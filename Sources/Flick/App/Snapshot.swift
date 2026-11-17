import AppKit
import FlickCore
import SwiftUI

/// `Flick --snapshot <directory>` renders the switcher (with sample windows) and the settings to PNG files, to
/// review the layout without permissions or key presses.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let directory = URL(fileURLWithPath: args[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        KeyboardLayout.shared.refresh()
        // Rendering switches languages; put the user's own choice back afterwards.
        let savedLanguage = Localization.shared.language

        for style in Style.allCases {
            for dark in [false, true] {
                var appearance = Appearance()
                appearance.style = style
                appearance.theme = dark ? .dark : .light
                renderSwitcher(appearance: appearance, searching: style == .titles,
                               to: directory.appendingPathComponent("switcher-\(style.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
        for language in [AppLanguage.french, .english] {
            Localization.shared.language = language
            let suffix = language == .french ? "fr" : "en"
            for tab in SettingsTab.allCases {
                SettingsNavigation.shared.tab = tab
                render(SettingsView().frame(width: 880, height: 620), to: directory.appendingPathComponent("settings-\(suffix)-\(tab.rawValue).png"))
            }
        }
        for language in [AppLanguage.french, .english] {
            Localization.shared.language = language
            render(OnboardingView(), size: CGSize(width: 560, height: 640),
                   to: directory.appendingPathComponent("onboarding-\(language == .french ? "fr" : "en").png"))
        }
        Localization.shared.language = savedLanguage
        exit(0)
    }

    private static var samples: [(app: String, title: String, color: NSColor, ratio: CGFloat)] { [
        ("/System/Applications/Mail.app", tr("Boîte de réception — 3 non lus", "Inbox — 3 unread"), .systemBlue, 1.6),
        ("/Applications/Safari.app", tr("Documentation Swift", "Swift Documentation"), .systemTeal, 1.5),
        ("/System/Library/CoreServices/Finder.app", tr("Téléchargements", "Downloads"), .systemGray, 1.3),
        ("/System/Applications/Notes.app", tr("Liste de courses", "Shopping list"), .systemYellow, 0.8),
        ("/System/Applications/Calendar.app", tr("Octobre 2026", "October 2026"), .systemRed, 1.7),
        ("/System/Applications/Music.app", tr("Musique", "Music"), .systemPink, 1.6),
        ("/System/Applications/Utilities/Terminal.app", "zsh — 120×40", .darkGray, 1.4),
        ("/System/Applications/Messages.app", "Messages", .systemGreen, 1.2),
    ] }

    private static func sampleImage(_ color: NSColor, ratio: CGFloat, title: String) -> CGImage? {
        let size = NSSize(width: 480 * ratio, height: 480)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.97, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
            color.withAlphaComponent(0.85).setFill()
            NSBezierPath(rect: CGRect(x: 0, y: rect.height - 56, width: rect.width, height: 56)).fill()
            NSColor(white: 0.85, alpha: 1).setFill()
            for i in 0..<6 {
                NSBezierPath(roundedRect: CGRect(x: 40, y: rect.height - 110 - CGFloat(i) * 52, width: rect.width * (0.5 + 0.07 * CGFloat(i % 3)), height: 22),
                             xRadius: 8, yRadius: 8).fill()
            }
            (title as NSString).draw(at: CGPoint(x: 24, y: rect.height - 40), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white,
            ])
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func renderSwitcher(appearance: Appearance, searching: Bool, to url: URL) {
        let panel = SwitcherPanel()
        var items: [ItemModel] = []
        for (i, s) in samples.enumerated() {
            var model = ItemModel(key: "w\(i)", title: s.title, icon: NSWorkspace.shared.icon(forFile: s.app))
            model.thumbnail = i == 3 ? nil : sampleImage(s.color, ratio: s.ratio, title: s.title)
            model.isMinimized = i == 3
            model.spaceNumber = i % 3 + 1
            model.isFullscreen = i == 4
            model.badge = i == 0 ? "3" : nil
            model.hasWindowControls = true
            items.append(model)
        }
        var windowless = ItemModel(key: "a", title: tr("Calculette", "Calculator"), icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Calculator.app"))
        windowless.isWindowless = true
        items.append(windowless)
        WindowTrackerSpacesInfo.hasSeveralSpaces = true
        let screen = NSScreen.main ?? NSScreen.screens[0]
        panel.show(SwitcherPanel.Content(items: items, aspectRatios: samples.map(\.ratio) + [0], selected: 1, searching: searching,
                                         query: searching ? tr("mes", "doc") : "", hint: searching ? nil : tr("⌥S pour rechercher", "⌥S to search")),
                   appearance: appearance, mouseHover: true, on: screen)
        guard let view = panel.contentView else { return }
        // Layers only exist once the panel is on screen: show it far off any display for a moment.
        panel.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        panel.orderFrontRegardless()
        panel.display()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let size = view.bounds.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        // The blur doesn't render offscreen: stand in with a flat backdrop.
        cg.setFillColor(appearance.theme == .dark ? NSColor(white: 0.16, alpha: 1).cgColor : NSColor(white: 0.93, alpha: 1).cgColor)
        cg.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 18, cornerHeight: 18, transform: nil))
        cg.fillPath()
        (panel.appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
            view.layer?.render(in: cg)
        }
        panel.orderOut(nil)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render<V: View>(_ view: V, size: CGSize = CGSize(width: 880, height: 620), to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
