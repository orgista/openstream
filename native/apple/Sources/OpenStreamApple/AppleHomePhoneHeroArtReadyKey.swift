import SwiftUI

struct AppleHomePhoneHeroArtReadyKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue() || value
    }
}
