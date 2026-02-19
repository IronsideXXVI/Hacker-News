import Foundation

struct HNItem: Codable, Identifiable, Hashable {
    let id: Int
    let type: String?
    let by: String?
    let time: Int?
    let url: String?
    let title: String?
    let score: Int?
    let descendants: Int?
    let kids: [Int]?
    let text: String?
    var storyTitle: String? = nil
    var storyID: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, type, by, time, url, title, score, descendants, kids, text, storyTitle, storyID
    }

    var displayURL: URL? {
        guard let url else { return nil }
        return URL(string: url)
    }

    var commentsURL: URL {
        URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }

    var displayDomain: String? {
        guard let url, let host = URL(string: url)?.host() else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : String(host)
        return domain
    }

    var timeAgo: String {
        guard let time else { return "" }
        let date = Date(timeIntervalSince1970: Double(time))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

extension String {
    func strippingHTML() -> String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
