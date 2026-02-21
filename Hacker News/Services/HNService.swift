import Foundation

struct AlgoliaResponse: Codable {
    let hits: [AlgoliaHit]
    let nbPages: Int
    let page: Int
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
    let comment_text: String?
    let story_title: String?
    let story_id: Int?
    let _tags: [String]?

    var inferredType: String {
        guard let tags = _tags else { return "story" }
        if tags.contains("comment") { return "comment" }
        if tags.contains("job") { return "job" }
        return "story"
    }
}

struct HNService {
    private static let baseURL = "https://hacker-news.firebaseio.com/v0/"

    static func fetchFeed(contentType: HNContentType, dateRange: HNDateRange, displaySort: HNDisplaySort, page: Int = 0, hitsPerPage: Int = 30, author: String? = nil) async throws -> (items: [HNItem], hasMore: Bool) {
        var components = URLComponents(string: displaySort.algoliaEndpoint)!
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage))
        ]
        if let tag = contentType.algoliaTag {
            var tagValue = tag
            if let author { tagValue += ",author_\(author)" }
            queryItems.append(URLQueryItem(name: "tags", value: tagValue))
        }
        if let timestamp = dateRange.startTimestamp {
            queryItems.append(URLQueryItem(name: "numericFilters", value: "created_at_i>\(timestamp)"))
        }
        components.queryItems = queryItems

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(AlgoliaResponse.self, from: data)

        let items: [HNItem] = response.hits.compactMap { hit in
            guard let id = Int(hit.objectID) else { return nil }
            let type = contentType.isAll ? hit.inferredType : ((contentType.isComments || contentType.isThreads) ? "comment" : "story")
            return HNItem(
                id: id,
                type: type,
                by: hit.author,
                time: hit.created_at_i,
                url: hit.url,
                title: hit.title,
                score: hit.points,
                descendants: hit.num_comments,
                kids: nil,
                text: type == "comment" ? hit.comment_text : hit.story_text,
                storyTitle: hit.story_title,
                storyID: hit.story_id
            )
        }
        return (items, page + 1 < response.nbPages)
    }

    static func searchStories(query: String, contentType: HNContentType, dateRange: HNDateRange, displaySort: HNDisplaySort, author: String? = nil) async throws -> [HNItem] {
        var components = URLComponents(string: displaySort.algoliaEndpoint)!
        var queryItems = [
            URLQueryItem(name: "query", value: query)
        ]
        if let tag = contentType.algoliaTag {
            var tagValue = tag
            if let author { tagValue += ",author_\(author)" }
            queryItems.append(URLQueryItem(name: "tags", value: tagValue))
        }
        if let timestamp = dateRange.startTimestamp {
            queryItems.append(URLQueryItem(name: "numericFilters", value: "created_at_i>\(timestamp)"))
        }
        components.queryItems = queryItems

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(AlgoliaResponse.self, from: data)
        return response.hits.compactMap { hit -> HNItem? in
            guard let id = Int(hit.objectID) else { return nil }
            let type = contentType.isAll ? hit.inferredType : ((contentType.isComments || contentType.isThreads) ? "comment" : "story")
            return HNItem(
                id: id,
                type: type,
                by: hit.author,
                time: hit.created_at_i,
                url: hit.url,
                title: hit.title,
                score: hit.points,
                descendants: hit.num_comments,
                kids: nil,
                text: type == "comment" ? hit.comment_text : hit.story_text,
                storyTitle: hit.story_title,
                storyID: hit.story_id
            )
        }
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
