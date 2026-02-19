import Foundation
import Observation

@Observable
final class FeedViewModel {
    var stories: [HNItem] = []
    var selectedStory: HNItem? {
        didSet {
            if selectedStory != nil {
                viewingUserProfileURL = nil
                showingSettings = false
            }
        }
    }
    var viewingUserProfileURL: URL? {
        didSet {
            if viewingUserProfileURL != nil {
                selectedStory = nil
                showingSettings = false
            }
        }
    }
    var showingSettings = false {
        didSet {
            if showingSettings {
                selectedStory = nil
                viewingUserProfileURL = nil
            }
        }
    }
    var webRefreshID = UUID()
    var searchQuery: String = ""
    var isSearchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    var isLoading = false
    var errorMessage: String?

    var contentType: HNContentType = .all {
        didSet {
            if oldValue != contentType { resetAndReload() }
        }
    }
    var displaySort: HNDisplaySort = .hot {
        didSet {
            if oldValue != displaySort { resetAndReload() }
        }
    }
    var dateRange: HNDateRange = .today {
        didSet {
            if oldValue != dateRange { resetAndReload() }
        }
    }

    var preferArticleView: Bool {
        didSet { UserDefaults.standard.set(preferArticleView, forKey: "preferArticleView") }
    }

    var adBlockingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adBlockingEnabled, forKey: "adBlockingEnabled")
            webRefreshID = UUID()
        }
    }

    var popUpBlockingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(popUpBlockingEnabled, forKey: "popUpBlockingEnabled")
            webRefreshID = UUID()
        }
    }

    private(set) var bookmarkedItems: [HNItem] = []
    private let bookmarksKey = "bookmarkedItems"
    private var currentPage = 0
    private var hasMore = false
    private var isFetchingMore = false

    init() {
        self.preferArticleView = UserDefaults.standard.object(forKey: "preferArticleView") as? Bool ?? true
        self.adBlockingEnabled = UserDefaults.standard.object(forKey: "adBlockingEnabled") as? Bool ?? true
        self.popUpBlockingEnabled = UserDefaults.standard.object(forKey: "popUpBlockingEnabled") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let items = try? JSONDecoder().decode([HNItem].self, from: data) {
            self.bookmarkedItems = items
        }
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarkedItems) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    func isBookmarked(_ item: HNItem) -> Bool {
        bookmarkedItems.contains(where: { $0.id == item.id })
    }

    func toggleBookmark(_ item: HNItem) {
        if let index = bookmarkedItems.firstIndex(where: { $0.id == item.id }) {
            bookmarkedItems.remove(at: index)
        } else {
            bookmarkedItems.insert(item, at: 0)
        }
        saveBookmarks()
        if contentType.isBookmarks {
            stories = filteredBookmarks()
        }
    }

    private func filteredBookmarks() -> [HNItem] {
        guard let start = dateRange.startTimestamp else { return bookmarkedItems }
        return bookmarkedItems.filter { ($0.time ?? 0) >= start }
    }

    func loadFeed() async {
        if contentType.isBookmarks {
            stories = filteredBookmarks()
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        stories = []
        currentPage = 0
        hasMore = false

        do {
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, displaySort: displaySort, page: 0)
            stories = result.items
            hasMore = result.hasMore
            currentPage = 1
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: HNItem) async {
        guard !contentType.isBookmarks,
              let index = stories.firstIndex(of: currentItem),
              index >= stories.count - 5,
              !isFetchingMore,
              hasMore else { return }

        isFetchingMore = true
        do {
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, displaySort: displaySort, page: currentPage)
            stories.append(contentsOf: result.items)
            hasMore = result.hasMore
            currentPage += 1
        } catch {
            errorMessage = error.localizedDescription
        }
        isFetchingMore = false
    }

    func searchStories() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        if contentType.isBookmarks {
            let lowered = query.lowercased()
            stories = filteredBookmarks().filter { item in
                (item.title?.lowercased().contains(lowered) ?? false) ||
                (item.by?.lowercased().contains(lowered) ?? false) ||
                (item.displayDomain?.lowercased().contains(lowered) ?? false) ||
                (item.text?.strippingHTML().lowercased().contains(lowered) ?? false)
            }
            return
        }

        isLoading = true
        errorMessage = nil
        stories = []
        selectedStory = nil

        do {
            stories = try await HNService.searchStories(query: query, contentType: contentType, dateRange: dateRange, displaySort: displaySort)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func clearSearch() {
        searchQuery = ""
        Task { await loadFeed() }
    }

    private func resetAndReload() {
        selectedStory = nil
        stories = []
        currentPage = 0
        hasMore = false
        Task { await loadFeed() }
    }
}
