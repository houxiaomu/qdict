#!/usr/bin/env swift
//
// Generate Dictonary's AppIcon set.
//
// Usage:  swift scripts/generate-icon.swift
//
// Writes 10 PNGs (and updates Contents.json) under
// Dictonary/Resources/Assets.xcassets/AppIcon.appiconset/.
//
// To tweak the look, edit the constants in `drawIcon` below.

import AppKit
import Foundation

// MARK: - Drawing

func drawIcon(size s: CGFloat) {
    guard let ctx = NSGraphicsContext.current else { return }
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true

    // ---- 1. Blue squircle background, diagonal gradient
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgRadius = s * 0.225 // macOS Big Sur–style continuous corners (≈22.5%)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: bgRadius, yRadius: bgRadius)

    let bgTop = NSColor(red: 0.31, green: 0.60, blue: 0.97, alpha: 1.0)   // #4F99F8
    let bgBot = NSColor(red: 0.09, green: 0.32, blue: 0.78, alpha: 1.0)   // #1751C7
    let bgGradient = NSGradient(starting: bgTop, ending: bgBot)!

    NSGraphicsContext.current?.saveGraphicsState()
    bgPath.addClip()
    bgGradient.draw(in: bgRect, angle: -60) // top-leftish to bottom-right
    NSGraphicsContext.current?.restoreGraphicsState()

    // ---- 2. White "book" card, centered, slight drop shadow
    let bookW = s * 0.62
    let bookH = s * 0.78
    let bookX = (s - bookW) / 2
    let bookY = (s - bookH) / 2
    let bookRect = NSRect(x: bookX, y: bookY, width: bookW, height: bookH)
    let bookRadius = s * 0.045
    let bookPath = NSBezierPath(roundedRect: bookRect, xRadius: bookRadius, yRadius: bookRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.018)
    shadow.shadowBlurRadius = s * 0.05
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.set()

    // Book cover gradient (very subtle, near-white with a hint of cool tone)
    let coverTop = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
    let coverBot = NSColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1.0)
    let coverGradient = NSGradient(starting: coverTop, ending: coverBot)!
    bookPath.addClip()
    coverGradient.draw(in: bookRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // ---- 3. Spine: a soft blue strip on the left edge
    let spineW = bookW * 0.10
    let spineRect = NSRect(x: bookX, y: bookY, width: spineW, height: bookH)
    NSGraphicsContext.current?.saveGraphicsState()
    bookPath.addClip()
    let spineTop = NSColor(red: 0.20, green: 0.46, blue: 0.92, alpha: 1.0)
    let spineBot = NSColor(red: 0.08, green: 0.28, blue: 0.72, alpha: 1.0)
    NSGradient(starting: spineTop, ending: spineBot)!.draw(in: spineRect, angle: -90)

    // Thin highlight line on the spine's right edge
    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: bookX + spineW, y: bookY + s * 0.025))
    highlight.line(to: NSPoint(x: bookX + spineW, y: bookY + bookH - s * 0.025))
    NSColor(white: 1, alpha: 0.18).setStroke()
    highlight.lineWidth = max(s * 0.005, 0.5)
    highlight.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    // ---- 4. "D" letter: bold blue, centered on the white area (right of spine)
    let letterAreaX = bookX + spineW
    let letterAreaW = bookW - spineW
    let fontSize = bookH * 0.62
    let letterColor = NSColor(red: 0.11, green: 0.36, blue: 0.84, alpha: 1.0)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: letterColor,
        .kern: 0
    ]
    let letter = NSAttributedString(string: "D", attributes: attrs)
    let letterSize = letter.size()
    // The font's drawn rect has padding above/below the cap height; nudge baseline upward.
    let letterX = letterAreaX + (letterAreaW - letterSize.width) / 2
    let letterY = bookY + (bookH - letterSize.height) / 2 - s * 0.015
    letter.draw(at: NSPoint(x: letterX, y: letterY))
}

// MARK: - PNG output

func makePNG(size pixels: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap rep"])
    }
    rep.size = NSSize(width: pixels, height: pixels) // logical size matches pixel size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    return data
}

// MARK: - Main

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let iconsetDir = projectRoot
    .appendingPathComponent("Dictonary")
    .appendingPathComponent("Resources")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

struct Variant { let filename: String; let pixels: Int; let size: String; let scale: String }
let variants: [Variant] = [
    .init(filename: "icon_16x16.png",       pixels: 16,   size: "16x16",   scale: "1x"),
    .init(filename: "icon_16x16@2x.png",    pixels: 32,   size: "16x16",   scale: "2x"),
    .init(filename: "icon_32x32.png",       pixels: 32,   size: "32x32",   scale: "1x"),
    .init(filename: "icon_32x32@2x.png",    pixels: 64,   size: "32x32",   scale: "2x"),
    .init(filename: "icon_128x128.png",     pixels: 128,  size: "128x128", scale: "1x"),
    .init(filename: "icon_128x128@2x.png",  pixels: 256,  size: "128x128", scale: "2x"),
    .init(filename: "icon_256x256.png",     pixels: 256,  size: "256x256", scale: "1x"),
    .init(filename: "icon_256x256@2x.png",  pixels: 512,  size: "256x256", scale: "2x"),
    .init(filename: "icon_512x512.png",     pixels: 512,  size: "512x512", scale: "1x"),
    .init(filename: "icon_512x512@2x.png",  pixels: 1024, size: "512x512", scale: "2x"),
]

for v in variants {
    let data = try makePNG(size: v.pixels)
    let url = iconsetDir.appendingPathComponent(v.filename)
    try data.write(to: url)
    print("✓ \(v.filename) (\(v.pixels)px)")
}

// Contents.json
struct ImageEntry: Codable {
    let idiom: String
    let size: String
    let scale: String
    let filename: String
}
struct InfoEntry: Codable { let version: Int; let author: String }
struct Contents: Codable { let images: [ImageEntry]; let info: InfoEntry }

let contents = Contents(
    images: variants.map {
        ImageEntry(idiom: "mac", size: $0.size, scale: $0.scale, filename: $0.filename)
    },
    info: InfoEntry(version: 1, author: "xcode")
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let contentsURL = iconsetDir.appendingPathComponent("Contents.json")
try encoder.encode(contents).write(to: contentsURL)
print("✓ Contents.json")

print("\nDone. Run ./scripts/build-dmg.sh to bundle a new DMG with the icon.")
