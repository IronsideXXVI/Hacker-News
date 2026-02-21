import Foundation

enum HNContentType: String, CaseIterable, Identifiable {
    case all
    case askHN
    case showHN
    case jobs
    case comments
    case threads
    case bookmarks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .askHN: "Ask"
        case .showHN: "Show"
        case .jobs: "Jobs"
        case .comments: "Comments"
        case .threads: "Threads"
        case .bookmarks: "Bookmarks"
        }
    }

    var algoliaTag: String? {
        switch self {
        case .all: "(story,job,poll)"
        case .askHN: "ask_hn"
        case .showHN: "show_hn"
        case .jobs: "job"
        case .comments: "comment"
        case .threads: "comment"
        case .bookmarks: nil
        }
    }

    var isAll: Bool { self == .all }
    var isComments: Bool { self == .comments }
    var isThreads: Bool { self == .threads }
    var isBookmarks: Bool { self == .bookmarks }
    var requiresAuth: Bool { self == .threads }
}

enum HNDateRange: String, CaseIterable, Identifiable {
    case today
    case pastWeek
    case pastMonth
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .pastWeek: "Past Week"
        case .pastMonth: "Past Month"
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
        case .allTime:
            return nil
        }
    }
}

enum HNDisplaySort: String, CaseIterable, Identifiable {
    case hot
    case recent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hot: "Hot"
        case .recent: "Recent"
        }
    }

    var algoliaEndpoint: String {
        switch self {
        case .hot: "https://hn.algolia.com/api/v1/search"
        case .recent: "https://hn.algolia.com/api/v1/search_by_date"
        }
    }
}
