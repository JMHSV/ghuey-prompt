// Renders the app icon and the menu bar icon into the asset catalog.
// Usage: swift scripts/make-icon.swift <Assets.xcassets directory>
import AppKit

let assetCatalog = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard assetCatalog.pathExtension == "xcassets" else {
    fatalError("Expected an .xcassets directory, got \(assetCatalog.path)")
}

// Artwork on a 1024pt canvas in SVG coordinates (y grows downward):
// a goose floating on two lines of text.
let goose = """
M 226 474 C 290 428 380 416 470 422 C 540 424 592 428 594 396 C 600 340 586 296 600 250 \
C 610 206 664 192 694 220 L 784 252 C 790 256 788 262 782 264 L 700 270 C 668 292 658 360 668 432 \
C 676 492 742 530 742 592 C 742 638 704 664 648 664 L 430 664 C 320 664 262 600 226 474 Z
"""
let gooseBounds = CGRect(x: 226, y: 192, width: 564, height: 472)
let eye = CGRect(x: 648, y: 222, width: 20, height: 20)
let textLines = [CGRect(x: 236, y: 716, width: 552, height: 40), CGRect(x: 236, y: 792, width: 360, height: 40)]

/// Parses the absolute M, L, C and Z commands used by the artwork above.
func artworkPath(_ data: String) -> NSBezierPath {
    let tokens = data.split(whereSeparator: \.isWhitespace)
    var index = 0
    func point() -> NSPoint {
        defer { index += 2 }
        return NSPoint(x: Double(tokens[index])!, y: Double(tokens[index + 1])!)
    }
    let path = NSBezierPath()
    while index < tokens.count {
        let command = tokens[index]
        index += 1
        switch command {
        case "M": path.move(to: point())
        case "L": path.line(to: point())
        case "C":
            let control1 = point(), control2 = point(), end = point()
            path.curve(to: end, controlPoint1: control1, controlPoint2: control2)
        case "Z": path.close()
        default: fatalError("Unsupported path command \(command)")
        }
    }
    return path
}

/// Maps artwork coordinates (y down, starting at `origin`) onto a bitmap `height` pixels tall (y up).
func artworkTransform(scale: CGFloat, origin: CGPoint = .zero, height: CGFloat) -> AffineTransform {
    AffineTransform(m11: scale, m12: 0, m21: 0, m22: -scale, tX: -origin.x * scale, tY: height + origin.y * scale)
}

func bitmap(width: Int, height: Int, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func renderAppIcon(pixels: Int) -> Data {
    bitmap(width: pixels, height: pixels) {
        let size = CGFloat(pixels)
        let scale = size / 1024

        // macOS icon grid: an 824pt squircle centered on a 1024pt canvas.
        let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
        let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * scale, yRadius: 185 * scale)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 24 * scale
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.black.setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.11, blue: 0.52, alpha: 1),
        ])!.draw(in: squircle, angle: -90)

        // Soft top highlight.
        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
            .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        let transform = artworkTransform(scale: scale, height: size)
        let artwork = artworkPath(goose)
        for line in textLines {
            artwork.append(NSBezierPath(roundedRect: line, xRadius: line.height / 2, yRadius: line.height / 2))
        }
        artwork.transform(using: transform)
        NSColor.white.setFill()
        artwork.fill()

        let eyePath = NSBezierPath(ovalIn: eye)
        eyePath.transform(using: transform)
        NSColor(calibratedRed: 0.3, green: 0.24, blue: 0.78, alpha: 1).setFill()
        eyePath.fill()
    }
}

/// The goose alone, as a template image: macOS tints it for the menu bar.
func renderStatusIcon(points: CGSize, scale: Int) -> Data {
    let width = Int(points.width) * scale, height = Int(points.height) * scale
    return bitmap(width: width, height: height) {
        let fit = CGFloat(height) / gooseBounds.height
        let inset = (CGFloat(width) / fit - gooseBounds.width) / 2
        let path = artworkPath(goose)
        path.transform(using: artworkTransform(
            scale: fit, origin: CGPoint(x: gooseBounds.minX - inset, y: gooseBounds.minY), height: CGFloat(height)
        ))
        NSColor.black.setFill()
        path.fill()
    }
}

func writeContents(_ images: [[String: String]], properties: [String: Any] = [:], to directory: URL) throws {
    var contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    if !properties.isEmpty { contents["properties"] = properties }
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appending(path: "Contents.json"))
}

let appIcon = assetCatalog.appending(path: "AppIcon.appiconset", directoryHint: .isDirectory)
var appIconImages: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try renderAppIcon(pixels: points * scale).write(to: appIcon.appending(path: name))
        appIconImages.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
try writeContents(appIconImages, to: appIcon)

let statusIcon = assetCatalog.appending(path: "StatusIcon.imageset", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: statusIcon, withIntermediateDirectories: true)
var statusIconImages: [[String: String]] = []
for scale in [1, 2] {
    let name = "status@\(scale)x.png"
    try renderStatusIcon(points: CGSize(width: 20, height: 16), scale: scale).write(to: statusIcon.appending(path: name))
    statusIconImages.append(["idiom": "mac", "scale": "\(scale)x", "filename": name])
}
try writeContents(statusIconImages, properties: ["template-rendering-intent": "template"], to: statusIcon)
