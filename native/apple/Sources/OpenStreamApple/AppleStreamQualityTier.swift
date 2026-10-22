import Foundation

/// A resolution the quality picker offers. The picker names the picture,
/// never the file: no codec, container, HDR or Dolby Vision words, no source
/// names (owner 2026-09-24: "there should be 1 source per resolution and
/// Automatic").
public enum AppleStreamQualityTier: Int, CaseIterable, Comparable, Sendable {
    case sd = 480
    case hd = 720
    case fullHD = 1080
    case uhd = 2160

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .sd: "SD"
        case .hd: "720p"
        case .fullHD: "1080p"
        case .uhd: "4K"
        }
    }

    /// 1440p sits with 1080p and 8K with 4K; an unstated resolution has no tier.
    public init?(resolution: Int) {
        switch resolution {
        case 2160...: self = .uhd
        case 1080..<2160: self = .fullHD
        case 720..<1080: self = .hd
        case 1..<720: self = .sd
        default: return nil
        }
    }
}

/// What the viewer asked the picker for.
public enum AppleStreamQualityChoice: Hashable, Sendable {
    case automatic
    case tier(AppleStreamQualityTier)
}
