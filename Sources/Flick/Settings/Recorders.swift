import AppKit
import FlickCore
import SwiftUI

/// Records the modifiers to hold (⌥, ⌘⇧…): press them together, then release.
struct ModifierRecorder: NSViewRepresentable {
    @Binding var modifiers: Modifiers

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.mode = .modifiers
        return field
    }

    func updateNSView(_ field: RecorderField, context: Context) {
        field.display = modifiers.symbols.isEmpty ? tr("Aucune", "None") : modifiers.symbols
        field.onModifiers = { modifiers = $0 }
    }
}

/// Records one key. `allowsClear` lets ⌫ unassign it.
struct KeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt16?
    var allowsClear = true

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.mode = .key
        return field
    }

    func updateNSView(_ field: RecorderField, context: Context) {
        field.display = MainActor.assumeIsolated { keyCode.map(KeyNames.name) } ?? tr("Aucune", "None")
        field.allowsClear = allowsClear
        field.onKey = { keyCode = $0 }
    }
}

final class RecorderField: NSView {
    enum Mode { case modifiers, key }

    var mode: Mode = .key
    var display = "" { didSet { needsDisplay = true } }
    var allowsClear = true
    var onModifiers: ((Modifiers) -> Void)?
    var onKey: ((UInt16?) -> Void)?
    private var peak: Modifiers = []
    private var recording = false {
        didSet {
            needsDisplay = true
            EventTap.shared.setSuspended(recording)
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        peak = []
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        switch mode {
        case .modifiers:
            if event.keyCode == KeyCode.escape { recording = false }
        case .key:
            if event.keyCode == KeyCode.escape && !event.modifierFlags.contains(.shift) {
                recording = false
            } else if (event.keyCode == KeyCode.delete || event.keyCode == KeyCode.forwardDelete) && allowsClear {
                onKey?(nil)
                recording = false
            } else {
                onKey?(event.keyCode)
                recording = false
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording, mode == .modifiers else { return super.flagsChanged(with: event) }
        let now = MainActor.assumeIsolated { KeyNames.modifiers(event.modifierFlags) }
        if now.isEmpty {
            if !peak.isEmpty {
                onModifiers?(peak)
                recording = false
            }
        } else {
            peak.formUnion(now)
            display = peak.symbols
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text: String
        if recording {
            text = mode == .modifiers ? (peak.isEmpty ? tr("Touches…", "Keys…") : peak.symbols) : tr("Touche…", "Key…")
        } else {
            text = display
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
