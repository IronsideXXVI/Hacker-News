import Foundation

actor OpenGraphService {
    static let shared = OpenGraphService()

    private var cache: [String: String?] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]

    func fetchImageURL(for pageURL: String) async -> String? {
        if let cached = cache[pageURL] {
            return cached
        }

        if let existing = inFlight[pageURL] {
            return await existing.value
        }

        let task = Task<String?, Never> {
            guard let url = URL(string: pageURL) else { return nil }
            do {
                var request = URLRequest(url: url, timeoutInterval: 8)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
                // Only fetch the first chunk — og:image is in the <head>
                let (data, _) = try await URLSession.shared.data(for: request)
                let html: String
                if data.count > 50_000 {
                    html = String(decoding: data.prefix(50_000), as: UTF8.self)
                } else {
                    html = String(decoding: data, as: UTF8.self)
                }
                return Self.extractOGImage(from: html)
            } catch {
                return nil
            }
        }

        inFlight[pageURL] = task
        let result = await task.value
        inFlight[pageURL] = nil
        cache[pageURL] = result
        return result
    }

    private static func extractOGImage(from html: String) -> String? {
        // Match <meta property="og:image" content="...">
        let patterns = [
            #"<meta[^>]+property\s*=\s*["']og:image["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']og:image["']"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let urlString = String(html[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                guard URL(string: urlString) != nil else { return nil }
                return urlString
            }
        }
        return nil
    }
}
