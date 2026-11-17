// Draws Flick's app icon: three window cards fanned out on a tile, the front one selected.
import AppKit

let output = CommandLine.arguments[1]
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.53, blue: 0.96, alpha: 1),
    ])!.draw(in: tilePath, angle: -60)

    func card(center: NSPoint, angle: CGFloat, alpha: CGFloat, selected: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: angle)
        transform.concat()
        let rect = NSRect(x: -230, y: -165, width: 460, height: 330)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        let body = NSBezierPath(roundedRect: rect, xRadius: 42, yRadius: 42)
        NSColor(white: 1, alpha: alpha).setFill()
        body.fill()
        NSShadow().set()
        // Title bar with the three circles.
        let bar = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.maxY - 70, width: rect.width, height: 70), xRadius: 42, yRadius: 42)
        bar.append(NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - 70, width: rect.width, height: 35)))
        NSColor(white: 0.90, alpha: alpha).setFill()
        bar.fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 34 + CGFloat(i) * 42, y: rect.maxY - 48, width: 26, height: 26)).fill()
        }
        NSColor(white: 0.82, alpha: alpha).setFill()
        for i in 0..<3 {
            let w = rect.width * [0.62, 0.48, 0.55][i]
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 40, y: rect.maxY - 130 - CGFloat(i) * 52, width: w, height: 24), xRadius: 12, yRadius: 12).fill()
        }
        if selected {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -22, dy: -22), xRadius: 60, yRadius: 60)
            ring.lineWidth = 22
            NSColor(calibratedRed: 1, green: 0.80, blue: 0.25, alpha: 1).setStroke()
            ring.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    card(center: NSPoint(x: 420, y: 600), angle: 12, alpha: 0.55, selected: false)
    card(center: NSPoint(x: 470, y: 530), angle: 5, alpha: 0.78, selected: false)
    card(center: NSPoint(x: 545, y: 440), angle: -4, alpha: 1, selected: true)
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
