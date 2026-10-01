import AVFoundation
import Foundation

/// What the stock player's transport names above its scrubber. With nothing
/// given, AVKit falls back to the file's own container tags: a 2015 film
/// showed "2023", the title tag of the release it was cut from (Apple TV
/// check, 2026-10-01). The title page's own title replaces it.
public enum AppleStockPlayerMetadata {
    public static func items(title: String?) -> [AVMetadataItem] {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return [] }
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = title as NSString
        item.extendedLanguageTag = "und"
        return [item.copy() as! AVMetadataItem]
    }
}
