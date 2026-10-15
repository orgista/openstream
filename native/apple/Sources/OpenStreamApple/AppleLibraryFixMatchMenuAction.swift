import SwiftUI

private struct AppleLibraryFixMatchActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var appleLibraryFixMatch: (@MainActor () -> Void)? {
        get { self[AppleLibraryFixMatchActionKey.self] }
        set { self[AppleLibraryFixMatchActionKey.self] = newValue }
    }
}

struct AppleLibraryFixMatchMenuAction: View {
    @Environment(\.appleLibraryFixMatch) private var fixMatch

    var body: some View {
        if let fixMatch {
            Button("Fix Match", systemImage: "pencil", action: fixMatch)
                .accessibilityIdentifier("detail.fixMatch")
        }
    }
}
