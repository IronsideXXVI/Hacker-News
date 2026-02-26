import Foundation
import Observation

@Observable
final class HNHideManager {
    private(set) var hiddenItemIDs: Set<Int> = []
    var isSyncing = false

    // MARK: - Web Callback

    /// Called when the WebView JS has already performed the hide/unhide via fetch().
    /// No HTTP request needed — just update local state.
    func onItemHiddenFromWeb(id: Int, isUnhide: Bool) {
        if isUnhide {
            hiddenItemIDs.remove(id)
        } else {
            hiddenItemIDs.insert(id)
        }
    }

    // MARK: - Native Hide/Unhide

    /// Hide an item by scraping the auth token from the item page, then sending the hide request.
    func hideItem(id: Int) async {
        hiddenItemIDs.insert(id)
        do {
            let (auth, currentlyHidden) = try await scrapeHideAuthToken(for: id)
            // If item is already hidden on HN, nothing to do server-side
            guard !currentlyHidden else { return }
            let url = URL(string: "https://news.ycombinator.com/hide?id=\(id)&auth=\(auth)&goto=news")!
            _ = try await URLSession.shared.data(from: url)
        } catch {
            // Keep local state — user intended to hide
        }
    }

    /// Unhide an item by scraping the auth token from the item page, then sending the unhide request.
    func unhideItem(id: Int) async {
        hiddenItemIDs.remove(id)
        do {
            let (auth, currentlyHidden) = try await scrapeHideAuthToken(for: id)
            // If item is already unhidden on HN, nothing to do server-side
            guard currentlyHidden else { return }
            let url = URL(string: "https://news.ycombinator.com/hide?id=\(id)&un=t&auth=\(auth)&goto=news")!
            _ = try await URLSession.shared.data(from: url)
        } catch {
            // Keep local state — user intended to unhide
        }
    }

    func isHidden(_ id: Int) -> Bool {
        hiddenItemIDs.contains(id)
    }

    // MARK: - Sync Hidden List

    /// Fetch the user's hidden items list from HN and populate hiddenItemIDs.
    func syncHiddenList(username: String) async {
        isSyncing = true
        defer { isSyncing = false }

        var allIDs: Set<Int> = []
        var nextURL: URL? = URL(string: "https://news.ycombinator.com/hidden?id=\(username)")

        while let url = nextURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let html = String(data: data, encoding: .utf8) ?? ""
                let (ids, moreURL) = parseHiddenListPage(html: html, baseURL: url)
                allIDs.formUnion(ids)
                nextURL = moreURL
            } catch {
                break
            }
        }

        hiddenItemIDs = allIDs
    }

    // MARK: - Logout

    func clearOnLogout() {
        hiddenItemIDs.removeAll()
    }

    // MARK: - HTML Parsing

    /// Scrape the auth token and current hidden state from the item page HTML.
    /// Returns (authToken, currentlyHidden) — `currentlyHidden` is true if the page shows "un-hide".
    private func scrapeHideAuthToken(for itemID: Int) async throws -> (auth: String, currentlyHidden: Bool) {
        let url = URL(string: "https://news.ycombinator.com/item?id=\(itemID)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""

        // Try unhide pattern first: hide?id=ITEMID&amp;un=t&amp;auth=TOKEN
        let unhidePattern = "hide?id=\(itemID)&amp;un=t&amp;auth="
        if let range = html.range(of: unhidePattern) {
            let afterAuth = html[range.upperBound...]
            if let endQuote = afterAuth.firstIndex(where: { $0 == "\"" || $0 == "&" }) {
                let token = String(afterAuth[afterAuth.startIndex..<endQuote])
                if !token.isEmpty {
                    return (token, true)
                }
            }
        }

        // Try hide pattern: hide?id=ITEMID&amp;auth=TOKEN
        let hidePattern = "hide?id=\(itemID)&amp;auth="
        if let range = html.range(of: hidePattern) {
            let afterAuth = html[range.upperBound...]
            if let endQuote = afterAuth.firstIndex(where: { $0 == "\"" || $0 == "&" }) {
                let token = String(afterAuth[afterAuth.startIndex..<endQuote])
                if !token.isEmpty {
                    return (token, false)
                }
            }
        }

        throw HideError.authTokenNotFound
    }

    /// Parse a hidden list page for item IDs and the "More" link for pagination.
    private func parseHiddenListPage(html: String, baseURL: URL) -> (ids: Set<Int>, nextURL: URL?) {
        var ids = Set<Int>()

        // Find all tr class="athing" id="NNNN"
        var searchRange = html.startIndex..<html.endIndex
        let athingPattern = "class=\"athing\" id=\""
        while let match = html.range(of: athingPattern, range: searchRange) {
            let afterID = html[match.upperBound...]
            if let quoteEnd = afterID.firstIndex(of: "\""),
               let itemID = Int(html[match.upperBound..<quoteEnd]) {
                ids.insert(itemID)
            }
            searchRange = match.upperBound..<html.endIndex
        }

        // Find "More" pagination link: <a href="/hidden?id=USERNAME&p=N" ...>More</a>
        var nextURL: URL?
        if let moreRange = html.range(of: "class=\"morelink\"") {
            // Walk backward to find href="..."
            let before = html[html.startIndex..<moreRange.lowerBound]
            if let hrefRange = before.range(of: "href=\"", options: .backwards) {
                let afterHref = html[hrefRange.upperBound...]
                if let hrefEnd = afterHref.firstIndex(of: "\"") {
                    let href = String(html[hrefRange.upperBound..<hrefEnd])
                        .replacingOccurrences(of: "&amp;", with: "&")
                    if let resolved = URL(string: href, relativeTo: baseURL) {
                        nextURL = resolved.absoluteURL
                    }
                }
            }
        }

        return (ids, nextURL)
    }
}

enum HideError: LocalizedError {
    case authTokenNotFound

    var errorDescription: String? {
        switch self {
        case .authTokenNotFound: "Could not find auth token for hide action."
        }
    }
}
