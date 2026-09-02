import SwiftUI

/// Primary action button for OpenStream: a white fill with a black label,
/// matching the launch screen, the store assets, and the web portal button.
///
/// It replaces `.borderedProminent`, which — under the app's white brand tint —
/// renders a white label on the white fill (the unreadable "white on white"
/// the owner reported on the Live tab's Open Settings button). The brand is
/// monochrome, so the accent is white and the primary button inverts to keep
/// contrast; nothing in the app reads as the iOS default blue.
public struct AppleBrandPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.white, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

public extension ButtonStyle where Self == AppleBrandPrimaryButtonStyle {
    static var brandPrimary: AppleBrandPrimaryButtonStyle { AppleBrandPrimaryButtonStyle() }
}
