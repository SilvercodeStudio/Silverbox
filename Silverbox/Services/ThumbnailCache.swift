import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SilverboxCore
import Synchronization
import UniformTypeIdentifiers

/// A decoded image that can cross isolation boundaries. `CGImage` is
/// immutable, so sharing it is safe.
struct CGImageBox: @unchecked Sendable {
    let image: CGImage
}

/// Decodes downsampled images off the main thread and keeps the most recent
/// ones in memory. Box art for thousands of games is loaded through here.
/// Small sizes also go to a ``ThumbnailDiskCache``, so covers on a network
/// share are read from the share once, not at each start or long scroll.
actor ThumbnailCache {
    private var images: [String: CGImageBox] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<CGImageBox?, Never>] = [:]
    private let limit: Int
    let disk: ThumbnailDiskCache?
    private var writesSinceTrim = 0

    init(limit: Int = 800, disk: ThumbnailDiskCache? = nil) {
        self.limit = limit
        self.disk = disk
        if let disk { Task.detached(priority: .background) { disk.trim() } }
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
        let disk = maxPixelSize <= ThumbnailDiskCache.maxPixelSize ? self.disk : nil
        let task = Task.detached(priority: .userInitiated) { () -> CGImageBox? in
            if let saved = disk?.load(url: url, maxPixelSize: maxPixelSize) { return saved }
            guard let decoded = ThumbnailCache.decode(url: url, maxPixelSize: maxPixelSize) else { return nil }
            if let disk {
                Task.detached(priority: .utility) {
                    disk.save(decoded.box, url: url, maxPixelSize: maxPixelSize, downscaled: decoded.downscaled)
                }
            }
            return decoded.box
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { store(key, result) }
        return result
    }

    /// Forgets every image, in memory and on disk, for Rescan Library.
    func clear() {
        images = [:]
        order = []
        writesSinceTrim = 0
        disk?.clear()
    }

    /// The thumbnail, and whether it is smaller than the original. A copy
    /// at full size keeps every pixel on disk, for pixel art.
    nonisolated static func decode(url: URL, maxPixelSize: Int) -> (box: CGImageBox, downscaled: Bool)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let downscaled = max(width, height) > max(image.width, image.height)
        return (CGImageBox(image: image), downscaled)
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

/// Thumbnails saved in the app's cache folder, one file each, named by a
/// hash of the image's path and the pixel size. A saved thumbnail is used
/// without looking at the original again, because that look is what costs
/// on a share; Rescan Library clears them. When the folder grows past
/// `byteLimit`, the least recently used files go.
nonisolated final class ThumbnailDiskCache: Sendable {
    /// Grid tiles, filmstrips and the inspector's gallery; larger images
    /// are read from the original each time.
    static let maxPixelSize = 600

    let directory: URL
    let byteLimit: Int
    /// Saves since the last trim, so a long scroll trims as it goes.
    private let saves = Mutex(0)

    init(directory: URL, byteLimit: Int = 300 * 1024 * 1024) {
        self.directory = directory
        self.byteLimit = byteLimit
    }

    func fileURL(for url: URL, maxPixelSize: Int) -> URL {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let name = String(hash, radix: 16)
        return directory.appendingPathComponent(String(name.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(name)-\(maxPixelSize)")
    }

    func load(url: URL, maxPixelSize: Int) -> CGImageBox? {
        let file = fileURL(for: url, maxPixelSize: maxPixelSize)
        guard let data = FileManager.default.contents(atPath: file.path),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        // The modification date records the last use, for trim().
        utimes(file.path, nil)
        return CGImageBox(image: image)
    }

    /// Writes JPEG for opaque thumbnails that were scaled down, PNG for the
    /// rest: transparency, and pixel art at its own size, stay as they are.
    func save(_ box: CGImageBox, url: URL, maxPixelSize: Int, downscaled: Bool) {
        let image = box.image
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = (opaque && downscaled ? UTType.jpeg : UTType.png).identifier as CFString
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        let file = fileURL(for: url, maxPixelSize: maxPixelSize)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: [.atomic])) != nil else { return }
        let due = saves.withLock { count in
            count += 1
            guard count >= 500 else { return false }
            count = 0
            return true
        }
        if due { trim() }
    }

    /// Removes the least recently used thumbnails until the folder holds
    /// at most three quarters of `byteLimit`.
    func trim() {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return }
        var files: [(url: URL, size: Int, used: Date)] = []
        var total = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            let size = values.totalFileAllocatedSize ?? 0
            files.append((url, size, values.contentModificationDate ?? .distantPast))
            total += size
        }
        guard total > byteLimit else { return }
        for file in files.sorted(by: { $0.used < $1.used }) {
            guard total > byteLimit * 3 / 4 else { break }
            if (try? FileManager.default.removeItem(at: file.url)) != nil { total -= file.size }
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
