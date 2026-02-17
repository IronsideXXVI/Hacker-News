import Foundation
import Observation

@Observable
final class FeedViewModel {
    var stories: [HNItem] = []
    var selectedStory: HNItem? {
        didSet {
            if selectedStory != nil { viewingUserProfileURL = nil }
        }
    }
    var viewingUserProfileURL: URL? {
        didSet {
            if viewingUserProfileURL != nil { selectedStory = nil }
        }
    }
    var webRefreshID = UUID()
    var searchQuery: String = ""
    var isSearchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    var currentFeed: HNFeedType = .top
    var isLoading = false
    var errorMessage: String?

    var preferArticleView: Bool {
        didSet { UserDefaults.standard.set(preferArticleView, forKey: "preferArticleView") }
    }

    private var allStoryIDs: [Int] = []
    private var loadedCount = 0
    private let batchSize = 30
    private var isFetchingMore = false

    init() {
        self.preferArticleView = UserDefaults.standard.object(forKey: "preferArticleView") as? Bool ?? true
    }

    func loadFeed() async {
        guard currentFeed.hasStoryList else { return }
        isLoading = true
        errorMessage = nil
        stories = []
        loadedCount = 0

        do {
            allStoryIDs = try await HNService.fetchStoryIDs(for: currentFeed)
            await loadNextBatch()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: HNItem) async {
        guard let index = stories.firstIndex(of: currentItem),
              index >= stories.count - 5,
              !isFetchingMore,
              loadedCount < allStoryIDs.count else { return }
        await loadNextBatch()
    }

    func searchStories() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        stories = []
        selectedStory = nil
        allStoryIDs = []
        loadedCount = 0

        do {
            stories = try await HNService.searchStories(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func clearSearch() {
        searchQuery = ""
        Task { await loadFeed() }
    }

    func switchFeed(to feed: HNFeedType) {
        guard feed != currentFeed else { return }
        currentFeed = feed
        selectedStory = nil
        stories = []
        allStoryIDs = []
        loadedCount = 0
        Task { await loadFeed() }
    }

    private func loadNextBatch() async {
        guard loadedCount < allStoryIDs.count else { return }
        isFetchingMore = true
        let end = min(loadedCount + batchSize, allStoryIDs.count)
        let batchIDs = Array(allStoryIDs[loadedCount..<end])

        do {
            let items = try await HNService.fetchItems(ids: batchIDs)
            stories.append(contentsOf: items)
            loadedCount = end
        } catch {
            errorMessage = error.localizedDescription
        }
        isFetchingMore = false
    }
}
