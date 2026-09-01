#include "immersive_video_session.hpp"

#include <algorithm>
#include <cassert>
#include <cmath>

using namespace openstream::xr;

namespace {

RuntimeCapabilities fullCapabilities() {
    return {
        .maxDecodeWidth = 8192,
        .maxDecodeHeight = 8192,
        .projection = {
            .flat = true,
            .equirectangular180 = true,
            .equirectangular360 = true,
            .fisheye180 = true,
            .cubemap360 = true,
            .wideFieldOfView = true,
        },
        .stereo = {
            .mono = true,
            .sideBySide = true,
            .topBottom = true,
            .multiview = true,
        },
        .codec = {
            .h264 = true,
            .hevc = true,
            .av1 = true,
            .vp9 = true,
        },
        .dynamicRange = {
            .sdr = true,
            .hdr10 = true,
            .hdr10Plus = true,
            .hlg = true,
            .dolbyVision = true,
        },
        .audio = {
            .standard = true,
            .spatial = true,
            .dolbyAtmos = true,
        },
    };
}

MediaSpec immersiveSpec() {
    return {
        .projection = Projection::Equirectangular360,
        .stereo = StereoLayout::SideBySide,
        .codec = VideoCodec::HEVC,
        .dynamicRange = DynamicRange::HDR10,
        .audio = AudioMode::DolbyAtmos,
        .decodedWidth = 7680,
        .decodedHeight = 3840,
        .durationSeconds = 120.0,
        .live = false,
    };
}

void assertNear(double actual, double expected) {
    assert(std::abs(actual - expected) < 0.0001);
}

}  // namespace

