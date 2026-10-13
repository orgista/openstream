import Foundation
import Testing
@testable import OpenStreamApple

struct AppleContinueWatchingMergeTests {
    struct Entry: Equatable { let id: String; let stamp: Int; let value: String }
    @Test func appendsReplacesInPlaceAndDropsRemovedEntries() {
        let old = [Entry(id: "a", stamp: 2, value: "old"), Entry(id: "b", stamp: 1, value: "b")]
        let fresh = [Entry(id: "b", stamp: 3, value: "new"), Entry(id: "c", stamp: 4, value: "c"),
                     Entry(id: "a", stamp: 1, value: "stale")]
        let merged = AppleContinueWatchingResolver.merge(old, incoming: fresh, id: { $0.id }, timestamp: { $0.stamp })
        #expect(merged.map(\.id) == ["a", "b", "c"])
        #expect(merged[0].value == "old")
        #expect(merged[1].value == "new")
        #expect(AppleContinueWatchingResolver.merge(merged, incoming: [fresh[0]], id: { $0.id }, timestamp: { $0.stamp }).map(\.id) == ["b"])
        #expect(AppleContinueWatchingResolver.merge(old, incoming: [old[0], old[0]], id: { $0.id }, timestamp: { $0.stamp }) == [old[0]])
    }
}
