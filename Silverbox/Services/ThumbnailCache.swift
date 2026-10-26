import CoreGraphics
import Foundation
import ImageIO
import SilverboxCore

/// A decoded image that can cross isolation boundaries. `CGImage` is
/// immutable, so sharing it is safe.
struct CGImageBox: @unchecked Sendable {
    let image: CGImage
}

/// Decodes downsampled images off the main thread and keeps the most recent
/// ones in memory. Box art for thousands of games is loaded through here.
actor ThumbnailCache {
    private var images: [String: CGImageBox] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<CGImageBox?, Never>] = [:]
    private let limit: Int

    init(limit: Int = 800) {
        self.limit = limit
    }

    func image(for url: URL, maxPixelSize: Int) async -> CGImageBox? {
        let key = "\(url.path)#\(maxPixelSize)"
        if let cached = images[key] {
            touch(key)
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task.detached(priority: .userInitiated) {
            ThumbnailCache.decode(url: url, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { store(key, result) }
        return result
    }

    nonisolated static func decode(url: URL, maxPixelSize: Int) -> CGImageBox? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return CGImageBox(image: image)
    }

    private func store(_ key: String, _ box: CGImageBox) {
        images[key] = box
        order.append(key)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            images[oldest] = nil
        }
    }

    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
    }
}
