#include "quest_compositor_video.hpp"

#include <GLES2/gl2ext.h>
#include <android/log.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>
#include <string>

namespace openstream::quest {
namespace {

constexpr const char* kLogTag = "OpenStreamQuest";

void logError(const char* message) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag, "%s", message);
}

GLuint compileShader(GLenum type, const char* source) {
    const GLuint shader = glCreateShader(type);
    if (shader == 0) return 0;
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled != GL_TRUE) {
        GLint logLength = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
        std::string log(static_cast<std::size_t>(std::max(logLength, 1)), '\0');
        glGetShaderInfoLog(shader, logLength, nullptr, log.data());
        __android_log_print(ANDROID_LOG_ERROR, kLogTag, "Video shader failed: %s", log.c_str());
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

}  // namespace

QuestCompositorVideo::~QuestCompositorVideo() {
    shutdown();
}

bool QuestCompositorVideo::initialize(
    XrSession session,
    XrSpace space,
    const VideoLayerPlan& plan,
    const xr::MediaSpec& media
) {
    shutdown();
    if (session == XR_NULL_HANDLE || space == XR_NULL_HANDLE || media.decodedWidth == 0 ||
        media.decodedHeight == 0 || !supportsCompositorPlayback(plan, media.stereo)) {
        return false;
    }
    session_ = session;
    space_ = space;
    const VideoPixelExtent outputExtent = compositorSwapchainExtent(media);
    width_ = outputExtent.width;
    height_ = outputExtent.height;
    sourceProjection_ = media.projection == xr::Projection::Fisheye180
        ? 1
        : (media.projection == xr::Projection::Cubemap360 ? 2 : 0);
    stereoLayout_ = media.stereo == xr::StereoLayout::SideBySide
        ? 1
        : (media.stereo == xr::StereoLayout::TopBottom ? 2 : 0);
    if (!createSwapchain() || !createCopyProgram()) {
        shutdown();
        return false;
    }
    configureLayers(plan, media);
    return !layerHeaders_.empty();
}

bool QuestCompositorVideo::createSwapchain() {
    std::uint32_t formatCount = 0;
    if (XR_FAILED(xrEnumerateSwapchainFormats(session_, 0, &formatCount, nullptr)) ||
        formatCount == 0) {
        return false;
    }
    std::vector<std::int64_t> formats(formatCount);
    if (XR_FAILED(xrEnumerateSwapchainFormats(
            session_,
            formatCount,
            &formatCount,
            formats.data()))) {
        return false;
    }
    constexpr std::array preferredFormats{
        static_cast<std::int64_t>(GL_SRGB8_ALPHA8),
        static_cast<std::int64_t>(GL_RGBA8),
    };
    std::int64_t selectedFormat = 0;
    for (const std::int64_t preferred : preferredFormats) {
        if (std::find(formats.begin(), formats.end(), preferred) != formats.end()) {
            selectedFormat = preferred;
            break;
        }
    }
    if (selectedFormat == 0) {
        logError("The Quest runtime does not expose an RGBA video-layer swapchain format.");
        return false;
    }

    XrSwapchainCreateInfo createInfo{};
    createInfo.type = XR_TYPE_SWAPCHAIN_CREATE_INFO;
    createInfo.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT |
        XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
    createInfo.format = selectedFormat;
    createInfo.sampleCount = 1;
    createInfo.width = width_;
    createInfo.height = height_;
    createInfo.faceCount = 1;
    createInfo.arraySize = 1;
    createInfo.mipCount = 1;
    if (XR_FAILED(xrCreateSwapchain(session_, &createInfo, &swapchain_))) return false;

    std::uint32_t imageCount = 0;
    if (XR_FAILED(xrEnumerateSwapchainImages(swapchain_, 0, &imageCount, nullptr)) ||
        imageCount == 0) {
        return false;
    }
    swapchainImages_.resize(imageCount);
    for (auto& image : swapchainImages_) image.type = XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR;
    return XR_SUCCEEDED(xrEnumerateSwapchainImages(
        swapchain_,
        imageCount,
        &imageCount,
        reinterpret_cast<XrSwapchainImageBaseHeader*>(swapchainImages_.data())
    ));
}

