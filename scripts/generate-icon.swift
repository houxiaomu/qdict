#!/usr/bin/env swift
//
// Generate QDict's AppIcon set.
//
// Usage:  swift scripts/generate-icon.swift
//
// Writes 10 PNGs (and updates Contents.json) under
// QDict/Resources/Assets.xcassets/AppIcon.appiconset/.
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

    // ---- 2. Page block (the "thickness" layer behind the cover). Drawn
    // slightly offset up-and-right so it peeks out as visible page edges,
    // giving the icon real "this is a 3D book" cues.
    let bookW = s * 0.60
    let bookH = s * 0.74
    let bookX = (s - bookW) / 2
    let bookY = (s - bookH) / 2 - s * 0.01 // shifted down a hair to balance after offset
    let pageOffsetX = s * 0.022
    let pageOffsetY = s * 0.018
    let bookRadius = s * 0.05

    let pageRect = NSRect(
        x: bookX + pageOffsetX,
        y: bookY + pageOffsetY,
        width: bookW,
        height: bookH
    )
    let pagePath = NSBezierPath(roundedRect: pageRect, xRadius: bookRadius, yRadius: bookRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    pageShadow.shadowBlurRadius = s * 0.04
    pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    pageShadow.set()
    NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1.0).setFill() // cream page edge
    pagePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Thin horizontal lines on the visible top of the page block — reads as
    // stacked pages.
    NSGraphicsContext.current?.saveGraphicsState()
    pagePath.addClip()
    let pageLineColor = NSColor(red: 0.78, green: 0.74, blue: 0.65, alpha: 0.9)
    pageLineColor.setStroke()
    let lineWidth = max(s * 0.006, 0.5)
    for i in 1...3 {
        let y = pageRect.maxY - CGFloat(i) * s * 0.010
        let line = NSBezierPath()
        line.move(to: NSPoint(x: pageRect.minX + s * 0.04, y: y))
        line.line(to: NSPoint(x: pageRect.maxX - s * 0.015, y: y))
        line.lineWidth = lineWidth
        line.stroke()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    // ---- 3. Front cover (white card)
    let bookRect = NSRect(x: bookX, y: bookY, width: bookW, height: bookH)
    let bookPath = NSBezierPath(roundedRect: bookRect, xRadius: bookRadius, yRadius: bookRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    let coverShadow = NSShadow()
    coverShadow.shadowOffset = NSSize(width: -s * 0.005, height: -s * 0.018)
    coverShadow.shadowBlurRadius = s * 0.05
    coverShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    coverShadow.set()

    let coverTop = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
    let coverBot = NSColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1.0)
    let coverGradient = NSGradient(starting: coverTop, ending: coverBot)!
    bookPath.addClip()
    coverGradient.draw(in: bookRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // ---- 4. Spine: wider, with a darker groove between spine and cover.
    let spineW = bookW * 0.16
    let spineRect = NSRect(x: bookX, y: bookY, width: spineW, height: bookH)
    NSGraphicsContext.current?.saveGraphicsState()
    bookPath.addClip()
    let spineTop = NSColor(red: 0.22, green: 0.48, blue: 0.94, alpha: 1.0)
    let spineBot = NSColor(red: 0.07, green: 0.27, blue: 0.70, alpha: 1.0)
    NSGradient(starting: spineTop, ending: spineBot)!.draw(in: spineRect, angle: -90)

    // Groove: a thin dark line separating spine from cover.
    let groove = NSBezierPath()
    groove.move(to: NSPoint(x: bookX + spineW, y: bookY + s * 0.02))
    groove.line(to: NSPoint(x: bookX + spineW, y: bookY + bookH - s * 0.02))
    NSColor.black.withAlphaComponent(0.22).setStroke()
    groove.lineWidth = max(s * 0.006, 0.6)
    groove.stroke()

    // Highlight on the spine's inner edge for a subtle 3D feel.
    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: bookX + spineW + lineWidth, y: bookY + s * 0.025))
    highlight.line(to: NSPoint(x: bookX + spineW + lineWidth, y: bookY + bookH - s * 0.025))
    NSColor(white: 1, alpha: 0.20).setStroke()
    highlight.lineWidth = max(s * 0.005, 0.5)
    highlight.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    // ---- 5. "D" letter: bold blue, centered on the cover area (right of spine).
    let letterAreaX = bookX + spineW
    let letterAreaW = bookW - spineW
    let fontSize = bookH * 0.58
    let letterColor = NSColor(red: 0.11, green: 0.36, blue: 0.84, alpha: 1.0)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: letterColor,
        .kern: 0
    ]
    let letter = NSAttributedString(string: "D", attributes: attrs)
    let letterSize = letter.size()
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
    .appendingPathComponent("QDict")
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
