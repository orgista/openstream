import Foundation

/// Whether a Stremio add-on's manifest URL carries the viewer's own sign-in.
///
/// An unconfigured add-on (`https://v3-cinemeta.strem.io/manifest.json`) has
/// the same address for everyone, so the iCloud snapshot can carry it in full
/// and it restores enabled. A configured add-on puts its options, and often a
/// debrid or API key, in a path segment before `manifest.json`
/// (`/realdebrid=…|sort=…/manifest.json`, a base64 or JSON blob); that address
/// is a secret and only ever travels sealed.
public enum AppleAddonURLSecretPolicy {
    /// True unless the URL is a plain http(s) manifest address with no
    /// userinfo, query, fragment or configuration segment.
    public static func isSecret(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty else { return true }
        if parts.user != nil || parts.password != nil { return true }
        if let query = parts.percentEncodedQuery, !query.isEmpty { return true }
        if let fragment = parts.percentEncodedFragment, !fragment.isEmpty { return true }
        let segments = parts.percentEncodedPath.split(separator: "/").map(String.init)
        guard segments.last?.lowercased() == "manifest.json" else { return true }
        return segments.dropLast().contains(where: isConfigurationSegment)
    }

    /// For an add-on's other addresses (its logo): secret when it has
    /// userinfo, a query, or a configuration segment anywhere before its file name.
    public static func isSecretAsset(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty else { return true }
        if parts.user != nil || parts.password != nil { return true }
        if let query = parts.percentEncodedQuery, !query.isEmpty { return true }
        return parts.percentEncodedPath.split(separator: "/").map(String.init).dropLast()
            .contains(where: isConfigurationSegment)
    }

    /// A path segment that holds add-on options rather than a plain folder
    /// name: long (base64, keys), JSON-ish or key=value, or naming a debrid
    /// service or key.
    static func isConfigurationSegment(_ segment: String) -> Bool {
        let decoded = segment.removingPercentEncoding ?? segment
        if decoded.count >= 16 { return true }
        let markers = CharacterSet(charactersIn: "=|{}[]:;,&%\"'+~!@$*()")
        if segment.rangeOfCharacter(from: markers) != nil || decoded.rangeOfCharacter(from: markers) != nil {
            return true
        }
        let lowered = decoded.lowercased()
        return keyNames.contains { lowered.contains($0) }
    }

    private static let keyNames = [
        "debrid", "premiumize", "torbox", "offcloud", "putio", "easynews",
        "apikey", "api_key", "api-key", "token", "password", "secret", "auth",
    ]
}
