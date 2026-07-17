#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-dmg-background.swift <output-png>\n", stderr)
    exit(64)
}

let width = 640
let height = 240
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create background bitmap.\n", stderr)
    exit(70)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.975, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 278, y: 120))
arrow.line(to: NSPoint(x: 362, y: 120))
arrow.move(to: NSPoint(x: 344, y: 102))
arrow.line(to: NSPoint(x: 362, y: 120))
arrow.line(to: NSPoint(x: 344, y: 138))
NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode background PNG.\n", stderr)
    exit(70)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} catch {
    fputs("Could not write background PNG: \(error)\n", stderr)
    exit(74)
}
