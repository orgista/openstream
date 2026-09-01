#include "quest_launch_media.hpp"

#include <cassert>

using openstream::quest::LaunchMetadata;
using openstream::quest::makeLaunchMedia;
using openstream::xr::AudioMode;
using openstream::xr::DynamicRange;
using openstream::xr::Projection;
using openstream::xr::StereoLayout;
using openstream::xr::VideoCodec;

int main() {
    const auto immersive = makeLaunchMedia(
        "https://media.example/movie_360_sbs.mp4",
        LaunchMetadata{.codec = "hevc"}
    );
    assert(immersive.has_value());
    assert(immersive->spec.projection == Projection::Equirectangular360);
    assert(immersive->spec.stereo == StereoLayout::SideBySide);
    assert(immersive->spec.codec == VideoCodec::HEVC);
    assert(immersive->spec.dynamicRange == DynamicRange::SDR);
    assert(immersive->spec.decodedWidth == 4096);
    assert(immersive->spec.decodedHeight == 2048);
    assert(immersive->spec.live);

    const auto explicitHdr = makeLaunchMedia(
        "content://openstream/movie_hdr10.mp4",
        LaunchMetadata{
            .projection = "vr180",
            .stereo = "top-bottom",
            .codec = "av01",
            .dynamicRange = "Dolby Vision",
            .audio = "Dolby Atmos",
            .width = 7680,
            .height = 3840,
            .durationSeconds = 120.0,
        }
    );
    assert(explicitHdr.has_value());
    assert(explicitHdr->spec.projection == Projection::Fisheye180);
    assert(explicitHdr->spec.stereo == StereoLayout::TopBottom);
    assert(explicitHdr->spec.codec == VideoCodec::AV1);
    assert(explicitHdr->spec.dynamicRange == DynamicRange::DolbyVision);
    assert(explicitHdr->spec.audio == AudioMode::DolbyAtmos);
    assert(explicitHdr->spec.decodedWidth == 7680);
    assert(explicitHdr->spec.decodedHeight == 3840);
    assert(!explicitHdr->spec.live);

    const auto filenameDoesNotEnableHdr = makeLaunchMedia(
        "file:///sdcard/video_dolby_vision_hdr10.mp4",
        {}
    );
    assert(filenameDoesNotEnableHdr.has_value());
    assert(filenameDoesNotEnableHdr->spec.dynamicRange == DynamicRange::SDR);

    assert(!makeLaunchMedia("", {}).has_value());

    // Duration validation tests (negative, NaN, Inf)
    assert(!makeLaunchMedia("https://media.example/test.mp4", LaunchMetadata{.durationSeconds = -1.0}).has_value());
    assert(!makeLaunchMedia("https://media.example/test.mp4", LaunchMetadata{.durationSeconds = -100.0}).has_value());
    assert(!makeLaunchMedia("https://media.example/test.mp4", LaunchMetadata{.durationSeconds = std::numeric_limits<double>::quiet_NaN()}).has_value());
    assert(!makeLaunchMedia("https://media.example/test.mp4", LaunchMetadata{.durationSeconds = std::numeric_limits<double>::infinity()}).has_value());
    assert(!makeLaunchMedia("https://media.example/test.mp4", LaunchMetadata{.durationSeconds = -std::numeric_limits<double>::infinity()}).has_value());

    // Projection defaults tests
    const auto cubemap = makeLaunchMedia("eac_video.mp4", LaunchMetadata{});
    assert(cubemap.has_value());
    assert(cubemap->spec.projection == Projection::Cubemap360);
    assert(cubemap->spec.decodedWidth == 3840);
    assert(cubemap->spec.decodedHeight == 2160);

    const auto flat = makeLaunchMedia("normal_2d_movie.mp4", LaunchMetadata{});
    assert(flat.has_value());
    assert(flat->spec.projection == Projection::Flat);
    assert(flat->spec.decodedWidth == 1920);
    assert(flat->spec.decodedHeight == 1080);

    const auto wide = makeLaunchMedia("panorama_clip.mp4", LaunchMetadata{});
    assert(wide.has_value());
    assert(wide->spec.projection == Projection::WideFieldOfView);
    assert(wide->spec.decodedWidth == 2560);
    assert(wide->spec.decodedHeight == 1080);

    // Stereo layout inference tests
    const auto multiview = makeLaunchMedia("https://example.com/video.mp4", LaunchMetadata{.stereo = "mv-hevc spatial-hevc"});
    assert(multiview.has_value());
    assert(multiview->spec.stereo == StereoLayout::Multiview);

    // Codec inference tests
    const auto vp9Media = makeLaunchMedia("https://example.com/stream", LaunchMetadata{.codec = "vp09"});
    assert(vp9Media.has_value());
    assert(vp9Media->spec.codec == VideoCodec::VP9);

    const auto h264Media = makeLaunchMedia("https://example.com/stream", LaunchMetadata{.codec = "avc1"});
    assert(h264Media.has_value());
    assert(h264Media->spec.codec == VideoCodec::H264);

    // Audio mode inference tests
    const auto spatialAudio = makeLaunchMedia("https://example.com/stream", LaunchMetadata{.audio = "ambisonic spatial"});
    assert(spatialAudio.has_value());
    assert(spatialAudio->spec.audio == AudioMode::Spatial);

    return 0;
}
