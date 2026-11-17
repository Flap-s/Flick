import AppKit
import FlickCore

@MainActor
final class StatusItem: NSObject, NSMenuDelegate {
    static let shared = StatusItem()

    private var item: NSStatusItem?
    private var current: MenuBarIcon?

    func install() {
        update(Preferences.shared.config.menuBarIcon)
        NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let status = StatusItem.shared
                status.item?.menu = status.makeMenu()
            }
        }
    }

    static func symbolName(_ icon: MenuBarIcon) -> String {
        switch icon {
        case .stack: "rectangle.stack"
        case .windows: "macwindow.on.rectangle"
        case .arrows: "arrow.left.arrow.right.square"
        case .hidden: "eye.slash"
        }
    }

    func update(_ icon: MenuBarIcon) {
        guard icon != current else { return }
        current = icon
        guard icon != .hidden else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item?.menu = makeMenu()
        }
        let image = NSImage(systemSymbolName: Self.symbolName(icon), accessibilityDescription: "Flick")
        image?.isTemplate = true
        item?.button?.image = image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: tr("Afficher le sélecteur", "Show Switcher"), action: #selector(showSwitcher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Réglages…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: tr("Autorisations…", "Permissions…"), action: #selector(showPermissions), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("Rechercher des mises à jour…", "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("À propos de Flick", "About Flick"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("Quitter Flick", "Quit Flick"), action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func showSwitcher() {
        // Let the menu close first, so the switcher doesn't open over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { SwitcherController.shared.openManually() }
    }

    @objc private func showSettings() { SettingsWindowController.show() }
    @objc private func showPermissions() { PermissionsWindowController.show() }
    @objc private func showAbout() { SettingsWindowController.show(tab: .about) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func checkForUpdates() {
        SettingsWindowController.show(tab: .updates)
        Task { await Updater.shared.check(userInitiated: true) }
    }
}
