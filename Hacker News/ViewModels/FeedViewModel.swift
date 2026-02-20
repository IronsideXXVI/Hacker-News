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
    var showFindBar = false
    var findQuery = ""
    var findNextTrigger = UUID()
    var findPreviousTrigger = UUID()
    var searchQuery: String = ""
    var isSearchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    var isLoading = false
    var showLoadingIndicator = false
    var errorMessage: String?
    private var currentLoadTask: Task<Void, Never>?
    private var loadingIndicatorTask: Task<Void, Never>?

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

    var textScale: Double {
        didSet {
            UserDefaults.standard.set(textScale, forKey: "textScale")
        }
    }

    func increaseTextScale() {
        textScale = min(1.5, textScale + 0.1)
    }

    func decreaseTextScale() {
        textScale = max(0.75, textScale - 0.1)
    }

    func resetTextScale() {
        textScale = 1.0
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
        self.textScale = UserDefaults.standard.object(forKey: "textScale") as? Double ?? 1.0
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
            finishLoading()
            return
        }

        if !isLoading {
            isLoading = true
            errorMessage = nil
            stories = []
            currentPage = 0
            hasMore = false
            startLoadingIndicatorDelay()
        }

        do {
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, displaySort: displaySort, page: 0)
            guard !Task.isCancelled else { return }
            stories = result.items
            hasMore = result.hasMore
            currentPage = 1
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        finishLoading()
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

        currentLoadTask?.cancel()
        loadingIndicatorTask?.cancel()

        isLoading = true
        errorMessage = nil
        stories = []
        selectedStory = nil
        showLoadingIndicator = false
        startLoadingIndicatorDelay()

        do {
            let results = try await HNService.searchStories(query: query, contentType: contentType, dateRange: dateRange, displaySort: displaySort)
            guard !Task.isCancelled else { return }
            stories = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        finishLoading()
    }

    func clearSearch() {
        searchQuery = ""
        currentLoadTask?.cancel()
        loadingIndicatorTask?.cancel()
        currentLoadTask = Task { await loadFeed() }
    }

    private func startLoadingIndicatorDelay() {
        loadingIndicatorTask?.cancel()
        loadingIndicatorTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if isLoading { showLoadingIndicator = true }
        }
    }

    private func finishLoading() {
        isLoading = false
        loadingIndicatorTask?.cancel()
        showLoadingIndicator = false
    }

    private func resetAndReload() {
        currentLoadTask?.cancel()

        selectedStory = nil
        stories = []
        currentPage = 0
        hasMore = false
        isLoading = true
        showLoadingIndicator = false
        errorMessage = nil

        startLoadingIndicatorDelay()
        currentLoadTask = Task { await loadFeed() }
    }
}