bool QuestCompositorVideo::createCopyProgram() {
    constexpr const char* vertexSource = R"glsl(#version 300 es
out vec2 videoUv;
const vec2 positions[4] = vec2[4](
    vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, 1.0)
);
const vec2 textureCoordinates[4] = vec2[4](
    vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0)
);
void main() {
    gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);
    videoUv = textureCoordinates[gl_VertexID];
}
)glsl";
    constexpr const char* fragmentSource = R"glsl(#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision highp float;
in vec2 videoUv;
layout(location = 0) out vec4 outputColor;
uniform samplerExternalOES videoTexture;
uniform mat4 videoTransform;
uniform int sourceProjection;
uniform int stereoLayout;

const float PI = 3.14159265358979323846;

void unpackStereoUv(vec2 packedUv, out vec2 localUv, out vec2 offset, out vec2 scale) {
    offset = vec2(0.0);
    scale = vec2(1.0);
    if (stereoLayout == 1) {
        scale.x = 0.5;
        offset.x = packedUv.x >= 0.5 ? 0.5 : 0.0;
    } else if (stereoLayout == 2) {
        scale.y = 0.5;
        offset.y = packedUv.y >= 0.5 ? 0.5 : 0.0;
    }
    localUv = (packedUv - offset) / scale;
}

vec2 fisheyeSourceUv(vec2 equirectUv) {
    float azimuth = (equirectUv.x - 0.5) * PI;
    float elevation = (0.5 - equirectUv.y) * PI;
    float cosElevation = cos(elevation);
    float forward = cos(azimuth) * cosElevation;
    float theta = acos(clamp(forward, -1.0, 1.0));
    float radial = theta / PI;
    float sinTheta = sin(theta);
    if (abs(sinTheta) < 0.00001) {
        return vec2(0.5);
    }
    return vec2(
        0.5 + radial * sin(azimuth) * cosElevation / sinTheta,
        0.5 - radial * sin(elevation) / sinTheta
    );
}

float eacCoordinate(float faceCoordinate) {
    float clampedFace = clamp(faceCoordinate, -1.0, 1.0);
    float uv = atan(clampedFace) / (PI * 0.5) + 0.5;
    return clamp(uv, 0.0, 1.0);
}

vec2 cubemapSourceUv(vec2 equirectUv) {
    float azimuth = (equirectUv.x - 0.5) * 2.0 * PI;
    float elevation = (0.5 - equirectUv.y) * PI;
    float cosElevation = cos(elevation);
    vec3 direction = vec3(
        -sin(azimuth) * cosElevation,
        sin(elevation),
        -cos(azimuth) * cosElevation
    );
    vec3 magnitude = abs(direction);
    int face = 0;
    vec2 faceCoordinate = vec2(0.0);
    if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z) {
        float denomX = max(magnitude.x, 1e-7);
        if (direction.x >= 0.0) {
            face = 0;
            faceCoordinate = vec2(direction.z, -direction.y) / denomX;
        } else {
            face = 1;
            faceCoordinate = vec2(-direction.z, -direction.y) / denomX;
        }
    } else if (magnitude.y >= magnitude.z) {
        float denomY = max(magnitude.y, 1e-7);
        if (direction.y >= 0.0) {
            face = 2;
            faceCoordinate = vec2(direction.x, direction.z) / denomY;
        } else {
            face = 3;
            faceCoordinate = vec2(direction.x, -direction.z) / denomY;
        }
    } else {
        float denomZ = max(magnitude.z, 1e-7);
        if (direction.z >= 0.0) {
            face = 4;
            faceCoordinate = vec2(-direction.x, -direction.y) / denomZ;
        } else {
            face = 5;
            faceCoordinate = vec2(direction.x, -direction.y) / denomZ;
        }
    }
    vec2 faceUv = vec2(
        eacCoordinate(faceCoordinate.x),
        eacCoordinate(faceCoordinate.y)
    );
    vec2 atlasCell = vec2(float(face % 3), float(face / 3));
    return (atlasCell + faceUv) / vec2(3.0, 2.0);
}

