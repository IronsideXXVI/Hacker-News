import Foundation

enum HNFeedType: String, CaseIterable {
    static var allCases: [HNFeedType] {
        [.top, .new, .past, .comments, .ask, .show, .jobs]
    }

    case top
    case new
    case past
    case comments
    case ask
    case show
    case jobs
    case submit

    var displayName: String {
        switch self {
        case .top: "Hacker News"
        case .new: "new"
        case .past: "past"
        case .comments: "comments"
        case .ask: "ask"
        case .show: "show"
        case .jobs: "jobs"
        case .submit: "submit"
        }
    }

    var apiEndpoint: URL? {
        let base = "https://hacker-news.firebaseio.com/v0/"
        switch self {
        case .top: return URL(string: base + "topstories.json")
        case .new: return URL(string: base + "newstories.json")
        case .ask: return URL(string: base + "askstories.json")
        case .show: return URL(string: base + "showstories.json")
        case .jobs: return URL(string: base + "jobstories.json")
        case .past, .comments, .submit: return nil
        }
    }

    var webURL: URL? {
        switch self {
        case .past: return URL(string: "https://news.ycombinator.com/front")
        case .comments: return URL(string: "https://news.ycombinator.com/newcomments")
        case .submit: return URL(string: "https://news.ycombinator.com/submit")
        default: return nil
        }
    }

    var hasStoryList: Bool {
        apiEndpoint != nil
    }
}
