#if os(iOS)
import SwiftUI

struct AppleLivePhoneProgrammeInfo: View {
    let channel: AppleIPTVChannel
    let programme: AppleIPTVProgramme?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(channel.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            Text(programme?.title ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppleDesignTokens.spacingMedium)
        .padding(.vertical, AppleDesignTokens.spacingSmall)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live.stage.programme")
    }
}
#endif