int main() {
    {
        ImmersiveVideoSession session;
        const auto result = session.prepare(immersiveSpec(), fullCapabilities(), 8, 16);
        assert(result.accepted());
        assert(result.reason == RejectionReason::None);
        assert(session.state() == SessionState::Ready);
        assert(result.plan != nullptr);
        assert(!result.plan->layeredTexture);
        assert(result.plan->left.textureLayer == 0);
        assert(result.plan->right.textureLayer == 0);
        assert(result.plan->left.mesh.vertices.size() == 9 * 17);
        assert(result.plan->right.mesh.vertices.size() == 9 * 17);
        for (const auto& vertex : result.plan->left.mesh.vertices) assert(vertex.u <= 0.5F);
        for (const auto& vertex : result.plan->right.mesh.vertices) assert(vertex.u >= 0.5F);
    }

    {
        auto media = immersiveSpec();
        media.stereo = StereoLayout::Multiview;
        ImmersiveVideoSession session;
        const auto result = session.prepare(media, fullCapabilities(), 6, 12);
        assert(result.accepted());
        assert(result.plan->layeredTexture);
        assert(result.plan->left.textureLayer == 0);
        assert(result.plan->right.textureLayer == 1);
        assert(result.plan->left.mesh.vertices.front().u == result.plan->right.mesh.vertices.front().u);
    }

    {
        const auto media = immersiveSpec();
        auto capabilities = fullCapabilities();
        ImmersiveVideoSession session;

        capabilities.maxDecodeWidth = 4096;
        assert(session.prepare(media, capabilities).reason == RejectionReason::ResolutionExceeded);

        capabilities = fullCapabilities();
        capabilities.projection.equirectangular360 = false;
        assert(session.prepare(media, capabilities).reason == RejectionReason::ProjectionUnsupported);

        capabilities = fullCapabilities();
        capabilities.stereo.sideBySide = false;
        assert(session.prepare(media, capabilities).reason == RejectionReason::StereoUnsupported);

        capabilities = fullCapabilities();
        capabilities.codec.hevc = false;
        assert(session.prepare(media, capabilities).reason == RejectionReason::CodecUnsupported);

        capabilities = fullCapabilities();
        capabilities.dynamicRange.hdr10 = false;
        assert(session.prepare(media, capabilities).reason == RejectionReason::DynamicRangeUnsupported);

        capabilities = fullCapabilities();
        capabilities.audio.dolbyAtmos = false;
        assert(session.prepare(media, capabilities).reason == RejectionReason::AudioUnsupported);
    }

    {
        ImmersiveVideoSession session;
        assert(!session.play());
        assert(session.prepare(immersiveSpec(), fullCapabilities()).accepted());
        assert(session.play());
        assert(session.state() == SessionState::Playing);
        session.advance(12.5);
        assertNear(session.positionSeconds(), 12.5);
        assert(session.pause());
        session.advance(10.0);
        assertNear(session.positionSeconds(), 12.5);
        assert(session.seek(200.0));
        assertNear(session.positionSeconds(), 120.0);
        assert(session.state() == SessionState::Ended);
        assert(session.play());
        assert(session.state() == SessionState::Playing);
        assertNear(session.positionSeconds(), 0.0);
        session.stop();
        assert(session.state() == SessionState::Idle);
        assertNear(session.positionSeconds(), 0.0);
        assert(!session.plan().has_value());
    }

    {
        auto live = immersiveSpec();
        live.durationSeconds = 0.0;
        live.live = true;
        ImmersiveVideoSession session;
        assert(session.prepare(live, fullCapabilities()).accepted());
        assert(!session.seek(10.0));
        assert(session.play());
        session.advance(3.0);
        assertNear(session.positionSeconds(), 3.0);
    }

    {
        auto invalid = immersiveSpec();
        invalid.decodedWidth = 0;
        ImmersiveVideoSession session;
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::InvalidMedia);
        assert(session.state() == SessionState::Idle);

        invalid = immersiveSpec();
        invalid.decodedHeight = 0;
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::InvalidMedia);

        invalid = immersiveSpec();
        invalid.durationSeconds = -5.0;
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::InvalidMedia);

        invalid = immersiveSpec();
        invalid.durationSeconds = std::numeric_limits<double>::quiet_NaN();
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::InvalidMedia);

        invalid = immersiveSpec();
        invalid.durationSeconds = std::numeric_limits<double>::infinity();
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::InvalidMedia);

        invalid = immersiveSpec();
        invalid.durationSeconds = 0.0;
        invalid.live = false;
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::InvalidMedia);

        invalid = immersiveSpec();
        invalid.codec = VideoCodec::Unknown;
        assert(session.prepare(invalid, fullCapabilities()).reason == RejectionReason::CodecUnsupported);

        // Verify invalid segment counts cause prepare to safely reject
        const auto validMedia = immersiveSpec();
        assert(session.prepare(validMedia, fullCapabilities(), 0, 10).reason == RejectionReason::InvalidMedia);
        assert(session.prepare(validMedia, fullCapabilities(), 10, 0).reason == RejectionReason::InvalidMedia);
        assert(session.prepare(validMedia, fullCapabilities(), 2000, 100).reason == RejectionReason::InvalidMedia);
        assert(session.prepare(validMedia, fullCapabilities(), 50, 5000).reason == RejectionReason::InvalidMedia);
    }

    {
        ImmersiveVideoSession session;
        assert(session.prepare(immersiveSpec(), fullCapabilities()).accepted());
        assert(session.play());

        // NaN and negative seeking should fail gracefully without altering position
        assert(!session.seek(std::numeric_limits<double>::quiet_NaN()));
        assertNear(session.positionSeconds(), 0.0);

        // Advance with non-finite or negative delta should be safely ignored
        session.advance(std::numeric_limits<double>::quiet_NaN());
        assertNear(session.positionSeconds(), 0.0);
        session.advance(-10.0);
        assertNear(session.positionSeconds(), 0.0);
        session.advance(0.0);
        assertNear(session.positionSeconds(), 0.0);

        // Negative seek should clamp to 0.0
        assert(session.seek(-10.0));
        assertNear(session.positionSeconds(), 0.0);
    }

    return 0;
}
