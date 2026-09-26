import Foundation

/// One row of the SharePlay "Choose the source for this channel" prompt: the
/// shared channel as one of the viewer's sources carries it.
public struct AppleSharedChannelSourceChoice: Identifiable, Equatable, Sendable {
    public let channel: AppleIPTVChannel
    public let title: String

    public var id: String { channel.id }

    /// A row per candidate, named for its source (the channel's own name when
    /// the source is gone). Two sources with the same name, or one source
    /// carrying the channel twice, would read as identical rows, so those
    /// rows add the channel's name.
    public static func choices(for channels: [AppleIPTVChannel],
                               sourceNames: [UUID: String]) -> [AppleSharedChannelSourceChoice] {
        let bases = channels.map { channel -> String in
            let name = sourceNames[channel.sourceID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? channel.name : name
        }
        var counts: [String: Int] = [:]
        for base in bases { counts[base, default: 0] += 1 }
        return zip(channels, bases).map { channel, base in
            let collides = (counts[base] ?? 0) > 1 && base != channel.name
            return AppleSharedChannelSourceChoice(channel: channel,
                                                  title: collides ? "\(base) · \(channel.name)" : base)
        }
    }
}

/// A row of the source prompt: start the channel from one source, or leave
/// SharePlay. Leaving is the prompt's only destructive row (red on Apple TV's
/// page, as the dialog it replaced drew it).
public enum AppleSharedSourcePromptAction: Equatable, Sendable {
    case choose(AppleSharedChannelSourceChoice)
    case leave

    public var title: String {
        switch self {
        case .choose(let choice): choice.title
        case .leave: "Leave SharePlay"
        }
    }

    public var isDestructive: Bool {
        switch self {
        case .choose: false
        case .leave: true
        }
    }
}
