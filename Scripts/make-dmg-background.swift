// Draws the background of Flick's disk image window: the app and the Applications folder on two frosted
// pedestals, joined by a curved arrow, with the instruction in French and English. Written at 2× (144 dpi) so it
// stays sharp on Retina screens. Finder places the icons at x = 170 and x = 470, 200 points from the top.
import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 640, height: 400)
let scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let indigo = color(94, 84, 242)
let blue = color(34, 140, 245)
// Finder draws the icon labels in dark text in light mode: the background stays light everywhere a label sits.
let ink = color(28, 30, 48)

// Base: a pale wash, with soft coloured glows for depth.
NSGradient(colors: [color(250, 250, 255), color(236, 240, 252)])!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
func glow(at point: NSPoint, radius: CGFloat, _ tint: NSColor) {
    NSGradient(colors: [tint, tint.withAlphaComponent(0)])!
        .draw(fromCenter: point, radius: 0, toCenter: point, radius: radius, options: [])
}
glow(at: NSPoint(x: 70, y: 380), radius: 300, indigo.withAlphaComponent(0.16))
glow(at: NSPoint(x: 600, y: 30), radius: 320, blue.withAlphaComponent(0.14))
glow(at: NSPoint(x: 320, y: 200), radius: 220, NSColor.white.withAlphaComponent(0.55))

func text(_ string: String, centerX: CGFloat = 320, y: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let s = NSAttributedString(string: string, attributes: attributes)
    let w = s.size().width
    s.draw(at: NSPoint(x: (centerX - w / 2).rounded(), y: y))
}

// Heading.
text("FLICK", y: 352, font: .systemFont(ofSize: 11, weight: .bold), color: indigo, kern: 3)
text("Glissez Flick dans Applications", y: 316, font: .systemFont(ofSize: 25, weight: .bold), color: ink, kern: -0.3)
text("Drag Flick to the Applications folder", y: 294, font: .systemFont(ofSize: 13, weight: .medium),
     color: ink.withAlphaComponent(0.5))

// Frosted pedestals under each icon and its label.
func pedestal(centerX: CGFloat) {
    let rect = NSRect(x: centerX - 82, y: 88, width: 164, height: 182)
    let path = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(40, 50, 120, 0.13)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.white.withAlphaComponent(0.72).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.9), NSColor.white.withAlphaComponent(0.35)])!.draw(in: path, angle: -90)
    path.lineWidth = 1
    NSColor.white.setStroke()
    path.stroke()
}
pedestal(centerX: 170)
pedestal(centerX: 470)

// Curved arrow, from the app towards the folder.
let arrowY: CGFloat = 200
let start = NSPoint(x: 266, y: arrowY - 2)
let end = NSPoint(x: 368, y: arrowY - 2)
let curve = CGMutablePath()
curve.move(to: start)
curve.addQuadCurve(to: end, control: CGPoint(x: 317, y: arrowY + 34))
cg.saveGState()
cg.addPath(curve)
cg.setLineWidth(5)
cg.setLineCap(.round)
cg.replacePathWithStrokedPath()
cg.clip()
let arrowGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [indigo.cgColor, blue.cgColor] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(arrowGradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
cg.restoreGState()
// Head, aligned with the curve's end tangent (pointing down-right).
let angle = atan2(end.y - (arrowY + 34), end.x - 317)
let headLength: CGFloat = 17, headWidth: CGFloat = 11
let tip = NSPoint(x: end.x + cos(angle) * 9, y: end.y + sin(angle) * 9)
let back = NSPoint(x: tip.x - cos(angle) * headLength, y: tip.y - sin(angle) * headLength)
let head = NSBezierPath()
head.move(to: tip)
head.line(to: NSPoint(x: back.x - sin(angle) * headWidth, y: back.y + cos(angle) * headWidth))
head.line(to: NSPoint(x: back.x + sin(angle) * headWidth, y: back.y - cos(angle) * headWidth))
head.close()
head.lineJoinStyle = .round
blue.setFill()
blue.setStroke()
head.lineWidth = 3
head.fill()
head.stroke()

// Footer: what to do next, with the shortcut as keycaps.
func keycap(_ label: String, x: CGFloat, y: CGFloat) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.75)]
    let s = NSAttributedString(string: label, attributes: attributes)
    let w = max(24, s.size().width + 14)
    let rect = NSRect(x: x, y: y, width: w, height: 22)
    let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(40, 50, 120, 0.18)
    shadow.shadowBlurRadius = 0
    shadow.shadowOffset = NSSize(width: 0, height: -1.5)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(200, 205, 225).setStroke()
    path.lineWidth = 0.5
    path.stroke()
    s.draw(at: NSPoint(x: x + (w - s.size().width) / 2, y: y + (22 - s.size().height) / 2))
    return w
}
let footerFont = NSFont.systemFont(ofSize: 12, weight: .medium)
let footerColor = ink.withAlphaComponent(0.55)
let before = NSAttributedString(string: "Ensuite, maintenez", attributes: [.font: footerFont, .foregroundColor: footerColor])
let middle = NSAttributedString(string: "et appuyez sur", attributes: [.font: footerFont, .foregroundColor: footerColor])
let capWidth: CGFloat = 26
let totalWidth = before.size().width + middle.size().width + capWidth * 2 + 8 * 4
var x = (size.width - totalWidth) / 2
let footerY: CGFloat = 38
before.draw(at: NSPoint(x: x, y: footerY + 3)); x += before.size().width + 8
x += keycap("⌥", x: x, y: footerY) + 8
middle.draw(at: NSPoint(x: x, y: footerY + 3)); x += middle.size().width + 8
_ = keycap("⇥", x: x, y: footerY)
text("Then hold ⌥ and press ⇥ to switch windows", y: 18, font: .systemFont(ofSize: 11), color: ink.withAlphaComponent(0.4))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