void main() {
    vec2 localUv;
    vec2 stereoOffset;
    vec2 stereoScale;
    unpackStereoUv(videoUv, localUv, stereoOffset, stereoScale);
    vec2 sourceUv = localUv;
    if (sourceProjection == 1) {
        sourceUv = fisheyeSourceUv(localUv);
    } else if (sourceProjection == 2) {
        sourceUv = cubemapSourceUv(localUv);
    }
    if (any(lessThan(sourceUv, vec2(0.0))) || any(greaterThan(sourceUv, vec2(1.0)))) {
        outputColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    vec2 packedSourceUv = stereoOffset + sourceUv * stereoScale;
    vec2 transformedUv = (videoTransform * vec4(packedSourceUv, 0.0, 1.0)).xy;
    outputColor = texture(videoTexture, transformedUv);
}
)glsl";

    const GLuint vertexShader = compileShader(GL_VERTEX_SHADER, vertexSource);
    const GLuint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentSource);
    if (vertexShader == 0 || fragmentShader == 0) {
        if (vertexShader != 0) glDeleteShader(vertexShader);
        if (fragmentShader != 0) glDeleteShader(fragmentShader);
        return false;
    }

    copyProgram_ = glCreateProgram();
    glAttachShader(copyProgram_, vertexShader);
    glAttachShader(copyProgram_, fragmentShader);
    glLinkProgram(copyProgram_);
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    GLint linked = GL_FALSE;
    glGetProgramiv(copyProgram_, GL_LINK_STATUS, &linked);
    if (linked != GL_TRUE) {
        logError("The Quest video texture copy program could not be linked.");
        return false;
    }
    transformUniform_ = glGetUniformLocation(copyProgram_, "videoTransform");
    projectionUniform_ = glGetUniformLocation(copyProgram_, "sourceProjection");
    stereoUniform_ = glGetUniformLocation(copyProgram_, "stereoLayout");
    const GLint textureUniform = glGetUniformLocation(copyProgram_, "videoTexture");
    glUseProgram(copyProgram_);
    glUniform1i(textureUniform, 0);
    glUseProgram(0);
    glGenFramebuffers(1, &framebuffer_);
    return transformUniform_ >= 0 && projectionUniform_ >= 0 && stereoUniform_ >= 0 &&
        textureUniform >= 0 && framebuffer_ != 0;
}

XrSwapchainSubImage QuestCompositorVideo::subImageForEye(
    xr::StereoLayout stereo,
    xr::Eye eye
) const {
    const VideoPixelRect crop = videoPixelRectForEye(width_, height_, stereo, eye);
    const XrRect2Di rectangle{
        .offset = {crop.x, crop.y},
        .extent = {crop.width, crop.height},
    };
    return {
        .swapchain = swapchain_,
        .imageRect = rectangle,
        .imageArrayIndex = 0,
    };
}

void QuestCompositorVideo::configureLayers(
    const VideoLayerPlan& plan,
    const xr::MediaSpec& media
) {
    layerHeaders_.clear();
    const bool stereo = media.stereo != xr::StereoLayout::Mono;
    const std::uint32_t layerCount = stereo ? 2U : 1U;
    for (std::uint32_t index = 0; index < layerCount; ++index) {
        const xr::Eye eye = index == 0 ? xr::Eye::Left : xr::Eye::Right;
        const XrEyeVisibility visibility = stereo
            ? (eye == xr::Eye::Left ? XR_EYE_VISIBILITY_LEFT : XR_EYE_VISIBILITY_RIGHT)
            : XR_EYE_VISIBILITY_BOTH;
        if (plan.kind == LayerKind::Quad) {
            XrCompositionLayerQuad& layer = quadLayers_[index];
            layer = {};
            layer.type = XR_TYPE_COMPOSITION_LAYER_QUAD;
            layer.space = space_;
            layer.eyeVisibility = visibility;
            layer.subImage = subImageForEye(media.stereo, eye);
            layer.pose.orientation.w = 1.0F;
            layer.pose.position.z = -2.5F;
            layer.size.height = 2.0F;
            layer.size.width = compositorQuadWidth(media);
            layerHeaders_.push_back(
                reinterpret_cast<const XrCompositionLayerBaseHeader*>(&layer)
            );
        } else {
            XrCompositionLayerEquirect2KHR& layer = equirectLayers_[index];
            layer = {};
            layer.type = XR_TYPE_COMPOSITION_LAYER_EQUIRECT2_KHR;
            layer.space = space_;
            layer.eyeVisibility = visibility;
            layer.subImage = subImageForEye(media.stereo, eye);
            layer.pose.orientation.w = 1.0F;
            layer.radius = 10.0F;
            layer.centralHorizontalAngle =
                (media.projection == xr::Projection::Equirectangular180 ||
                 media.projection == xr::Projection::Fisheye180)
                ? std::numbers::pi_v<float>
                : 2.0F * std::numbers::pi_v<float>;
            layer.upperVerticalAngle = std::numbers::pi_v<float> / 2.0F;
            layer.lowerVerticalAngle = -std::numbers::pi_v<float> / 2.0F;
            layerHeaders_.push_back(
                reinterpret_cast<const XrCompositionLayerBaseHeader*>(&layer)
            );
        }
    }
}

