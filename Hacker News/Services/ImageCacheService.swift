import AppKit
import Foundation

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ttl: TimeInterval = 24 * 60 * 60 // 24 hours

    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("StoryCardImages", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.countLimit = 200
    }

    func image(for url: URL) async -> NSImage? {
        let key = cacheKey(for: url)

        // Check memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        let filePath = cacheDirectory.appendingPathComponent(key)
        if fileManager.fileExists(atPath: filePath.path),
           let attrs = try? fileManager.attributesOfItem(atPath: filePath.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < ttl,
           let image = NSImage(contentsOf: filePath) {
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }

        // Download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: key as NSString)
            try? data.write(to: filePath, options: .atomic)
            return image
        } catch {
            return nil
        }
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

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        // Simple hash to create a safe filename
        let hash = data.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }
}
