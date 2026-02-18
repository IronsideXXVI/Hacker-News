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

    var contentType: HNContentType = .frontPage {
        didSet {
            if oldValue != contentType { resetAndReload() }
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

    private var currentPage = 0
    private var hasMore = false
    private var isFetchingMore = false

    init() {
        self.preferArticleView = UserDefaults.standard.object(forKey: "preferArticleView") as? Bool ?? true
    }

    func loadFeed() async {
        isLoading = true
        errorMessage = nil
        stories = []
        currentPage = 0
        hasMore = false

        do {
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, page: 0)
            stories = result.items
            hasMore = result.hasMore
            currentPage = 1
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: HNItem) async {
        guard let index = stories.firstIndex(of: currentItem),
              index >= stories.count - 5,
              !isFetchingMore,
              hasMore else { return }

        isFetchingMore = true
        do {
            let result = try await HNService.fetchFeed(contentType: contentType, dateRange: dateRange, page: currentPage)
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
        isLoading = true
        errorMessage = nil
        stories = []
        selectedStory = nil

        do {
            stories = try await HNService.searchStories(query: query, contentType: contentType, dateRange: dateRange)
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
