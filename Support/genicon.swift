// Renders the app icon as an .iconset directory of PNGs.
// Usage: swift Support/genicon.swift <output-iconset-dir>
// The glyph mirrors PullRequestIcon in the app (octicon git-pull-request,
// 16×16 design space) on a dark squircle following Apple's icon grid.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let green = CGColor(red: 0.247, green: 0.725, blue: 0.314, alpha: 1) // GitHub #3fb950

func render(px: Int) -> CGImage {
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Apple icon grid: 824pt squircle centered in a 1024pt canvas.
    let inset = s * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    let top = CGColor(red: 0.16, green: 0.19, blue: 0.23, alpha: 1)
    let bottom = CGColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: .zero, options: [])

    // Map the 16×16 (y-down) glyph space into the squircle, centered.
    let glyphSide = rect.width * 0.62
    let scale = glyphSide / 16
    ctx.translateBy(x: (s - glyphSide) / 2, y: (s + glyphSide) / 2)
    ctx.scaleBy(x: scale, y: -scale)

    ctx.setStrokeColor(green)
    ctx.setFillColor(green)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)

    func circle(_ x: CGFloat, _ y: CGFloat) {
        ctx.strokeEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
    }

    // Left rail: circle, line, circle. Bottom-right circle.
    circle(3.25, 3.25)
    circle(3.25, 12.75)
    circle(12.75, 12.75)
    ctx.move(to: CGPoint(x: 3.25, y: 5.6))
    ctx.addLine(to: CGPoint(x: 3.25, y: 10.4))
    ctx.strokePath()

    // Arrow curving from the top into the right rail.
    ctx.move(to: CGPoint(x: 8.0, y: 3.25))
    ctx.addLine(to: CGPoint(x: 10.5, y: 3.25))
    ctx.addQuadCurve(to: CGPoint(x: 12.75, y: 5.5), control: CGPoint(x: 12.75, y: 3.25))
    ctx.addLine(to: CGPoint(x: 12.75, y: 10.4))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: 8.3, y: 1.1))
    ctx.addLine(to: CGPoint(x: 8.3, y: 5.4))
    ctx.addLine(to: CGPoint(x: 6.0, y: 3.25))
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()!
}

func save(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift genicon.swift <output-iconset-dir>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    save(render(px: variant.px), to: outDir.appendingPathComponent("\(variant.name).png"))
}
