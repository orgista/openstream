import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Credits and the content statement the App Store build has to carry.
///
/// TMDB's API terms require its logo and the exact notice below wherever the
/// app credits its metadata; TMDB's watch-provider data comes from JustWatch,
/// which asks for its own credit wherever that data is shown. OpenStream ships
/// no content, and the empty states say so in one line.
public enum AppleAttribution {
    public static let tmdbNotice = "This product uses the TMDB API but is not endorsed or certified by TMDB."
    public static let justWatchCredit = "Streaming availability data by JustWatch"
    public static let noContentDisclaimer = "OpenStream doesn't provide any content. Add your own sources."
}

/// The TMDB logo as TMDB publishes it (unaltered, bundled so About works
/// offline), followed by its required notice.
struct AppleTMDBAttributionRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let logo = Self.logo {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(height: logoHeight)
                    .accessibilityLabel("TMDB")
            }
            Text(AppleAttribution.tmdbNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.about.tmdb")
    }

    /// Read from the copied resource folder by path: a loose PNG in a
    /// `.copy` folder is not found by `Image(_:bundle:)`.
    static let logo: Image? = {
        guard let url = Bundle.module.url(forResource: "tmdb", withExtension: "png", subdirectory: "Attribution") else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }()

    private var logoHeight: CGFloat {
        #if os(tvOS)
        24
        #else
        14
        #endif
    }
}
