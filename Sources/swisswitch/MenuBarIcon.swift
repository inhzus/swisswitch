import AppKit

/// The menu-bar glyph: a toggle switch outline whose knob carries a knocked-out
/// cross, matching the app icon. A template image, so macOS tints it.
enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let track = NSRect(x: 1.5, y: 3.5, width: 19, height: 9)
            let outline = NSBezierPath(roundedRect: track, xRadius: 4.5, yRadius: 4.5)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            outline.stroke()

            // Knob at the "on" end, with the cross cut out (even-odd fill).
            let center = NSPoint(x: track.maxX - 4.5, y: track.midY)
            let radius = 3.25
            let knob = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
            let l = 1.9, w = 0.65
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: center.x - w, y: center.y + l))
            for (dx, dy) in [(w, l), (w, w), (l, w), (l, -w), (w, -w), (w, -l),
                             (-w, -l), (-w, -w), (-l, -w), (-l, w), (-w, w)] {
                cross.line(to: NSPoint(x: center.x + dx, y: center.y + dy))
            }
            cross.close()
            knob.append(cross)
            knob.windingRule = .evenOdd
            NSColor.black.setFill()
            knob.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "swisswitch"
        return image
    }
}
