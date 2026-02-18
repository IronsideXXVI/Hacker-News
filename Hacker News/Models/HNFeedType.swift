import Foundation

enum HNContentType: String, CaseIterable, Identifiable {
    case frontPage
    case stories
    case askHN
    case showHN
    case jobs
    case comments

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frontPage: "Front Page"
        case .stories: "Stories"
        case .askHN: "Ask HN"
        case .showHN: "Show HN"
        case .jobs: "Jobs"
        case .comments: "Comments"
        }
    }

    var algoliaTag: String {
        switch self {
        case .frontPage: "front_page"
        case .stories: "story"
        case .askHN: "ask_hn"
        case .showHN: "show_hn"
        case .jobs: "job"
        case .comments: "comment"
        }
    }

    var isComments: Bool { self == .comments }
}

enum HNDateRange: String, CaseIterable, Identifiable {
    case today
    case pastWeek
    case pastMonth
    case pastYear
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .pastWeek: "Past Week"
        case .pastMonth: "Past Month"
        case .pastYear: "Past Year"
        case .allTime: "All Time"
        }
    }

    var startTimestamp: Int? {
        let now = Date()
        let calendar = Calendar.current
        switch self {
        case .today:
            return Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        case .pastWeek:
            return Int((calendar.date(byAdding: .day, value: -7, to: now) ?? now).timeIntervalSince1970)
        case .pastMonth:
            return Int((calendar.date(byAdding: .month, value: -1, to: now) ?? now).timeIntervalSince1970)
        case .pastYear:
            return Int((calendar.date(byAdding: .year, value: -1, to: now) ?? now).timeIntervalSince1970)
        case .allTime:
            return nil
        }
    }
}
