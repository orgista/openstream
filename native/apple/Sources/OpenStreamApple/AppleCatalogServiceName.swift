import Foundation

/// Maps streaming catalog IDs to clean, human-readable service names.
/// Based on the Streaming Catalogs add-on (github.com/rleroi/Stremio-Streaming-Catalogs-Addon).
public enum AppleCatalogServiceName: Sendable {
    
    /// The service a catalog lists, when it is one streaming service's own
    /// catalog, else nil — never the generic name clean-up `service` falls
    /// back to, so "Popular" or "Top 10 Disney+" stay what they are.
    ///
    /// Known by its id (`amp`, or the TMDB add-on's `streaming.amp`), or by a
    /// name that is exactly a service's ("Prime Video", "Netflix").
    public static func streamingService(catalogID: String?, name: String?) -> String? {
        if let id = catalogID?.lowercased(), !id.isEmpty {
            let key = id.hasPrefix("streaming.") ? String(id.dropFirst("streaming.".count)) : id
            if let service = knownService(id: key) { return service }
        }
        guard let name else { return nil }
        let cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        guard !cleaned.isEmpty else { return nil }
        if let alias = nameAliases[cleaned] { return alias }
        return knownServiceNames.first { $0.lowercased() == cleaned }
    }

    /// Names a service's catalog goes by that are not its short name.
    private static let nameAliases: [String: String] = [
        "prime video": "Prime",
        "amazon prime video": "Prime",
        "amazon prime": "Prime",
        "max": "HBO Max",
        "apple tv": "Apple TV+",
        "paramount plus": "Paramount+",
        "disney plus": "Disney+",
    ]

    private static let knownIDs = [
        "nfx", "nfk", "hbm", "dnp", "hlu", "amp", "pmp", "atp", "pcp", "cru", "jhs", "zee", "vil", "clv",
        "gop", "hay", "nlz", "sst", "mgl", "cts", "cpd", "stz", "dpe", "mbi", "vik", "sgo", "sonyliv",
        "mp9", "shd", "bbo", "act", "itv", "bbc", "al4", "crc", "iqi", "sha",
    ]

    private static let knownServiceNames: [String] = knownIDs.compactMap { knownService(id: $0) }

    /// The id table alone, without `service`'s name fallback.
    private static func knownService(id: String) -> String? {
        guard !id.hasPrefix("netflix-top10") else { return nil }
        return service(fromCatalogID: id, name: nil)
    }

    /// Returns the human-readable service name for a given catalog ID, or nil if it's not a known per-service catalog.
    public static func service(fromCatalogID id: String? = nil, name: String?) -> String? {
        let id = id?.lowercased() ?? ""
        switch id {
        case "nfx": return "Netflix"
        case "nfk": return "Netflix Kids"
        case "hbm": return "HBO Max"
        case "dnp": return "Disney+"
        case "hlu": return "Hulu"
        case "amp": return "Prime"
        case "pmp": return "Paramount+"
        case "atp": return "Apple TV+"
        case "pcp", "pct": return "Peacock"
        case "cru", "fmn": return "Crunchyroll"
        case "jhs", "hst": return "JioHotstar"
        case "zee": return "Zee5"
        case "vil": return "Videoland"
        case "clv": return "Clarovideo"
        case "gop": return "Globoplay"
        case "hay": return "Hayu"
        case "nlz": return "NLZIET"
        case "sst": return "SkyShowtime"
        case "mgl": return "MagellanTV"
        case "cts": return "Curiosity Stream"
        case "cpd": return "Canal+"
        case "stz": return "Starz"
        case "dpe": return "Discovery+"
        case "mbi": return "Mubi"
        case "vik": return "Rakuten Viki"
        case "sgo": return "Sky Go"
        case "sonyliv": return "Sony Liv"
        case "mp9": return "Movistar+"
        case "shd": return "Shudder"
        case "bbo": return "BritBox"
        case "act": return "Acorn TV"
        case "itv": return "ITVX"
        case "bbc": return "BBC iPlayer"
        case "al4": return "Channel 4"
        case "crc": return "Criterion Channel"
        case "iqi": return "iQIYI"
        case "sha": return "Shahid VIP"
        default:
            if id.hasPrefix("netflix-top10") {
                return "Netflix"
            }
            if let name {
                let cleaned = name
                    .replacingOccurrences(of: "Streaming Catalog", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Catalog", with: "", options: .caseInsensitive)
                    .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                if cleaned.caseInsensitiveCompare("Prime Video") == .orderedSame {
                    return "Prime"
                }
                return cleaned.isEmpty ? nil : cleaned
            }
            return nil
        }
    }
}
