import Foundation
import Observation
import SwiftUI

enum ViewMode: String, CaseIterable {
    case post, comments, both
}

enum NavigationEntry: Equatable {
    case home
    case story(HNItem, ViewMode)
    case profile(URL)
    case settings
}

enum AppearanceMode: String, CaseIterable {
    case light, dark, system

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

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
    // MARK: - Navigation History
    private(set) var navigationBackStack: [NavigationEntry] = []
    private(set) var navigationForwardStack: [NavigationEntry] = []
    var canNavigateBack: Bool { !navigationBackStack.isEmpty }
    var canNavigateForward: Bool { !navigationForwardStack.isEmpty }

    private var currentNavigationEntry: NavigationEntry {
        if showingSettings { return .settings }
        if let url = viewingUserProfileURL { return .profile(url) }
        if let story = selectedStory { return .story(story, viewMode) }
        return .home
    }

    func navigate(to story: HNItem) {
        guard selectedStory != story else { return }
        navigationBackStack.append(currentNavigationEntry)
        navigationForwardStack.removeAll()
        selectedStory = story
    }

    func navigateToProfile(url: URL) {
        guard viewingUserProfileURL != url else { return }
        navigationBackStack.append(currentNavigationEntry)
        navigationForwardStack.removeAll()
        viewingUserProfileURL = url
    }

    func navigateToSettings() {
        guard !showingSettings else { return }
        navigationBackStack.append(currentNavigationEntry)
        navigationForwardStack.removeAll()
        showingSettings = true
    }

    func navigateHome() {
        guard selectedStory != nil || viewingUserProfileURL != nil || showingSettings else { return }
        navigationBackStack.append(currentNavigationEntry)
        navigationForwardStack.removeAll()
        selectedStory = nil
        viewingUserProfileURL = nil
        showingSettings = false
    }

    func navigateBack() {
        guard let entry = navigationBackStack.popLast() else { return }
        navigationForwardStack.append(currentNavigationEntry)
        restore(entry)
    }

    func navigateForward() {
        guard let entry = navigationForwardStack.popLast() else { return }
        navigationBackStack.append(currentNavigationEntry)
        restore(entry)
    }

    func changeViewMode(to newMode: ViewMode) {
        guard viewMode != newMode else { return }
        if selectedStory != nil {
            navigationBackStack.append(currentNavigationEntry)
            navigationForwardStack.removeAll()
        }
        viewMode = newMode
    }

    private func restore(_ entry: NavigationEntry) {
        switch entry {
        case .home:
            selectedStory = nil
            viewingUserProfileURL = nil
            showingSettings = false
        case .story(let item, let mode):
            viewMode = mode
            selectedStory = item
        case .profile(let url):
            viewingUserProfileURL = url
        case .settings:
            showingSettings = true
        }
    }

    var webRefreshID = UUID()
    var showFindBar = false
    var findQuery = ""
    var findNextTrigger = UUID()
    var findPreviousTrigger = UUID()
    var goBackTrigger = UUID()
    var goForwardTrigger = UUID()
    var refreshTrigger = UUID()
    var searchQuery: String = ""
    var isSearchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    var isLoading = false
    var showLoadingIndicator = false
    var errorMessage: String?
    private var currentLoadTask: Task<Void, Never>?
    private var loadingIndicatorTask: Task<Void, Never>?

    var loggedInUsername: String?

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

    var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
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

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
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
        if let raw = UserDefaults.standard.string(forKey: "viewMode"),
           let mode = ViewMode(rawValue: raw) {
            self.viewMode = mode
        } else {
            let legacy = UserDefaults.standard.object(forKey: "preferArticleView") as? Bool ?? true
            let migrated: ViewMode = legacy ? .post : .comments
            self.viewMode = migrated
            UserDefaults.standard.set(migrated.rawValue, forKey: "viewMode")
            UserDefaults.standard.removeObject(forKey: "preferArticleView")
        }
        self.adBlockingEnabled = UserDefaults.standard.object(forKey: "adBlockingEnabled") as? Bool ?? true
        self.popUpBlockingEnabled = UserDefaults.standard.object(forKey: "popUpBlockingEnabled") as? Bool ?? true
        self.textScale = UserDefaults.standard.object(forKey: "textScale") as? Double ?? 1.0
        self.appearanceMode = (UserDefaults.standard.string(forKey: "appearanceMode")).flatMap(AppearanceMode.init(rawValue:)) ?? .system
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
            let author = contentType.isThreads ? loggedInUsername : nil
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, displaySort: displaySort, page: 0, author: author)
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
            let author = contentType.isThreads ? loggedInUsername : nil
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, displaySort: displaySort, page: currentPage, author: author)
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
            let author = contentType.isThreads ? loggedInUsername : nil
            let results = try await HNService.searchStories(query: query, contentType: contentType, dateRange: dateRange, displaySort: displaySort, author: author)
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
