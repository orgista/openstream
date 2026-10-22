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
}
