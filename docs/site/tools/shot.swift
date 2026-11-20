// Crops a window capture to the window's edge and writes the images the site uses.
//
//   swift docs/site/tools/shot.swift capture.png docs/site/images/<name>
//       [--trim L,T,R,B] [--rect X,Y,W,H] [--radius R] [--widths 2400,1200]
//
// writes <name>-2400.webp and <name>-1200.webp (JPEG when cwebp, from `brew install webp`, is not
// installed; JPEG has no transparency, so --radius needs cwebp). The capture is a box drawn around
// a window with Shift-Command-4: a thin margin of desktop surrounds the window, and the tool finds
// the edge where the pixels stop matching the margin, along many rows and columns (the median, so
// a desktop icon or label in the margin does not move it).
//
// A capture of one window (Shift-Command-4, Space, then Option-click the window, for no shadow)
// has transparent corners and nothing around the window. The tool keeps its transparency and
// crops to its opaque pixels, for a window in front of another, or a sheet.
//
//   --trim    cuts that many more pixels from each side, when another window shows at an edge.
//   --rect    crops that rectangle instead (pixels, from the top left), for a window over another,
//             such as the welcome or Settings in front of the main window.
//   --radius  makes the corners outside a rounded rectangle of that radius (pixels) transparent,
//             so no desktop shows past the window's round corners (about 36 for a window).
//   --widths  the widths to write, for a small window (Settings: 1200,600).
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    fail(
        "usage: shot.swift capture.png images/<name> [--trim L,T,R,B] [--rect X,Y,W,H] [--radius R]"
            + " [--widths 2400,1200]")
}
let source = URL(fileURLWithPath: arguments.removeFirst())
let outputBase = arguments.removeFirst()
var options: [String: [Int]] = [:]
while arguments.count >= 2 {
    let name = arguments.removeFirst(), value = arguments.removeFirst()
    guard ["--trim", "--rect", "--radius", "--widths"].contains(name) else { fail("unknown option \(name)") }
    options[name] = value.split(separator: ",").map { Int($0) ?? 0 }
}
guard arguments.isEmpty else { fail("\(arguments[0]) needs a value") }
let trim = options["--trim"] ?? [0, 0, 0, 0]
guard trim.count == 4 else { fail("--trim takes four numbers: left,top,right,bottom") }
let widths = options["--widths"] ?? [2400, 1200]
let radius = options["--radius"]?.first ?? 0

guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else { fail("cannot read \(source.path)") }

let width = image.width, height = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()

/// The capture's pixels, premultiplied RGBA from the top row.
let pixels: UnsafeMutablePointer<UInt8> = {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let copy = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
    copy.initialize(from: context.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
    return copy
}()

/// A capture of one window: its corner is transparent.
let isWindowCapture = pixels[3] == 0

/// The rectangle of a window capture's opaque pixels: the window, without any shadow.
func opaqueRect() -> CGRect {
    var (left, top, right, bottom) = (width, height, -1, -1)
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] >= 250 {
            left = min(left, x)
            right = max(right, x)
            top = min(top, y)
            bottom = max(bottom, y)
        }
    }
    guard right >= left else { fail("the capture has no opaque pixels") }
    return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
}

func windowRect() -> CGRect {
    func pixel(_ x: Int, _ yFromTop: Int) -> (Int, Int, Int) {
        let i = (yFromTop * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }
    func differs(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2)) > 10
    }
    func edgeFromTop(_ x: Int) -> Int {
        var y = 0
        let r = pixel(x, 0)
        while y < height && !differs(pixel(x, y), r) { y += 1 }
        return y
    }
    func edgeFromBottom(_ x: Int) -> Int {
        var y = height - 1
        let r = pixel(x, y)
        while y > 0 && !differs(pixel(x, y), r) { y -= 1 }
        return y
    }
    func edgeFromLeft(_ y: Int) -> Int {
        var x = 0
        let r = pixel(0, y)
        while x < width && !differs(pixel(x, y), r) { x += 1 }
        return x
    }
    func edgeFromRight(_ y: Int) -> Int {
        var x = width - 1
        let r = pixel(x, y)
        while x > 0 && !differs(pixel(x, y), r) { x -= 1 }
        return x
    }
    func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
    let columns = Array(stride(from: width / 10, to: width * 9 / 10, by: 37))
    let rows = Array(stride(from: height / 10, to: height * 9 / 10, by: 37))
    let top = median(columns.map(edgeFromTop)) + trim[1]
    let bottom = median(columns.map(edgeFromBottom)) - trim[3]
    let left = median(rows.map(edgeFromLeft)) + trim[0]
    let right = median(rows.map(edgeFromRight)) - trim[2]
    return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
}

let rect: CGRect
if let r = options["--rect"] {
    guard r.count == 4 else { fail("--rect takes four numbers: x,y,width,height") }
    rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
} else {
    rect = isWindowCapture ? opaqueRect() : windowRect()
}
print(
    "\(source.lastPathComponent): \(width)x\(height), window at \(Int(rect.minX)),\(Int(rect.minY))"
        + " \(Int(rect.width))x\(Int(rect.height))")
let cropped = image.cropping(to: rect)!
if let largest = widths.max(), Int(rect.width) < largest {
    print("  The window is \(Int(rect.width)) pixels wide, less than \(largest): take the screenshot on a Retina display.")
}

let cwebp = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"].first { FileManager.default.isExecutableFile(atPath: $0) }
// A window capture keeps its transparent corners, as --radius makes them.
let keepsAlpha = radius > 0 || isWindowCapture
if keepsAlpha && cwebp == nil { fail("--radius and a window capture need cwebp: brew install webp") }
for targetWidth in widths {
    let targetHeight = Int((Double(cropped.height) * Double(targetWidth) / Double(cropped.width)).rounded())
    let scaled = CGContext(
        data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8, bytesPerRow: targetWidth * 4,
        space: colorSpace,
        bitmapInfo: (keepsAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    scaled.interpolationQuality = .high
    let bounds = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    if radius > 0 && !isWindowCapture {
        let r = CGFloat(radius) * CGFloat(targetWidth) / rect.width
        scaled.addPath(CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil))
        scaled.clip()
    }
    scaled.draw(cropped, in: bounds)
    let result = scaled.makeImage()!
    if let cwebp {
        // A lossless PNG goes to cwebp, so the WebP is encoded once, from the full-quality pixels.
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("shot-\(UUID().uuidString).png")
        let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, result, nil)
        CGImageDestinationFinalize(destination)
        let url = URL(fileURLWithPath: "\(outputBase)-\(targetWidth).webp")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cwebp)
        process.arguments = ["-quiet", "-q", "88", "-sharp_yuv", png.path, "-o", url.path]
        try! process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: png)
        print("  \(url.path) \(targetWidth)x\(targetHeight)")
    } else {
        let url = URL(fileURLWithPath: "\(outputBase)-\(targetWidth).jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, result, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        CGImageDestinationFinalize(destination)
        print("  \(url.path) \(targetWidth)x\(targetHeight)")
    }
}
