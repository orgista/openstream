import SwiftUI

/// Live before its first lineup is on screen: one system spinner and its
/// status, in place of rows popping in (owner 2026-10-22). The stage above it
/// stays black until a channel is chosen.
struct AppleLiveChannelsLoading: View {
    var body: some View {
        ProgressView("Loading Channels")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("live.channels.loading")
    }
}

/// When the Live list shows `AppleLiveChannelsLoading` instead of rows.
enum AppleLiveChannelsLoadingPolicy {
    /// Loading only while nothing better can be shown: the first lineup has
    /// not answered, a reload runs with no failure on screen (a retry keeps
    /// the failure in place instead of flickering to the spinner and back),
    /// or the channels are in but not yet sorted. A sorted lineup that came
    /// out empty shows the empty state.
    static func showsLoading(hasRows: Bool, hasChannels: Bool, isLoading: Bool, hasResolvedFirstLoad: Bool,
                             showsFailure: Bool, snapshotIsCurrent: Bool) -> Bool {
        guard !hasRows else { return false }
        if hasChannels { return !snapshotIsCurrent }
        return !hasResolvedFirstLoad || (isLoading && !showsFailure)
    }
}
