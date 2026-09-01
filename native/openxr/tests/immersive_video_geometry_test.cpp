#include "immersive_video_geometry.hpp"

#include <cassert>
#include <cmath>

using namespace openstream::xr;

int main() {
    const auto sphere = makeImmersiveVideoMesh(
        Projection::Equirectangular360, StereoLayout::Mono, Eye::Left, 8, 16
    );
    assert(sphere.vertices.size() == 9 * 17);
    assert(sphere.indices.size() == 8 * 16 * 6);
    for (const auto& vertex : sphere.vertices) {
        assert(vertex.u >= 0.0F && vertex.u <= 1.0F);
        assert(vertex.v >= 0.0F && vertex.v <= 1.0F);
        const float length = std::sqrt(vertex.x * vertex.x + vertex.y * vertex.y + vertex.z * vertex.z);
        assert(std::abs(length - 1.0F) < 0.0001F);
    }

    const auto left = makeImmersiveVideoMesh(
        Projection::Equirectangular180, StereoLayout::SideBySide, Eye::Left, 6, 12
    );
    const auto right = makeImmersiveVideoMesh(
        Projection::Equirectangular180, StereoLayout::SideBySide, Eye::Right, 6, 12
    );
    for (const auto& vertex : left.vertices) assert(vertex.u <= 0.5F);
    for (const auto& vertex : right.vertices) assert(vertex.u >= 0.5F);

    const auto top = makeImmersiveVideoMesh(
        Projection::Fisheye180, StereoLayout::TopBottom, Eye::Left, 6, 12
    );
    const auto bottom = makeImmersiveVideoMesh(
        Projection::Fisheye180, StereoLayout::TopBottom, Eye::Right, 6, 12
    );
    for (const auto& vertex : top.vertices) assert(vertex.v <= 0.5F);
    for (const auto& vertex : bottom.vertices) assert(vertex.v >= 0.5F);

    const auto cube = makeImmersiveVideoMesh(
        Projection::Cubemap360, StereoLayout::Mono, Eye::Left
    );
    assert(cube.vertices.size() == 24);
    assert(cube.indices.size() == 36);

    const auto flat = makeImmersiveVideoMesh(Projection::Flat, StereoLayout::Mono, Eye::Left);
    assert(flat.vertices.size() == 4);
    assert(flat.indices.size() == 6);

    // Test minimum boundary (2x3 segments)
    const auto minMesh = makeImmersiveVideoMesh(
        Projection::Equirectangular360, StereoLayout::Mono, Eye::Left,
        kMinLatitudeSegments, kMinLongitudeSegments
    );
    assert(minMesh.vertices.size() == (kMinLatitudeSegments + 1) * (kMinLongitudeSegments + 1));
    assert(minMesh.indices.size() == kMinLatitudeSegments * kMinLongitudeSegments * 6);

    // Test 180° projection underflow clamping for small/odd longitude segments
    const auto eq180Small = makeImmersiveVideoMesh(
        Projection::Equirectangular180, StereoLayout::Mono, Eye::Left, 2, 3
    );
    assert(!eq180Small.vertices.empty());
    assert(!eq180Small.indices.empty());

    const auto fish180Small = makeImmersiveVideoMesh(
        Projection::Fisheye180, StereoLayout::Mono, Eye::Left, 4, 4
    );
    assert(!fish180Small.vertices.empty());
    assert(!fish180Small.indices.empty());

    const auto eq180Odd = makeImmersiveVideoMesh(
        Projection::Equirectangular180, StereoLayout::Mono, Eye::Left, 4, 5
    );
    assert(!eq180Odd.vertices.empty());
    assert(!eq180Odd.indices.empty());

    // Test rejection of invalid segment counts (< min or > max)
    auto expectInvalidArgument = [](Projection proj, std::uint32_t lat, std::uint32_t lon) {
        bool threw = false;
        try {
            (void) makeImmersiveVideoMesh(proj, StereoLayout::Mono, Eye::Left, lat, lon);
        } catch (const std::invalid_argument&) {
            threw = true;
        }
        assert(threw);
    };

    expectInvalidArgument(Projection::Equirectangular360, 0, 10);
    expectInvalidArgument(Projection::Equirectangular360, 1, 10);
    expectInvalidArgument(Projection::Equirectangular360, 10, 0);
    expectInvalidArgument(Projection::Equirectangular360, 10, 1);
    expectInvalidArgument(Projection::Equirectangular360, 10, 2);
    expectInvalidArgument(Projection::Equirectangular360, kMaxLatitudeSegments + 1, 100);
    expectInvalidArgument(Projection::Equirectangular360, 50, kMaxLongitudeSegments + 1);
    expectInvalidArgument(Projection::Equirectangular360, 65536, 65536);
    expectInvalidArgument(Projection::Equirectangular180, 0, 10);
    expectInvalidArgument(Projection::Equirectangular180, 50, kMaxLongitudeSegments + 1);
    expectInvalidArgument(Projection::Fisheye180, kMaxLatitudeSegments + 1, 50);

    return 0;
}
