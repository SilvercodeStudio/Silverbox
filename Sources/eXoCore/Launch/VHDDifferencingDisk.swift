import Foundation

/// Writes an empty differencing VHD over a parent disk, as eXo's
/// `makevhd.exe` does before each 86Box start.
///
/// The child holds only the sectors Windows changes, so the parent (eXo's
/// Windows 98 image) stays untouched and can sit on a read-only library.
/// 86Box reads VHDs through MiniVHD, which finds the parent from the absolute
/// path stored in the child, then checks the parent's ID and its file's
/// modification time. The layout follows MiniVHD's own writer: a footer copy,
/// the sparse header, an empty block table, the parent locators and the footer.
nonisolated public enum VHDDifferencingDisk {
    public enum Failure: Error, Equatable, LocalizedError {
        case notAVHD(URL)

        public var errorDescription: String? {
            switch self {
            case .notAVHD(let url): return "\(url.lastPathComponent) is not a VHD disk image."
            }
        }
    }

    static let sectorSize = 512
    static let blockSize = 2 * 1024 * 1024
    /// VHD time stamps count seconds from 1 January 2000, UTC.
    static let epoch = Date(timeIntervalSince1970: 946_684_800)

    /// Writes the child, replacing any file at `child`.
    public static func create(at child: URL, parent: URL) throws {
        let parentFooter = try footer(of: parent)
        let currentSize = parentFooter.uint64(at: 48)
        let modified =
            (try FileManager.default.attributesOfItem(atPath: parent.path)[.modificationDate] as? Date) ?? Date()

        let blocks = Int((currentSize + UInt64(blockSize) - 1) / UInt64(blockSize))
        let tableSectors = (blocks * 4 + sectorSize - 1) / sectorSize
        let tableOffset = sectorSize + 1024
        let locatorOffset = tableOffset + tableSectors * sectorSize + 5 * sectorSize
        let absolute = utf16LE(parent.standardizedFileURL.path)
        let relative = utf16LE(relativePath(from: child.deletingLastPathComponent(), to: parent))
        let absoluteSpace = (absolute.count / sectorSize + 1) * sectorSize
        let relativeSpace = (relative.count / sectorSize + 1) * sectorSize

        var footer = Data(count: sectorSize)
        footer.replace(at: 0, with: Data("conectix".utf8))
        footer.put(UInt32(2), at: 8)  // features: reserved bit
        footer.put(UInt32(0x0001_0000), at: 12)  // format version
        footer.put(UInt64(sectorSize), at: 16)  // offset of the sparse header
        footer.put(timestamp(Date()), at: 24)
        footer.replace(at: 28, with: Data("amac".utf8))  // creator application
        footer.put(UInt32(0x0001_0000), at: 32)
        footer.replace(at: 36, with: Data("Mac ".utf8))  // creator host
        footer.put(currentSize, at: 40)  // original size
        footer.put(currentSize, at: 48)  // current size
        footer.replace(at: 56, with: parentFooter.subdata(in: 56..<60))  // geometry
        footer.put(UInt32(4), at: 60)  // disk type: differencing
        footer.replace(at: 68, with: withUnsafeBytes(of: UUID().uuid) { Data($0) })
        footer.put(checksum(footer), at: 64)

        var header = Data(count: 1024)
        header.replace(at: 0, with: Data("cxsparse".utf8))
        header.put(UInt64.max, at: 8)  // data offset: unused
        header.put(UInt64(tableOffset), at: 16)
        header.put(UInt32(0x0001_0000), at: 24)  // header version
        header.put(UInt32(blocks), at: 28)
        header.put(UInt32(blockSize), at: 32)
        header.replace(at: 40, with: parentFooter.subdata(in: 68..<84))  // parent ID
        header.put(timestamp(modified), at: 56)
        let name = Data(parent.lastPathComponent.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }.prefix(512))
        header.replace(at: 64, with: name)
        header.putLocator(index: 0, code: "W2ku", space: absoluteSpace, length: absolute.count, offset: locatorOffset)
        header.putLocator(
            index: 1, code: "W2ru", space: relativeSpace, length: relative.count, offset: locatorOffset + absoluteSpace)
        header.put(checksum(header), at: 36)

        var disk = footer + header
        disk.append(Data(repeating: 0xFF, count: tableSectors * sectorSize))
        disk.append(Data(count: 5 * sectorSize))
        var locators = Data(count: absoluteSpace + relativeSpace)
        locators.replace(at: 0, with: absolute)
        locators.replace(at: absoluteSpace, with: relative)
        disk.append(locators)
        disk.append(Data(count: 5 * sectorSize))
        disk.append(footer)

        try FileManager.default.createDirectory(
            at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try disk.write(to: child, options: .atomic)
    }

    /// The 512-byte footer at the end of a VHD.
    static func footer(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= UInt64(sectorSize) else { throw Failure.notAVHD(url) }
        try handle.seek(toOffset: size - UInt64(sectorSize))
        let footer = try handle.read(upToCount: sectorSize) ?? Data()
        guard footer.count == sectorSize, footer.prefix(8) == Data("conectix".utf8) else {
            throw Failure.notAVHD(url)
        }
        return footer
    }

    static func timestamp(_ date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSince(epoch)))
    }

    /// One's complement of the byte sum; the checksum field must be zero.
    static func checksum(_ data: Data) -> UInt32 {
        ~data.reduce(UInt32(0)) { $0 &+ UInt32($1) }
    }

    static func utf16LE(_ string: String) -> Data {
        Data(string.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
    }

    /// `parent` relative to `folder`, with `..` steps.
    static func relativePath(from folder: URL, to parent: URL) -> String {
        let from = folder.standardizedFileURL.pathComponents
        let to = parent.standardizedFileURL.pathComponents
        var common = 0
        while common < min(from.count, to.count), from[common] == to[common] { common += 1 }
        let ups = Array(repeating: "..", count: from.count - common)
        return (ups + to[common...]).joined(separator: "/")
    }
}

nonisolated extension Data {
    fileprivate mutating func replace(at offset: Int, with bytes: Data) {
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    fileprivate mutating func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        replace(at: offset, with: Swift.withUnsafeBytes(of: value.bigEndian) { Data($0) })
    }

    fileprivate mutating func putLocator(index: Int, code: String, space: Int, length: Int, offset: Int) {
        let base = 576 + index * 24
        replace(at: base, with: Data(code.utf8))
        put(UInt32(space), at: base + 4)
        put(UInt32(length), at: base + 8)
        put(UInt64(offset), at: base + 16)
    }

    func uint64(at offset: Int) -> UInt64 {
        self[offset..<(offset + 8)].reduce(0) { $0 << 8 | UInt64($1) }
    }

    func uint32(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
