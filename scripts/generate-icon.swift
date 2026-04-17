#!/usr/bin/env swift
// Generates AppIcon.icns for WhisperMic
// Usage: swift generate-icon.swift /path/to/output/AppIcon.icns

import Cocoa
import Foundation

func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let s = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.2

    // Blue gradient background
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(starting: NSColor(red: 0.17, green: 0.37, blue: 0.54, alpha: 1.0),
                              ending: NSColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1.0))!
    gradient.draw(in: path, angle: 90)

    // White mic icon
    NSColor.white.setFill()
    NSColor.white.setStroke()

    let cx = s / 2
    let lineWidth = max(1.0, s * 0.05)

    // Mic body (rounded rect)
    let micW = s * 0.22
    let micH = s * 0.35
    let micX = cx - micW / 2
    let micY = s * 0.40
    let micPath = NSBezierPath(roundedRect: NSRect(x: micX, y: micY, width: micW, height: micH),
                                xRadius: micW / 2, yRadius: micW / 2)
    micPath.fill()

    // Arc below mic
    let arcPath = NSBezierPath()
    arcPath.lineWidth = lineWidth
    let arcR = s * 0.18
    let arcCY = s * 0.42
    arcPath.appendArc(withCenter: NSPoint(x: cx, y: arcCY),
                      radius: arcR,
                      startAngle: 0, endAngle: 180)
    arcPath.stroke()

    // Stand line
    let standPath = NSBezierPath()
    standPath.lineWidth = lineWidth
    standPath.move(to: NSPoint(x: cx, y: arcCY - arcR))
    standPath.line(to: NSPoint(x: cx, y: s * 0.15))
    standPath.stroke()

    // Base line
    let basePath = NSBezierPath()
    basePath.lineWidth = lineWidth
    basePath.lineCapStyle = .round
    let bw = s * 0.12
    basePath.move(to: NSPoint(x: cx - bw, y: s * 0.15))
    basePath.line(to: NSPoint(x: cx + bw, y: s * 0.15))
    basePath.stroke()

    img.unlockFocus()
    return img
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

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperMicIcon_\(ProcessInfo.processInfo.processIdentifier)")
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
