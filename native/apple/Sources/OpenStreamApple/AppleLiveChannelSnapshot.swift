import Foundation

/// One immutable projection per lineup/filter change. SwiftUI reads these
/// arrays directly instead of normalizing every channel during each render.
struct AppleLiveChannelSnapshot: Sendable {
    /// The group `AppleChannelProjection.premierGuideGroups` gives the curated
    /// lineup; anything it could not match lands in its sibling "Other" group.
    static let premierGroupName = "Premier Guide"

    let channels: [AppleIPTVChannel]
    let channelIDs: [String]
    let categories: [String]

    static func build(groups: [AppleIPTVChannelGroup], package: AppleLiveChannelPackage,
                      custom: AppleCustomChannelPackage, entries: [AppleChannelLineupEntry],
                      favoriteIDs: Set<String>, category: String) -> Self {
        let all = groups.flatMap(\.channels)
        let selected: [AppleIPTVChannel]
        switch package {
        case .custom: selected = custom.selected(from: all)
        case .everything: selected = all.filter { !AppleChannelVisibilityPolicy.isPlaceholder($0) }
        case .premierGuide: selected = AppleChannelVisibilityPolicy.deduplicatedEastChannels(all)
        }
        let index = AppleChannelLineupIndex(entries)

        // One fuzzy match per channel, reused by the category list, the
        // category filter and the Premier Guide ordering. These were three
        // separate passes over the whole lineup — `categoryByID`, then
        // `premierGuideGroups` (which also re-deduplicated an already
        // deduplicated list), then the grouping below — and on the owner's
        // 9376 channels they cost **761 ms** of the Live tab's start-up
        // (measured 2026-09-15).
        var entryByChannelID = [String: AppleChannelLineupEntry](minimumCapacity: selected.count)
        for channel in selected where entryByChannelID[channel.id] == nil {
            if let entry = index.match(channel.name) { entryByChannelID[channel.id] = entry }
        }

        var categoryByID = [String: String](minimumCapacity: entryByChannelID.count)
        for (id, entry) in entryByChannelID {
            categoryByID[id] = entry.category == "Local" ? "Locals" : entry.category
        }
        let available = Set(categoryByID.values)
        let order = ["News", "Sports", "Entertainment", "Kids", "Movies", "Premium", "Lifestyle", "Music", "International", "Locals"]
        let categories = ["All", "Favorites"] + order.filter { available.contains($0) }
        let channels: [AppleIPTVChannel]
        if category == "All" {
            if package == .premierGuide {
                // Premier Guide is the curated lineup — not the lineup plus
                // everything that failed to match it. `premierGuideGroups`
                // also returns an "Other" group, and flattening both put the
                // whole provider list back into the guide: 4749 of the owner's
                // 9376 channels, where the phone shows a few hundred (owner
                // 2026-09-14: "reduce the live line up to the premier safe
                // thing we did with iPhone and android"). Unmatched channels
                // stay reachable through Search and the Everything package.
                // Same ordering `premierGuideGroups` produced — one channel per
                // lineup number, by number then name — built from the matches
                // already in hand.
                var seenNumbers = Set<Int>()
                let numbered = selected.compactMap { channel -> (AppleChannelLineupEntry, AppleIPTVChannel)? in
                    guard let entry = entryByChannelID[channel.id],
                          seenNumbers.insert(entry.number).inserted else { return nil }
                    return (entry, channel)
                }.sorted {
                    $0.0.number == $1.0.number
                        ? $0.1.name.localizedCaseInsensitiveCompare($1.1.name) == .orderedAscending
                        : $0.0.number < $1.0.number
                }
                // Nothing matched the lineup — an empty guide would be worse
                // than an unfiltered one.
                channels = numbered.isEmpty ? selected : numbered.map(\.1)
            } else {
                channels = Dictionary(grouping: selected) { entryByChannelID[$0.id]?.category ?? "Other" }
                    .sorted { $0.key < $1.key }.flatMap(\.value)
            }
        } else if category == "Favorites" {
            channels = selected.filter { favoriteIDs.contains($0.id) }
        } else {
            channels = selected.filter { categoryByID[$0.id] == category }
        }
        return .init(channels: channels, channelIDs: channels.map(\.id), categories: categories)
    }
}
