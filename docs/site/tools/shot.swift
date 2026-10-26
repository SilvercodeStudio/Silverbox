// Crops a window capture to the window's edge and writes the images the site uses.
//
//   swift docs/site/tools/shot.swift capture.png docs/site/images/<name> [--trim L,T,R,B]
//
// writes <name>-2400.webp and <name>-1200.webp (JPEG when cwebp, from `brew install webp`, is not
// installed). The capture is a macOS window screenshot
// (Shift-Command-4, Space): a thin margin of desktop surrounds the window, and the tool
// finds the edge where the pixels stop matching the margin, along many rows and columns.
// When another window shows at an edge, --trim cuts that many more pixels from each side.
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 || (arguments.count == 5 && arguments[3] == "--trim") else {
    FileHandle.standardError.write(Data("usage: shot.swift capture.png images/<name> [--trim L,T,R,B]\n".utf8))
    exit(2)
}
let trim = arguments.count == 5 ? arguments[4].split(separator: ",").map { Int($0) ?? 0 } : [0, 0, 0, 0]
guard trim.count == 4 else {
    FileHandle.standardError.write(Data("--trim takes four numbers: left,top,right,bottom\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: arguments[1])
let outputBase = arguments[2]
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else {
    FileHandle.standardError.write(Data("cannot read \(source.path)\n".utf8))
    exit(1)
}

let width = image.width, height = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = context.data!.assumingMemoryBound(to: UInt8.self)

func pixel(_ x: Int, _ yFromTop: Int) -> (Int, Int, Int) {
    let i = ((height - 1 - yFromTop) * width + x) * 4
    return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
}
func differs(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
    max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2)) > 10
}
func edgeFromTop(_ x: Int) -> Int { var y = 0; let r = pixel(x, 0); while y < height && !differs(pixel(x, y), r) { y += 1 }; return y }
func edgeFromBottom(_ x: Int) -> Int { var y = height - 1; let r = pixel(x, y); while y > 0 && !differs(pixel(x, y), r) { y -= 1 }; return y }
func edgeFromLeft(_ y: Int) -> Int { var x = 0; let r = pixel(0, y); while x < width && !differs(pixel(x, y), r) { x += 1 }; return x }
func edgeFromRight(_ y: Int) -> Int { var x = width - 1; let r = pixel(x, y); while x > 0 && !differs(pixel(x, y), r) { x -= 1 }; return x }

let columns = Array(stride(from: width / 10, to: width * 9 / 10, by: 37))
let rows = Array(stride(from: height / 10, to: height * 9 / 10, by: 37))
let top = columns.map(edgeFromTop).min()! + trim[1], bottom = columns.map(edgeFromBottom).max()! - trim[3]
let left = rows.map(edgeFromLeft).min()! + trim[0], right = rows.map(edgeFromRight).max()! - trim[2]
let rect = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
print("\(source.lastPathComponent): \(width)x\(height), window at \(left),\(top) \(Int(rect.width))x\(Int(rect.height))")
let cropped = image.cropping(to: rect)!

let cwebp = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"].first { FileManager.default.isExecutableFile(atPath: $0) }
for targetWidth in [2400, 1200] {
    let targetHeight = Int((Double(cropped.height) * Double(targetWidth) / Double(cropped.width)).rounded())
    let scaled = CGContext(
        data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8, bytesPerRow: targetWidth * 4,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    scaled.interpolationQuality = .high
    scaled.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
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
