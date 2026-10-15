import SwiftUI

@MainActor
struct AppleTitlePageOptionalTasks: View {
    let enabled: Bool
    let itemID: String
    let generation: UUID
    let resolvedMediaID: String?
    let detailsAnswered: Bool
    let episodeCount: Int
    let loadPreview: @MainActor @Sendable () async -> Void
    let loadWatchProviders: @MainActor @Sendable () async -> Void
    let loadArtwork: @MainActor @Sendable () async -> Void
    let recordEpisodes: @MainActor @Sendable () async -> Void

    var body: some View {
        Color.clear
            .task(id: "preview:\(itemID):\(generation)") {
                guard enabled else { return }
                await loadPreview()
            }
            .task(id: "watch:\(generation):\(resolvedMediaID ?? "")") {
                guard enabled, resolvedMediaID != nil else { return }
                await loadWatchProviders()
            }
            .task(id: "art:\(generation):\(resolvedMediaID ?? ""):\(detailsAnswered)") {
                guard enabled else { return }
                await loadArtwork()
            }
            .task(id: "episodes:\(generation):\(episodeCount)") {
                guard enabled else { return }
                await recordEpisodes()
            }
            .accessibilityHidden(true)
    }
}
