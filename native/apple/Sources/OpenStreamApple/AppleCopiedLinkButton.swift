#if os(iOS)
import SwiftUI

struct AppleCopiedLinkButton: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            Text("Open Copied Link").accessibilityHidden(true)
            // PasteButton's native title cannot be renamed; keep its stock icon
            // and name the action beside it and in its accessibility label.
            PasteButton(payloadType: String.self) { values in
                if let value = values.first { query = value }
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Open Copied Link")
            .accessibilityIdentifier("search.openCopiedLink")
        }
        .padding()
    }
}
#endif
