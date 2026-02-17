import Foundation

// Algolia search response models
struct AlgoliaSearchResponse: Codable {
    let hits: [AlgoliaHit]
}

struct AlgoliaHit: Codable {
    let objectID: String
    let title: String?
    let url: String?
    let author: String?
    let points: Int?
    let num_comments: Int?
    let created_at_i: Int?
    let story_text: String?
}

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

    static func searchStories(query: String) async throws -> [HNItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://hn.algolia.com/api/v1/search?query=\(encoded)&tags=story") else {
            return []
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AlgoliaSearchResponse.self, from: data)
        return response.hits.compactMap { hit -> HNItem? in
            guard let id = Int(hit.objectID) else { return nil }
            return HNItem(
                id: id,
                type: "story",
                by: hit.author,
                time: hit.created_at_i,
                url: hit.url,
                title: hit.title,
                score: hit.points,
                descendants: hit.num_comments,
                kids: nil,
                text: hit.story_text
            )
        }
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
