#!/usr/bin/env swift
// Draws the swisswitch app icon: a white toggle switch on a Swiss-red squircle,
// its knob a red disc with a white Swiss cross. Writes Resources/AppIcon.icns and docs/icon.png.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let red = CGColor(srgbRed: 0.89, green: 0.08, blue: 0.12, alpha: 1)

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A Swiss-style cross centered at `c`: arms `length` long, `width` thick.
func cross(center c: CGPoint, length: CGFloat, width: CGFloat) -> CGPath {
    let l = length / 2, w = width / 2
    let path = CGMutablePath()
    path.addLines(between: [
        CGPoint(x: c.x - w, y: c.y + l), CGPoint(x: c.x + w, y: c.y + l),
        CGPoint(x: c.x + w, y: c.y + w), CGPoint(x: c.x + l, y: c.y + w),
        CGPoint(x: c.x + l, y: c.y - w), CGPoint(x: c.x + w, y: c.y - w),
        CGPoint(x: c.x + w, y: c.y - l), CGPoint(x: c.x - w, y: c.y - l),
        CGPoint(x: c.x - w, y: c.y - w), CGPoint(x: c.x - l, y: c.y - w),
        CGPoint(x: c.x - l, y: c.y + w), CGPoint(x: c.x - w, y: c.y + w),
    ])
    path.closeSubpath()
    return path
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// Draws the icon in a 1024×1024 coordinate space (origin bottom-left).
func drawIcon(_ ctx: CGContext) {
    // Squircle body with drop shadow (macOS icon grid: 824pt inset 100pt).
    let body = roundedRect(CGRect(x: 100, y: 100, width: 824, height: 824), 186)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(body)
    ctx.setFillColor(red)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([CGColor(srgbRed: 1, green: 0.33, blue: 0.27, alpha: 1),
                  CGColor(srgbRed: 0.82, green: 0.05, blue: 0.10, alpha: 1)]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Faint top highlight.
    ctx.drawLinearGradient(
        gradient([CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Toggle track, slightly recessed.
    let trackRect = CGRect(x: 202, y: 357, width: 620, height: 310)
    let track = roundedRect(trackRect, trackRect.height / 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: CGColor(gray: 0, alpha: 0.18))
    ctx.addPath(track)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(track)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([CGColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1), CGColor(gray: 1, alpha: 1)]),
        start: CGPoint(x: 512, y: trackRect.maxY), end: CGPoint(x: 512, y: trackRect.minY), options: [])
    // Inner shadow along the top edge.
    let ring = CGMutablePath()
    ring.addRect(trackRect.insetBy(dx: -80, dy: -80))
    ring.addPath(track)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(ring)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // Knob at the "on" end, raised, with the cross.
    let knobCenter = CGPoint(x: trackRect.maxX - trackRect.height / 2, y: trackRect.midY)
    let knobRadius: CGFloat = 128
    let knob = CGPath(ellipseIn: CGRect(x: knobCenter.x - knobRadius, y: knobCenter.y - knobRadius,
                                        width: knobRadius * 2, height: knobRadius * 2), transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.30))
    ctx.addPath(knob)
    ctx.setFillColor(red)
    ctx.fillPath()
    ctx.restoreGState()

    // Red knob, white cross: the Swiss flag (red-on-white would be the Red Cross emblem).
    ctx.saveGState()
    ctx.addPath(knob)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([CGColor(srgbRed: 1, green: 0.30, blue: 0.25, alpha: 1),
                  CGColor(srgbRed: 0.80, green: 0.04, blue: 0.09, alpha: 1)]),
        start: CGPoint(x: knobCenter.x, y: knobCenter.y + knobRadius),
        end: CGPoint(x: knobCenter.x, y: knobCenter.y - knobRadius), options: [])
    ctx.restoreGState()

    ctx.addPath(cross(center: knobCenter, length: 140, width: 44))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
try fm.createDirectory(at: URL(fileURLWithPath: "Resources"), withIntermediateDirectories: true)
try fm.createDirectory(at: URL(fileURLWithPath: "docs"), withIntermediateDirectories: true)
try png(pixels: 512).write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns and docs/icon.png")
