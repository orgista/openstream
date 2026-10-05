import Foundation

final class AppleIPTVGuideXMLTVParser: NSObject, XMLParserDelegate, Sendable {
    func parse(data: Data, defaultOffsetHours: Double = 0) -> [AppleIPTVProgramme] {
        guide(data: data, defaultOffsetHours: defaultOffsetHours).allProgrammes
    }

    func guide(data: Data, defaultOffsetHours: Double = 0) -> AppleIPTVGuide {
        let parser = XMLParser(data: data)
        let delegate = ParserDelegate(defaultOffsetHours: defaultOffsetHours)
        parser.delegate = delegate
        parser.parse()
        return AppleIPTVGuide(programmes: delegate.programmes, channelNames: delegate.channelNames)
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    var programmes: [AppleIPTVProgramme] = []
    var channelNames: [String: String] = [:]
    private var catalogueID: String?
    private var displayName = ""
    
    private var currentElement: String = ""
    private var currentChannel: String = ""
    private var currentStart: Date?
    private var currentEnd: Date?
    
    private var currentTitle: String = ""
    private var currentSubtitle: String = ""
    private var currentDesc: String = ""
    private var currentCategory: String = ""
    
    private let dateFormatterWithOffset: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss Z"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    private let dateFormatterNoOffset: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()
    
    init(defaultOffsetHours: Double) {
        super.init()
        let hours = defaultOffsetHours.isFinite ? min(14, max(-12, defaultOffsetHours)) : 0
        dateFormatterNoOffset.timeZone = TimeZone(secondsFromGMT: Int(hours * 3600))
        dateFormatterNoOffset.isLenient = false
        dateFormatterWithOffset.isLenient = false
    }

    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = dateFormatterWithOffset.date(from: trimmed) {
            return d
        }
        if let d = dateFormatterNoOffset.date(from: trimmed) {
            return d
        }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "channel" {
            catalogueID = attributeDict["id"]
            displayName = ""
        }
        if elementName == "programme" {
            currentChannel = attributeDict["channel"] ?? ""
            if let startStr = attributeDict["start"] {
                currentStart = parseDate(startStr)
            } else {
                currentStart = nil
            }
            if let stopStr = attributeDict["stop"] {
                currentEnd = parseDate(stopStr)
            } else {
                currentEnd = nil
            }
            
            currentTitle = ""
            currentSubtitle = ""
            currentDesc = ""
            currentCategory = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        
        switch currentElement {
        case "display-name" where catalogueID != nil: displayName += string
        case "title": currentTitle += string
        case "sub-title": currentSubtitle += string
        case "desc": currentDesc += string
        case "category": currentCategory += string
        default: break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "channel", let id = catalogueID, channelNames.count < AppleIPTVClient.maximumChannels {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, !name.isEmpty { channelNames[id] = name }
            catalogueID = nil
        }
        if elementName == "programme" {
            guard let start = currentStart, let end = currentEnd, !currentChannel.isEmpty, end > start, !currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, programmes.count < AppleIPTVGuideDiskCache.maximumProgrammes else { return }
            
            let prog = AppleIPTVProgramme(
                id: UUID().uuidString,
                channelID: currentChannel,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: currentSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : currentSubtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                description: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                end: end,
                category: currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : currentCategory.trimmingCharacters(in: .whitespacesAndNewlines),
                isLive: false // Will be determined by guide querying logic comparing Date() to start/end
            )
            programmes.append(prog)
        }
        currentElement = ""
    }
}
