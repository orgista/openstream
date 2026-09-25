import Testing
@testable import OpenStreamApple

/// A card with no title of its own names itself, or VoiceOver reads a blank
/// link (the iPad's Featured posters, N49; every Apple TV poster, N41).
struct AppleCatalogCardAccessibilityTests {
    @Test func aCardThatDrawsNoTitleNamesItself() {
        #expect(AppleCatalogCardAccessibility.namesItself(drawsTitle: false))
    }

    /// Off Apple TV a titled card keeps its children combined, so the caption
    /// it draws is what VoiceOver reads.
    @Test func aTitledCardCombinesItsCaption() {
        #expect(AppleCatalogCardAccessibility.namesItself(drawsTitle: true) == false)
    }
}
