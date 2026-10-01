import Foundation

/// Where this install came from, read from the receipt Apple leaves in the
/// bundle: App Store installs carry a `receipt`, DEBUG builds usually none, and
/// a `sandboxReceipt` is carried by TestFlight installs **and** by the build
/// App Review runs. No runtime signal tells those two apart, so nothing that
/// must stay out of the reviewer's build may key off this; such behaviour is
/// compiled in DEBUG only (`AppleTestCatalogSeedPolicy`).
public enum AppleBuildChannel {
    /// TestFlight or App Review. Used only for the local interaction trace's
    /// default, which writes to the app's own Caches and never leaves the
    /// device unless the user shares it.
    public static var hasSandboxReceipt: Bool {
        isSandboxReceipt(Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }

    public static func isSandboxReceipt(_ lastPathComponent: String?) -> Bool {
        lastPathComponent == "sandboxReceipt"
    }
}

/// Whether this build pre-adds the testers' catalogs. DEBUG only: a Release
/// archive (TestFlight, App Review, App Store) starts with no sources at all,
/// and does not even contain the catalog addresses.
public enum AppleTestCatalogSeedPolicy {
    public static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    public static func seedsTestCatalogs(isDebugBuild: Bool) -> Bool {
        isDebugBuild
    }

    public static func manifests(isDebugBuild: Bool) -> [String] {
        guard isDebugBuild else { return [] }
        #if DEBUG
        return debugManifests
        #else
        return []
        #endif
    }

    #if DEBUG
    /// Add-ons every debug build starts with (owner, 2026-09-17: "add
    /// AIOmetadata add-on for testing"). Testers on TestFlight add it the way
    /// users do: paste the address, Web Management, or a backup.
    private static let debugManifests: [String] = [
        "https://aiometadata.elfhosted.com/stremio/6907d7b7-37cb-4b48-adaf-f40b9cdec53c/manifest.json",
    ]
    #endif
}
