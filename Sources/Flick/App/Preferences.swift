import AppKit
import Combine
import FlickCore
import UniformTypeIdentifiers

/// The user's settings, saved to UserDefaults as JSON and applied live.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private static let key = "config"

    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            save()
            apply()
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), var saved = try? JSONDecoder().decode(Config.self, from: data) {
            // 1.0.0 captured in the background by default, which kept macOS's capture notice on screen.
            if !UserDefaults.standard.bool(forKey: "migratedBackgroundCapture") {
                UserDefaults.standard.set(true, forKey: "migratedBackgroundCapture")
                saved.appearance.backgroundCapture = false
            }
            config = saved
            save()
        } else {
            UserDefaults.standard.set(true, forKey: "migratedBackgroundCapture")
            config = Self.defaults()
        }
    }

    /// Defaults adapted to the keyboard layout: control keys follow the letters they are named after.
    static func defaults() -> Config {
        var config = Config()
        let letters: [ControlAction: Character] = [.closeWindow: "w", .minimizeWindow: "m", .fullscreenWindow: "f", .quitApp: "q",
                                                   .hideApp: "h", .search: "s"]
        for (action, letter) in letters {
            if let code = KeyNames.keyCode(typing: letter) { config.controls[action] = code }
        }
        return config
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    func apply() {
        EventTap.shared.apply(config)
        StatusItem.shared.update(config.menuBarIcon)
        Thumbnails.shared.setBackgroundCapture(config.appearance.backgroundCapture)
        AppDelegate.updateIgnoredShortcuts()
    }

    func reset() {
        config = Self.defaults()
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = tr("Réglages Flick.json", "Flick Settings.json")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(config).write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("Impossible d’importer les réglages", "Couldn’t import the settings")
            alert.informativeText = tr("Le fichier n’est pas un export de Flick valide.", "The file isn’t a valid Flick export.")
            alert.runModal()
        }
    }
}
