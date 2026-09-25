import Foundation

@MainActor
struct ApplePlaybackSourceOption: Identifiable {
    let id: URL
    /// Nil for a local file and for a stream that names no resolution.
    let tier: AppleStreamQualityTier?
    /// Builds the player for this source, starting at `resume` when given —
    /// how a quality switch keeps the viewer's place — or else at the saved
    /// position. Local files always start at their saved position.
    let prepare: (_ resume: Double?) async throws -> AppleStremioPlayerPresentation
}

/// The in-player quality picker over one title's candidates.
///
/// `automatic` is every source in the order Automatic plays them (local
/// files, then streams by `AppleStremioCandidateRanking.playbackOrder`), and
/// is what the automatic-fallback loop in `AppleStremioPlayerView` walks
/// after a failure. `byTier` is the same candidates ordered for one picked
/// resolution: that tier first, then the nearest ones.
@MainActor
struct ApplePlaybackSourceOptions {
    let tiers: [AppleStreamQualityTier]
    let automatic: [ApplePlaybackSourceOption]
    let byTier: [AppleStreamQualityTier: [ApplePlaybackSourceOption]]

    func order(for choice: AppleStreamQualityChoice) -> [ApplePlaybackSourceOption] {
        switch choice {
        case .automatic: automatic
        case .tier(let tier): byTier[tier] ?? automatic
        }
    }
}
