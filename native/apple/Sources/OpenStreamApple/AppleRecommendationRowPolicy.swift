import Foundation

enum AppleRecommendationRowPolicy {
    static func appendingSeed<Rail>(_ seed: Rail?, to configured: [Rail]) -> [Rail] {
        guard let seed else { return configured }
        return configured + [seed]
    }

    static func heading(seed: String, count: Int, existing: [String]) -> String? {
        let title = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, count >= 6 else { return nil }
        let heading = "Because you watched \(title)"
        guard !existing.contains(where: { $0.compare(heading, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return nil }
        return heading
    }
}
