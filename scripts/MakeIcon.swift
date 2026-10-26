// Builds macOS icon sizes from the approved Ayrvo master and a template-safe folded mark.
// Run: swift scripts/MakeIcon.swift <outdir> [app|menu|all]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconMode: String { case all, app, menu }
let args = CommandLine.arguments
guard (2...3).contains(args.count),
      let mode = IconMode(rawValue: args.count == 3 ? args[2] : "all") else {
    fputs("usage: swift MakeIcon.swift <outdir> [app|menu|all]\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ pixels: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                  bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Cannot allocate a \(pixels)-pixel icon")
    }
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    return context
}

func writePNG(_ context: CGContext, to url: URL) {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot create \(url.path)") }
    // Dock and template icons must keep transparent corners.
    precondition(context.data!.assumingMemoryBound(to: UInt8.self)[3] == 0)
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
    guard let saved = CGImageSourceCreateWithURL(url as CFURL, nil),
          let decoded = CGImageSourceCreateImageAtIndex(saved, 0, nil) else {
        fatalError("Cannot verify \(url.path)")
    }
    precondition(decoded.width == context.width && decoded.height == context.height)
}

// The two separated planes preserve the approved folded silhouette at 18 points.
func drawMenuMark(in context: CGContext, pixels: Int) {
    context.translateBy(x: CGFloat(pixels) * 2 / 44, y: CGFloat(pixels))
    context.scaleBy(x: CGFloat(pixels) / 44, y: -CGFloat(pixels) / 44)
    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 6, y: 15))
    mark.addCurve(to: CGPoint(x: 10, y: 9), control1: CGPoint(x: 6, y: 12), control2: CGPoint(x: 7, y: 10.5))
    mark.addLine(to: CGPoint(x: 27, y: 1))
    mark.addCurve(to: CGPoint(x: 32, y: 4), control1: CGPoint(x: 30, y: -0.5), control2: CGPoint(x: 32, y: 1))
    mark.addLine(to: CGPoint(x: 32, y: 11))
    mark.addCurve(to: CGPoint(x: 29, y: 16), control1: CGPoint(x: 32, y: 13), control2: CGPoint(x: 31, y: 15))
    mark.addLine(to: CGPoint(x: 11, y: 25))
    mark.addCurve(to: CGPoint(x: 6, y: 22), control1: CGPoint(x: 8, y: 26.5), control2: CGPoint(x: 6, y: 25))
    mark.closeSubpath()
    mark.move(to: CGPoint(x: 9, y: 30))
    mark.addCurve(to: CGPoint(x: 12, y: 26), control1: CGPoint(x: 9, y: 28), control2: CGPoint(x: 10, y: 27))
    mark.addLine(to: CGPoint(x: 30, y: 17))
    mark.addCurve(to: CGPoint(x: 35, y: 20), control1: CGPoint(x: 33, y: 15.5), control2: CGPoint(x: 35, y: 17))
    mark.addLine(to: CGPoint(x: 35, y: 27))
    mark.addCurve(to: CGPoint(x: 31, y: 33), control1: CGPoint(x: 35, y: 30), control2: CGPoint(x: 34, y: 31.5))
    mark.addLine(to: CGPoint(x: 14, y: 41))
    mark.addCurve(to: CGPoint(x: 9, y: 38), control1: CGPoint(x: 11, y: 42.5), control2: CGPoint(x: 9, y: 41))
    mark.closeSubpath()
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.addPath(mark)
    context.fillPath()
}

if mode == .all || mode == .app {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let masterURL = root.appendingPathComponent("Resources/AyrvoIcon.png")
    guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
          let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot read the approved master at \(masterURL.path)")
    }
    precondition(master.width == master.height && master.width >= 1024)
    let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    let entries = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for (name, pixels) in entries + [("AppIcon-1024.png", 1024)] {
        let context = makeContext(pixels)
        context.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let destination = name == "AppIcon-1024.png" ? output : iconset
        writePNG(context, to: destination.appendingPathComponent(name))
    }
}
if mode == .all || mode == .menu {
    for (name, pixels) in [("NavIcon.png", 18), ("NavIcon@2x.png", 36), ("NavIcon-preview.png", 288)] {
        let context = makeContext(pixels)
        drawMenuMark(in: context, pixels: pixels)
        writePNG(context, to: output.appendingPathComponent(name))
    }
}
print("Wrote and verified \(mode.rawValue) icons in \(output.path)")
