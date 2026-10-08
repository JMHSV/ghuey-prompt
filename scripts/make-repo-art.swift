// Renders GitHub's social preview and README banner using the existing app icon.
// Run from the repository root: swift scripts/make-repo-art.swift
import AppKit

let output = URL(fileURLWithPath: ".github/assets", isDirectory: true)
let iconURL = URL(fileURLWithPath: "GhueyPrompt/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
guard let icon = NSImage(contentsOf: iconURL) else {
    fatalError("Couldn't load the app icon at \(iconURL.path)")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let ink = color(0.055, 0.052, 0.078)
let white = color(0.96, 0.95, 0.99)
let lavender = color(0.73, 0.68, 1.0)
let muted = color(0.64, 0.62, 0.72)

func text(_ value: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          foreground: NSColor = white, serif: Bool = false, tracking: CGFloat = 0) {
    let font = serif ? (NSFont(name: "Georgia-Italic", size: size) ?? .systemFont(ofSize: size))
        : .systemFont(ofSize: size, weight: weight)
    (value as NSString).draw(at: point, withAttributes: [
        .font: font, .foregroundColor: foreground, .kern: tracking,
    ])
}

func background(width: CGFloat, height: CGFloat) {
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    ink.setFill()
    bounds.fill()
    let glow = NSBezierPath(ovalIn: NSRect(x: -210, y: -140, width: 1050, height: height + 430))
    NSGradient(colors: [color(0.30, 0.22, 0.57, 0.46), color(0.10, 0.08, 0.17, 0)])!
        .draw(in: glow, relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
    let upperGlow = NSBezierPath(ovalIn: NSRect(x: 720, y: height - 260, width: 650, height: 480))
    NSGradient(colors: [color(0.37, 0.27, 0.62, 0.18), color(0.10, 0.08, 0.17, 0)])!
        .draw(in: upperGlow, relativeCenterPosition: .zero)
    let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 20, dy: 20), xRadius: 24, yRadius: 24)
    color(1, 1, 1, 0.08).setStroke()
    border.lineWidth = 1
    border.stroke()
}

func render(_ name: String, width: Int, height: Int, draw: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("Couldn't create the bitmap for \(name)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    background(width: CGFloat(width), height: CGFloat(height))
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Couldn't encode \(name)")
    }
    let path = output.appendingPathComponent(name)
    try png.write(to: path, options: .atomic)
    print("\(path.path) (\(width)×\(height), \(png.count) bytes)")
}

try render("social-preview.png", width: 1280, height: 640) {
    icon.draw(in: NSRect(x: 72, y: 204, width: 300, height: 300))
    text("Ghuey Prompt", at: NSPoint(x: 410, y: 445), size: 44, weight: .semibold)
    text("Your prompts,", at: NSPoint(x: 406, y: 325), size: 64, weight: .medium)
    text("one edge away.", at: NSPoint(x: 408, y: 249), size: 66, foreground: lavender, serif: true)
    text("Save once. Insert anywhere.", at: NSPoint(x: 410, y: 192), size: 24, foreground: muted)
    text("NATIVE MACOS", at: NSPoint(x: 92, y: 65), size: 14, weight: .medium, foreground: muted, tracking: 2)
    text("LOCAL STORAGE", at: NSPoint(x: 366, y: 65), size: 14, weight: .medium, foreground: muted, tracking: 2)
    text("ICLOUD OPTIONAL", at: NSPoint(x: 690, y: 65), size: 14, weight: .medium, foreground: muted, tracking: 2)
}

try render("readme-banner.png", width: 1280, height: 360) {
    icon.draw(in: NSRect(x: 78, y: 70, width: 220, height: 220))
    text("Your prompts,", at: NSPoint(x: 348, y: 211), size: 52, weight: .medium)
    text("one edge away.", at: NSPoint(x: 350, y: 148), size: 55, foreground: lavender, serif: true)
    text("Save once. Insert anywhere.", at: NSPoint(x: 352, y: 101), size: 22, foreground: muted)
}
