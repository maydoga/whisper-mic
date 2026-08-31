#!/usr/bin/env swift
// Generates AppIcon.icns for Hulpje
// Usage: swift generate-icon.swift /path/to/output/AppIcon.icns

import Cocoa
import Foundation

/// A raised hand on an indigo field. Legible down to 16pt, which rules out anything
/// with thin strokes or interior detail.
func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let s = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(starting: NSColor(red: 0.24, green: 0.20, blue: 0.52, alpha: 1.0),
                              ending: NSColor(red: 0.48, green: 0.36, blue: 0.86, alpha: 1.0))!
    gradient.draw(in: path, angle: 90)

    if let glyph = symbolImage(named: "hand.raised.fill", pointSize: s * 0.52) {
        let box = NSRect(
            x: (s - glyph.size.width) / 2,
            y: (s - glyph.size.height) / 2,
            width: glyph.size.width,
            height: glyph.size.height
        )
        glyph.draw(in: box)
    }

    img.unlockFocus()
    return img
}

/// SF Symbols ship as templates; drawing the shape and filling `.sourceAtop` paints it.
func symbolImage(named name: String, pointSize: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }

    let out = NSImage(size: symbol.size)
    out.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
}

// Main
let outputPath: String
if CommandLine.arguments.count > 1 {
    outputPath = CommandLine.arguments[1]
} else {
    outputPath = "AppIcon.icns"
}

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HulpjeIcon_\(ProcessInfo.processInfo.processIdentifier)")
let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in iconSizes {
    let img = generateIcon(size: size)
    let path = iconsetDir.appendingPathComponent(name).path
    savePNG(img, to: path)
}

// Run iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputPath]
try? process.run()
process.waitUntilExit()

// Cleanup
try? FileManager.default.removeItem(at: tempDir)

if process.terminationStatus == 0 {
    print("Created \(outputPath)")
} else {
    print("Failed to create icns")
    exit(1)
}
