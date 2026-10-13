import Foundation
import Testing
@testable import OpenStreamApple

struct AppleShelfDedupeTests {
    @Test func previousThreeDisplayedRowsAndWithinRow() {
        let rows = [["a", "a", "b"], ["b", "c"], ["d"], ["a", "e"], ["a", "b", "f"]]
        #expect(AppleCatalogShelfPolicy.deduplicatedRows(rows) == [["a", "b"], ["c"], ["d"], ["e"], ["a", "b", "f"]])
    }
    @Test func removedDuplicatesDoNotExtendTheirOwnWindow() {
        #expect(AppleCatalogShelfPolicy.deduplicatedRows([["a"], ["a"], [], [], ["a"]]) == [["a"], [], [], [], ["a"]])
    }
    @Test func aDeduplicatedTailStillReachesThePagingBoundary() {
        let raw = (0..<10).map { AppleCatalogItem(mediaID: "item\($0)", type: "movie", name: "Item \($0)") }
        let allowed = Set(raw.prefix(5).map { AppleRecommendationInputs.identity($0) })
        let visible = AppleCatalogShelfPolicy.visibleItems(raw, allowed: allowed)
        #expect(visible.map(\.id) == Array(raw.prefix(5)).map(\.id))
        #expect(AppleCatalogPaging.isNearEnd(itemID: raw[4].id, in: raw) == false)
        #expect(AppleCatalogPaging.isNearEnd(itemID: raw[4].id, in: visible))
    }

    #if OPENSTREAM_ADDONS
    @Test func opaqueProviderIDsStaySeparateWhileStrongIDsDeduplicate() throws {
        let urlA = try #require(URL(string: "https://fixture.example/a/manifest.json"))
        let a = AppleSource(kind: .stremio, name: "A", url: urlA)
        let urlB = try #require(URL(string: "https://fixture.example/b/manifest.json"))
        let b = AppleSource(kind: .stremio, name: "B", url: urlB)
        let opaque = AppleCatalogItem(mediaID: "1", type: "movie", name: "Unknown year")
        let keyA = AppleCatalogShelfPolicy.identity(opaque, source: a)
        let keyB = AppleCatalogShelfPolicy.identity(opaque, source: b)
        #expect(keyA != keyB)
        #expect(AppleCatalogShelfPolicy.deduplicatedRows([[keyA], [keyB]]) == [[keyA], [keyB]])
        #expect(AppleCatalogShelfPolicy.visibleItems([opaque], allowed: [keyA], source: a) == [opaque])
        let strong = AppleCatalogItem(mediaID: "tt1234567", type: "movie", name: "Same film")
        let strongA = AppleCatalogShelfPolicy.identity(strong, source: a)
        let strongB = AppleCatalogShelfPolicy.identity(strong, source: b)
        #expect(strongA == strongB)
        #expect(AppleCatalogShelfPolicy.deduplicatedRows([[strongA], [strongB]]) == [[strongA], []])
    }
    #endif

}
