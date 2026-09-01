#include "immersive_video_geometry.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace openstream::xr {
namespace {

constexpr float kPi = 3.14159265358979323846F;

void mapStereoUV(float& u, float& v, StereoLayout layout, Eye eye) {
    if (layout == StereoLayout::SideBySide) {
        u = u * 0.5F + (eye == Eye::Right ? 0.5F : 0.0F);
    } else if (layout == StereoLayout::TopBottom) {
        v = v * 0.5F + (eye == Eye::Right ? 0.5F : 0.0F);
    }
}

Mesh sphereMesh(
    float horizontalRadians,
    bool fisheye,
    StereoLayout stereo,
    Eye eye,
    std::uint32_t latitudeSegments,
    std::uint32_t longitudeSegments
) {
    if (latitudeSegments < kMinLatitudeSegments || longitudeSegments < kMinLongitudeSegments ||
        latitudeSegments > kMaxLatitudeSegments || longitudeSegments > kMaxLongitudeSegments) {
        throw std::invalid_argument(
            "immersive video mesh segment counts out of allowable range [2..1024, 3..2048]"
        );
    }

    Mesh mesh;
    mesh.vertices.reserve((latitudeSegments + 1) * (longitudeSegments + 1));
    mesh.indices.reserve(latitudeSegments * longitudeSegments * 6);
    for (std::uint32_t latitude = 0; latitude <= latitudeSegments; ++latitude) {
        const float v0 = static_cast<float>(latitude) / static_cast<float>(latitudeSegments);
        const float elevation = (0.5F - v0) * kPi;
        const float cosElevation = std::cos(elevation);
        for (std::uint32_t longitude = 0; longitude <= longitudeSegments; ++longitude) {
            const float u0 = static_cast<float>(longitude) / static_cast<float>(longitudeSegments);
            const float azimuth = (u0 - 0.5F) * horizontalRadians;
            float u = u0;
            float v = v0;
            if (fisheye) {
                const float forward = std::cos(azimuth) * cosElevation;
                const float theta = std::acos(std::clamp(forward, -1.0F, 1.0F));
                const float radial = theta / kPi;
                const float sinTheta = std::sin(theta);
                if (sinTheta > 0.00001F) {
                    u = 0.5F + radial * (std::sin(azimuth) * cosElevation / sinTheta);
                    v = 0.5F - radial * (std::sin(elevation) / sinTheta);
                } else {
                    u = 0.5F;
                    v = 0.5F;
                }
            }
            mapStereoUV(u, v, stereo, eye);
            // Winding faces inward because the viewer stands at the origin.
            mesh.vertices.push_back({
                -std::sin(azimuth) * cosElevation,
                std::sin(elevation),
                -std::cos(azimuth) * cosElevation,
                std::clamp(u, 0.0F, 1.0F),
                std::clamp(v, 0.0F, 1.0F),
            });
        }
    }

    const auto stride = longitudeSegments + 1;
    for (std::uint32_t latitude = 0; latitude < latitudeSegments; ++latitude) {
        for (std::uint32_t longitude = 0; longitude < longitudeSegments; ++longitude) {
            const auto topLeft = latitude * stride + longitude;
            const auto bottomLeft = (latitude + 1) * stride + longitude;
            mesh.indices.insert(mesh.indices.end(), {
                topLeft, topLeft + 1, bottomLeft,
                topLeft + 1, bottomLeft + 1, bottomLeft,
            });
        }
    }
    return mesh;
}

Mesh quadMesh(StereoLayout stereo, Eye eye, float width) {
    Mesh mesh{
        .vertices = {
            {-width, 1.0F, -2.0F, 0.0F, 0.0F},
            { width, 1.0F, -2.0F, 1.0F, 0.0F},
            {-width,-1.0F, -2.0F, 0.0F, 1.0F},
            { width,-1.0F, -2.0F, 1.0F, 1.0F},
        },
        .indices = {0, 1, 2, 1, 3, 2},
    };
    for (auto& vertex : mesh.vertices) mapStereoUV(vertex.u, vertex.v, stereo, eye);
    return mesh;
}

Mesh cubemapMesh(StereoLayout stereo, Eye eye) {
    // Equi-angular cubemap input uses a conventional 3x2 atlas. Each face has
    // independent vertices so its atlas cell never bleeds into a neighbor.
    constexpr float p = 1.0F;
    constexpr float positions[6][4][3] = {
        {{ p, p,-p},{ p, p, p},{ p,-p,-p},{ p,-p, p}},
        {{-p, p, p},{-p, p,-p},{-p,-p, p},{-p,-p,-p}},
        {{-p, p,-p},{ p, p,-p},{-p, p, p},{ p, p, p}},
        {{-p,-p, p},{ p,-p, p},{-p,-p,-p},{ p,-p,-p}},
        {{ p, p, p},{-p, p, p},{ p,-p, p},{-p,-p, p}},
        {{-p, p,-p},{ p, p,-p},{-p,-p,-p},{ p,-p,-p}},
    };
    Mesh mesh;
    mesh.vertices.reserve(24);
    mesh.indices.reserve(36);
    for (std::uint32_t face = 0; face < 6; ++face) {
        const float cellX = static_cast<float>(face % 3) / 3.0F;
        const float cellY = static_cast<float>(face / 3) / 2.0F;
        constexpr float faceUV[4][2] = {{0,0},{1,0},{0,1},{1,1}};
        for (std::uint32_t corner = 0; corner < 4; ++corner) {
            float u = cellX + faceUV[corner][0] / 3.0F;
            float v = cellY + faceUV[corner][1] / 2.0F;
            mapStereoUV(u, v, stereo, eye);
            mesh.vertices.push_back({
                positions[face][corner][0], positions[face][corner][1], positions[face][corner][2], u, v,
            });
        }
        const auto base = face * 4;
        mesh.indices.insert(mesh.indices.end(), {base, base + 1, base + 2, base + 1, base + 3, base + 2});
    }
    return mesh;
}

}  // namespace

Mesh makeImmersiveVideoMesh(
    Projection projection,
    StereoLayout stereo,
    Eye eye,
    std::uint32_t latitudeSegments,
    std::uint32_t longitudeSegments
) {
    if (latitudeSegments < kMinLatitudeSegments || longitudeSegments < kMinLongitudeSegments ||
        latitudeSegments > kMaxLatitudeSegments || longitudeSegments > kMaxLongitudeSegments) {
        throw std::invalid_argument(
            "immersive video mesh segment counts out of allowable range [2..1024, 3..2048]"
        );
    }

    switch (projection) {
        case Projection::Equirectangular180:
            return sphereMesh(
                kPi,
                false,
                stereo,
                eye,
                latitudeSegments,
                std::max(longitudeSegments / 2, kMinLongitudeSegments)
            );
        case Projection::Equirectangular360:
            return sphereMesh(kPi * 2.0F, false, stereo, eye, latitudeSegments, longitudeSegments);
        case Projection::Fisheye180:
            return sphereMesh(
                kPi,
                true,
                stereo,
                eye,
                latitudeSegments,
                std::max(longitudeSegments / 2, kMinLongitudeSegments)
            );
        case Projection::Cubemap360:
            return cubemapMesh(stereo, eye);
        case Projection::WideFieldOfView:
            return quadMesh(stereo, eye, 1.65F);
        case Projection::Flat:
            return quadMesh(stereo, eye, 1.0F);
    }
    throw std::invalid_argument("unsupported immersive video projection");
}

}  // namespace openstream::xr
