import Foundation
import Testing
@testable import OpenStreamApple

/// iPhone 27 v2 re-run: Russian Windows-1251 sidecars showed mojibake and
/// UTF-16 Portuguese ones showed nothing. The fixtures in
/// `Tests/Fixtures/subtitles` are two-cue SubRip files in each encoding.
@Suite struct AppleSubtitleTextEncodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/subtitles/\(name)")
        return try Data(contentsOf: url)
    }

    private func texts(_ name: String, language: String?) throws -> [String] {
        AppleSubtitleTextParser.cues(from: try fixture(name), language: language).compactMap(\.text)
    }

    @Test(arguments: [
        ("ru-cp1251.srt", "rus", "Привет, как дела?"),
        ("ru-cp1251.srt", "ru", "Привет, как дела?"),
        ("uk-cp1251.srt", "ukr", "Доброго ранку!"),
        ("pt-utf16le-bom.srt", "por", "Olá, tudo bem?"),
        ("pt-utf16le-nobom.srt", "pob", "Olá, tudo bem?"),
        ("pt-utf16be-bom.srt", "pt", "Olá, tudo bem?"),
        ("es-utf32le-bom.srt", "spa", "¿Qué tal, señor?"),
        ("fr-utf8-bom.srt", "fre", "Ça va très bien."),
        ("fr-cp1252.srt", "fra", "Ça va très bien."),
        ("pl-cp1250.srt", "pol", "Zażółć gęślą jaźń."),
        ("el-cp1253.srt", "ell", "Γειά σου κόσμε."),
        ("ar-cp1256.srt", "ara", "مرحبا بالعالم"),
        ("ja-shiftjis.srt", "jpn", "こんにちは世界"),
        ("zh-gbk.srt", "chi", "你好，世界"),
        ("zh-tw-big5.srt", "zh-TW", "你好，世界"),
    ])
    func eachEncodingReadsBackItsFirstCue(file: String, language: String, expected: String) throws {
        let cues = try texts(file, language: language)
        #expect(cues.count == 2)
        #expect(cues.first == expected)
    }

    /// No declared language: the bytes decide. Unicode needs no hint at all,
    /// and mostly-high-byte text is read as Cyrillic.
    @Test func withoutALanguageTheBytesDecide() throws {
        #expect(try texts("pt-utf16le-nobom.srt", language: nil).last == "Legendas em português, ação.")
        #expect(try texts("ru-cp1251.srt", language: nil).first == "Привет, как дела?")
        #expect(try texts("fr-cp1252.srt", language: nil).first == "Ça va très bien.")
    }

    @Test func theDetectorsPieces() {
        #expect(AppleSubtitleTextEncoding.byteOrderMark([0xFF, 0xFE, 0x31, 0x00])?.0 == .utf16LittleEndian)
        #expect(AppleSubtitleTextEncoding.byteOrderMark([0xFF, 0xFE, 0x00, 0x00])?.0 == .utf32LittleEndian)
        #expect(AppleSubtitleTextEncoding.byteOrderMark([0x31, 0x0D, 0x0A]) == nil)
        let ascii = Array("1\r\n00:00:01,000 --> 00:00:03,000\r\n".utf8)
        #expect(AppleSubtitleTextEncoding.utf16WithoutMark(ascii) == nil)
        let be = Array("1\r\n00:00:01,000".utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
        #expect(AppleSubtitleTextEncoding.utf16WithoutMark(be) == .utf16BigEndian)
    }
}
