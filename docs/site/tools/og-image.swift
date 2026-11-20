// Makes the link preview (og:image) from the hero screenshot: the window centered on the site's dark
// ground, 1200x630, as JPEG, which every link preview reads (some do not read WebP).
//
//   swift docs/site/tools/og-image.swift docs/site/images/library-dark-2400.webp docs/site/images/og-image.jpg
import ImageIO
import UniformTypeIdentifiers
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let W = 1200, H = 630
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(red: 0x14/255, green: 0x10/255, blue: 0x0b/255, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let margin = 28.0
let scale = min((Double(W) - 2*margin)/Double(img.width), (Double(H) - 2*margin)/Double(img.height))
let w = Double(img.width)*scale, h = Double(img.height)*scale
ctx.interpolationQuality = .high
ctx.draw(img, in: CGRect(x: (Double(W)-w)/2, y: (Double(H)-h)/2, width: w, height: h))
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
CGImageDestinationFinalize(d)