bool QuestCompositorVideo::renderExternalTexture(
    GLuint externalTexture,
    const std::array<float, 16>& transform
) {
    if (!ready() || externalTexture == 0 || copyProgram_ == 0 || framebuffer_ == 0) return false;

    std::uint32_t imageIndex = 0;
    XrSwapchainImageAcquireInfo acquireInfo{};
    acquireInfo.type = XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO;
    if (XR_FAILED(xrAcquireSwapchainImage(swapchain_, &acquireInfo, &imageIndex))) return false;

    XrSwapchainImageWaitInfo waitInfo{};
    waitInfo.type = XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO;
    waitInfo.timeout = XR_INFINITE_DURATION;
    if (XR_FAILED(xrWaitSwapchainImage(swapchain_, &waitInfo))) {
        XrSwapchainImageReleaseInfo releaseInfo{};
        releaseInfo.type = XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO;
        (void) xrReleaseSwapchainImage(swapchain_, &releaseInfo);
        return false;
    }

    if (imageIndex >= swapchainImages_.size()) {
        XrSwapchainImageReleaseInfo releaseInfo{};
        releaseInfo.type = XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO;
        (void) xrReleaseSwapchainImage(swapchain_, &releaseInfo);
        return false;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
    glFramebufferTexture2D(
        GL_FRAMEBUFFER,
        GL_COLOR_ATTACHMENT0,
        GL_TEXTURE_2D,
        swapchainImages_[imageIndex].image,
        0
    );
    const bool framebufferComplete = glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
        GL_FRAMEBUFFER_COMPLETE;
    if (framebufferComplete) {
        glViewport(0, 0, static_cast<GLsizei>(width_), static_cast<GLsizei>(height_));
        glDisable(GL_BLEND);
        glDisable(GL_CULL_FACE);
        glDisable(GL_DEPTH_TEST);
        glUseProgram(copyProgram_);
        glUniformMatrix4fv(transformUniform_, 1, GL_FALSE, transform.data());
        glUniform1i(projectionUniform_, sourceProjection_);
        glUniform1i(stereoUniform_, stereoLayout_);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_EXTERNAL_OES, externalTexture);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glBindTexture(GL_TEXTURE_EXTERNAL_OES, 0);
        glUseProgram(0);
        glFlush();
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    XrSwapchainImageReleaseInfo releaseInfo{};
    releaseInfo.type = XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO;
    const bool released = XR_SUCCEEDED(xrReleaseSwapchainImage(swapchain_, &releaseInfo));
    return framebufferComplete && released && glGetError() == GL_NO_ERROR;
}

void QuestCompositorVideo::shutdown() {
    layerHeaders_.clear();
    if (framebuffer_ != 0) glDeleteFramebuffers(1, &framebuffer_);
    if (copyProgram_ != 0) glDeleteProgram(copyProgram_);
    framebuffer_ = 0;
    copyProgram_ = 0;
    transformUniform_ = -1;
    projectionUniform_ = -1;
    stereoUniform_ = -1;
    sourceProjection_ = 0;
    stereoLayout_ = 0;
    swapchainImages_.clear();
    if (swapchain_ != XR_NULL_HANDLE) xrDestroySwapchain(swapchain_);
    swapchain_ = XR_NULL_HANDLE;
    session_ = XR_NULL_HANDLE;
    space_ = XR_NULL_HANDLE;
    width_ = 0;
    height_ = 0;
}

}  // namespace openstream::quest
