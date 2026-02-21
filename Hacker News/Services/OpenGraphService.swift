import Foundation

actor OpenGraphService {
    static let shared = OpenGraphService()

    private var memoryCache: [String: String?] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ttl: TimeInterval = 24 * 60 * 60 // 24 hours

    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("OpenGraphCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func fetchImageURL(for pageURL: String) async -> String? {
        // Check memory cache
        if let cached = memoryCache[pageURL] {
            return cached
        }

        // Check disk cache
        let key = cacheKey(for: pageURL)
        let filePath = cacheDirectory.appendingPathComponent(key)
        if fileManager.fileExists(atPath: filePath.path),
           let attrs = try? fileManager.attributesOfItem(atPath: filePath.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl,
           let raw = try? String(contentsOf: filePath, encoding: .utf8) {
            let cached: String? = (raw.isEmpty || URL(string: raw) == nil) ? nil : raw
            memoryCache[pageURL] = cached
            return cached
        }

        // Deduplicate in-flight requests
        if let existing = inFlight[pageURL] {
            return await existing.value
        }

        let task = Task<String?, Never> {
            guard let url = URL(string: pageURL) else { return nil }
            do {
                var request = URLRequest(url: url, timeoutInterval: 8)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
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
        memoryCache[pageURL] = result

        // Write to disk
        try? (result ?? "").write(to: filePath, atomically: true, encoding: .utf8)

        return result
    }

    func clearExpired() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > ttl {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func cacheKey(for urlString: String) -> String {
        let data = Data(urlString.utf8)
        let hash = data.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }

    private static func extractOGImage(from html: String) -> String? {
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
