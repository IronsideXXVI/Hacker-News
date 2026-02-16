import Foundation

struct HNService {
    private static let baseURL = "https://hacker-news.firebaseio.com/v0/"

    static func fetchStoryIDs(for feed: HNFeedType) async throws -> [Int] {
        guard let url = feed.apiEndpoint else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Int].self, from: data)
    }

    static func fetchItem(id: Int) async throws -> HNItem {
        let url = URL(string: baseURL + "item/\(id).json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(HNItem.self, from: data)
    }

    static func fetchUser(id: String) async throws -> HNUser {
        let url = URL(string: baseURL + "user/\(id).json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(HNUser.self, from: data)
    }

    static func fetchItems(ids: [Int]) async throws -> [HNItem] {
        try await withThrowingTaskGroup(of: (Int, HNItem).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { @Sendable in
                    let item = try await fetchItem(id: id)
                    return (index, item)
                }
            }

            var results = [(Int, HNItem)]()
            results.reserveCapacity(ids.count)
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
