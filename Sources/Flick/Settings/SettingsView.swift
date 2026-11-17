import AppKit
import Combine
import FlickCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?
    private var observers: [AnyCancellable] = []

    static func show(tab: SettingsTab? = nil) {
        if let tab { SettingsNavigation.shared.tab = tab }
        NSApp.activate()
        if let shared {
            shared.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SettingsWindowController()
        shared = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "FlickSettings")
        window.toolbarStyle = .unified
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.setContentSize(NSSize(width: 880, height: 620))
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.center()
        window.setFrameAutosaveName("FlickSettingsSidebar")
        super.init(window: window)
        window.delegate = self
        // The window title follows the selected pane and the language.
        observers.append(SettingsNavigation.shared.$tab.sink { [weak window] tab in window?.title = tab.title })
        observers.append(NotificationCenter.default.publisher(for: Localization.didChange).sink { [weak window] _ in
            window?.title = SettingsNavigation.shared.tab.title
        })
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        EventTap.shared.setSuspended(false)
        Self.shared = nil
    }
}

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general, windows, shortcuts, controls, appearance, exceptions, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: tr("Général", "General")
        case .windows: tr("Fenêtres", "Windows")
        case .shortcuts: tr("Raccourcis", "Shortcuts")
        case .controls: tr("Commandes", "Controls")
        case .appearance: tr("Apparence", "Appearance")
        case .exceptions: tr("Exceptions", "Exceptions")
        case .updates: tr("Mises à jour", "Updates")
        case .about: tr("À propos", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .windows: "macwindow.on.rectangle"
        case .shortcuts: "command"
        case .controls: "keyboard.fill"
        case .appearance: "paintpalette.fill"
        case .exceptions: "hand.raised.fill"
        case .updates: "arrow.down.circle.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .windows: .blue
        case .shortcuts: .indigo
        case .controls: .teal
        case .appearance: .pink
        case .exceptions: .orange
        case .updates: .green
        case .about: .secondary
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .general
}

/// System Settings–style window: categories in a sidebar, the selected one on the right.
struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsTab?>(get: { navigation.tab }, set: { if let tab = $0 { navigation.tab = tab } })) {
                ForEach(SettingsTab.allCases) { tab in
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tab.tint.gradient))
                    }
                    .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            pane(navigation.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        // Rebuild every text when the language changes.
        .id(localization.language)
    }

    @ViewBuilder private func pane(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .windows: WindowFilterSettings()
        case .shortcuts: ShortcutSettings()
        case .controls: ControlSettings()
        case .appearance: AppearanceSettings()
        case .exceptions: ExceptionSettings()
        case .updates: UpdateSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: Pickers

struct EnumPicker<T: Labeled>: View {
    let title: String
    @Binding var value: T

    init(_ title: String, _ value: Binding<T>) {
        self.title = title
        _value = value
    }

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(Array(T.allCases), id: \.self) { Text($0.label).tag($0) }
        }
    }
}

/// A shortcut's own value, or the global one.
struct OverridePicker<T: Labeled>: View {
    let title: String
    @Binding var value: T?
    let global: T

    init(_ title: String, _ value: Binding<T?>, global: T) {
        self.title = title
        _value = value
        self.global = global
    }

    var body: some View {
        Picker(title, selection: $value) {
            Text(tr("Réglage global (\(global.label))", "Global setting (\(global.label))")).tag(T?.none)
            Divider()
            ForEach(Array(T.allCases), id: \.self) { Text($0.label).tag(T?.some($0)) }
        }
    }
}

struct BoolOverridePicker: View {
    let title: String
    @Binding var value: Bool?
    let global: Bool

    var body: some View {
        Picker(title, selection: $value) {
            Text(tr("Réglage global (\(global ? "oui" : "non"))", "Global setting (\(global ? "yes" : "no"))")).tag(Bool?.none)
            Divider()
            Text(tr("Oui", "Yes")).tag(Bool?.some(true))
            Text(tr("Non", "No")).tag(Bool?.some(false))
        }
    }
}

struct FiltersEditor: View {
    @Binding var filters: Filters

    var body: some View {
        EnumPicker(tr("Fenêtres des apps", "Windows from apps"), $filters.apps)
        EnumPicker(tr("Fenêtres des Spaces", "Windows from Spaces"), $filters.spaces)
        EnumPicker(tr("Fenêtres des écrans", "Windows from screens"), $filters.screens)
        EnumPicker(tr("Fenêtres réduites", "Minimized windows"), $filters.minimized)
        EnumPicker(tr("Fenêtres des apps masquées", "Windows of hidden apps"), $filters.hidden)
        EnumPicker(tr("Fenêtres en plein écran", "Full-screen windows"), $filters.fullscreen)
        EnumPicker(tr("Apps sans fenêtre ouverte", "Apps with no open window"), $filters.windowless)
        EnumPicker(tr("Trier les fenêtres", "Sort windows"), $filters.order)
        Toggle(tr("Une seule fenêtre par app", "One window per app"), isOn: $filters.oneWindowPerApp)
        Toggle(tr("Une entrée par onglet (fenêtres à onglets)", "One entry per tab (tabbed windows)"), isOn: $filters.separateTabs)
    }
}

struct OverridesEditor: View {
    @Binding var overrides: FilterOverrides
    let global: Filters

    var body: some View {
        OverridePicker(tr("Fenêtres des apps", "Windows from apps"), $overrides.apps, global: global.apps)
        OverridePicker(tr("Fenêtres des Spaces", "Windows from Spaces"), $overrides.spaces, global: global.spaces)
        OverridePicker(tr("Fenêtres des écrans", "Windows from screens"), $overrides.screens, global: global.screens)
        OverridePicker(tr("Fenêtres réduites", "Minimized windows"), $overrides.minimized, global: global.minimized)
        OverridePicker(tr("Fenêtres des apps masquées", "Windows of hidden apps"), $overrides.hidden, global: global.hidden)
        OverridePicker(tr("Fenêtres en plein écran", "Full-screen windows"), $overrides.fullscreen, global: global.fullscreen)
        OverridePicker(tr("Apps sans fenêtre ouverte", "Apps with no open window"), $overrides.windowless, global: global.windowless)
        OverridePicker(tr("Trier les fenêtres", "Sort windows"), $overrides.order, global: global.order)
        BoolOverridePicker(title: tr("Une seule fenêtre par app", "One window per app"), value: $overrides.oneWindowPerApp, global: global.oneWindowPerApp)
        BoolOverridePicker(title: tr("Une entrée par onglet", "One entry per tab"), value: $overrides.separateTabs, global: global.separateTabs)
        if !overrides.isEmpty {
            Button(tr("Tout remettre aux réglages globaux", "Reset all to global settings")) { overrides = FilterOverrides() }
        }
    }
}

// MARK: General

private struct GeneralSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var localization = Localization.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle(tr("Ouvrir Flick à l’ouverture de session", "Open Flick at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in LaunchAtLogin.set(value) }
                Picker(tr("Langue", "Language"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text(localization.label($0)).tag($0) }
                }
                Picker(tr("Icône de la barre des menus", "Menu bar icon"), selection: $prefs.config.menuBarIcon) {
                    ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                        Label(icon.label, systemImage: StatusItem.symbolName(icon)).tag(icon)
                    }
                }
                if prefs.config.menuBarIcon == .hidden {
                    Text(tr("Pour revenir aux réglages, ouvrez Flick à nouveau depuis le Finder ou Spotlight.",
                            "To come back to the settings, open Flick again from the Finder or Spotlight."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(tr("Réglages", "Settings")) {
                HStack {
                    Button(tr("Exporter…", "Export…")) { prefs.exportSettings() }
                    Button(tr("Importer…", "Import…")) { prefs.importSettings() }
                    Spacer()
                    Button(tr("Réinitialiser…", "Reset…"), role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(tr("Réinitialiser tous les réglages de Flick ?", "Reset all of Flick’s settings?"), isPresented: $confirmReset) {
            Button(tr("Réinitialiser", "Reset"), role: .destructive) { prefs.reset() }
        } message: {
            Text(tr("Raccourcis, apparence et exceptions reviennent à leurs valeurs d’origine. Cette action est irréversible.",
                    "Shortcuts, appearance and exceptions go back to their original values. This can’t be undone."))
        }
    }
}

// MARK: Listed windows

private struct WindowFilterSettings: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                FiltersEditor(filters: $prefs.config.filters)
            } header: {
                Text(tr("Fenêtres listées par défaut", "Windows listed by default"))
            } footer: {
                Text(tr("Chaque raccourci peut remplacer ces réglages dans Raccourcis.",
                        "Each shortcut can override these settings in Shortcuts."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Shortcuts

private struct ShortcutSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var selection = 0

    var body: some View {
        Form {
            Section {
                HStack {
                    Picker(tr("Raccourci", "Shortcut"), selection: $selection) {
                        ForEach(prefs.config.shortcuts.indices, id: \.self) { index in
                            let s = prefs.config.shortcuts[index]
                            Text(verbatim: "\(index + 1) · \(KeyNames.describe(hold: s.hold, keyCode: s.keyCode))").tag(index)
                        }
                    }
                    Button { add() } label: { Image(systemName: "plus") }
                        .disabled(prefs.config.shortcuts.count >= Config.maxShortcuts)
                        .help(tr("Ajouter un raccourci (jusqu’à \(Config.maxShortcuts))", "Add a shortcut (up to \(Config.maxShortcuts))"))
                    Button { remove() } label: { Image(systemName: "minus") }
                        .disabled(prefs.config.shortcuts.count <= 1)
                        .help(tr("Supprimer ce raccourci", "Remove this shortcut"))
                }
            } footer: {
                Text(tr("Chaque raccourci peut montrer un groupe de fenêtres différent : toutes, celles de l’app active, d’un Space…", "Each shortcut can show a different group of windows: all of them, the active app’s, one Space’s…"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if prefs.config.shortcuts.indices.contains(selection) {
                let binding = $prefs.config.shortcuts[selection]
                Section(tr("Déclenchement", "Trigger")) {
                    HStack {
                        Text(tr("Maintenir", "Hold"))
                        Spacer()
                        HStack {
                            ModifierRecorder(modifiers: binding.hold).frame(width: 96, height: 24)
                            Text(tr("et appuyer sur", "and press"))
                            KeyRecorder(keyCode: Binding(get: { binding.wrappedValue.keyCode },
                                                         set: { if let code = $0 { binding.wrappedValue.keyCode = code } }),
                                        allowsClear: false)
                                .frame(width: 96, height: 24)
                        }
                    }
                    EnumPicker(tr("Au relâchement des touches", "When keys are released"), binding.releaseAction)
                    if let other = prefs.config.shortcutConflict(hold: binding.wrappedValue.hold, keyCode: binding.wrappedValue.keyCode, excluding: selection) {
                        Label(tr("Le raccourci \(other + 1) utilise déjà cette combinaison.", "Shortcut \(other + 1) already uses this combination."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if binding.wrappedValue.hold == .command && binding.wrappedValue.keyCode == KeyCode.tab {
                        Text(tr("⌘⇥ remplace le sélecteur d’apps de macOS tant que Flick est ouvert.", "⌘⇥ replaces the macOS app switcher while Flick is running."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(tr("Fenêtres listées", "Listed windows")) {
                    OverridesEditor(overrides: binding.overrides, global: prefs.config.filters)
                }
            }

            Section(tr("Geste du trackpad", "Trackpad gesture")) {
                EnumPicker(tr("Geste", "Gesture"), $prefs.config.gesture.kind)
                if prefs.config.gesture.kind != .none {
                    Toggle(tr("Retour haptique", "Haptic feedback"), isOn: $prefs.config.gesture.haptics)
                    OverridesEditor(overrides: $prefs.config.gesture.overrides, global: prefs.config.filters)
                    HStack {
                        Text(tr("Désactivez le geste équivalent de macOS s’il entre en conflit.", "Turn off the matching macOS gesture if they conflict."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(tr("Réglages du trackpad…", "Trackpad Settings…")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.config.shortcuts.count) { _, count in selection = min(selection, count - 1) }
    }

    private func add() {
        // A free combination: ⌥ with the next free digit.
        let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let code = digits.first { d in !prefs.config.shortcuts.contains { $0.hold == .option && $0.keyCode == d } } ?? KeyCode.tab
        prefs.config.shortcuts.append(Shortcut(hold: .option, keyCode: code))
        selection = prefs.config.shortcuts.count - 1
    }

    private func remove() {
        guard prefs.config.shortcuts.count > 1, prefs.config.shortcuts.indices.contains(selection) else { return }
        prefs.config.shortcuts.remove(at: selection)
        selection = max(0, selection - 1)
    }
}

// MARK: Controls

private struct ControlSettings: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                ForEach(ControlAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.label)
                        Spacer()
                        KeyRecorder(keyCode: Binding(get: { prefs.config.controls[action] },
                                                     set: { prefs.config.controls[action] = $0 }))
                            .frame(width: 96, height: 24)
                    }
                }
                Picker(tr("Sélectionner la fenêtre précédente", "Select previous window"), selection: $prefs.config.previousModifier) {
                    Text(tr("⇧ Maj", "⇧ Shift")).tag(Modifiers.shift)
                    Text(tr("⌃ Contrôle", "⌃ Control")).tag(Modifiers.control)
                    Text(tr("⌘ Commande", "⌘ Command")).tag(Modifiers.command)
                    Text("⌥ Option").tag(Modifiers.option)
                }
            } header: {
                Text(tr("Touches actives quand le sélecteur est ouvert", "Keys while the switcher is open"))
            } footer: {
                Text(tr("Appuyez sur ces touches en maintenant celles du raccourci. ↩ active aussi la fenêtre ; ⌫ dans un champ retire la touche.", "Press these keys while holding the shortcut’s modifiers. ↩ also focuses the window; ⌫ in a field clears the key."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Navigation") {
                Toggle(tr("Sélectionner avec les flèches", "Select with arrow keys"), isOn: $prefs.config.arrowKeys)
                Toggle(tr("Sélectionner avec les touches vim (H J K L)", "Select with vim keys (H J K L)"), isOn: $prefs.config.vimKeys)
                let shadowed = prefs.config.controlsShadowedByVim
                if !shadowed.isEmpty {
                    Label(tr("Les touches vim remplacent : ", "Vim keys replace: ") + shadowed.map(\.label).joined(separator: ", ") + ".", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle(tr("Sélectionner au survol de la souris", "Select on mouse hover"), isOn: $prefs.config.mouseHover)
                Toggle(tr("Le pointeur suit la fenêtre activée", "Pointer follows the focused window"), isOn: $prefs.config.cursorFollowsFocus)
                Toggle(tr("Afficher l’astuce de recherche", "Show the search hint"), isOn: $prefs.config.showSearchHint)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let a = $prefs.config.appearance
        Form {
            Section("Style") {
                Picker("Style", selection: a.style) {
                    ForEach(Style.allCases, id: \.self) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                EnumPicker(tr("Taille", "Size"), a.size)
                EnumPicker(tr("Thème", "Theme"), a.theme)
                EnumPicker(tr("Afficher sur", "Show on"), a.showOn)
                if prefs.config.appearance.style != .titles { EnumPicker(tr("Alignement", "Alignment"), a.alignment) }
            }
            Section(tr("Titres", "Titles")) {
                if prefs.config.appearance.style == .appIcons { Toggle(tr("Afficher les titres", "Show titles"), isOn: a.showTitles) }
                EnumPicker(tr("Titre affiché", "Title shown"), a.titleSource)
                EnumPicker(tr("Couper les titres trop longs", "Truncate long titles"), a.truncation)
            }
            Section(tr("Éléments", "Elements")) {
                Toggle(tr("Aperçu de la fenêtre sélectionnée à sa place", "Preview the selected window in place"), isOn: a.previewSelectedWindow)
                Toggle(tr("Pastilles rouges des apps (Dock)", "App badges (Dock)"), isOn: a.showBadges)
                Toggle(tr("Masquer les icônes d’état (réduite, masquée, plein écran)", "Hide status icons (minimized, hidden, full screen)"), isOn: a.hideStatusIcons)
                Toggle(tr("Masquer les numéros de Space", "Hide Space numbers"), isOn: a.hideSpaceLabels)
                Toggle(tr("Masquer les boutons de fenêtre au survol", "Hide window buttons on hover"), isOn: a.hideWindowControls)
            }
            Section(tr("Animations et miniatures", "Animations and thumbnails")) {
                LabeledContent(tr("Délai d’apparition", "Appearance delay")) {
                    HStack {
                        Slider(value: Binding(get: { Double(prefs.config.appearance.apparitionDelay) },
                                              set: { prefs.config.appearance.apparitionDelay = Int($0) }), in: 0...1000, step: 25)
                        Text(verbatim: "\(prefs.config.appearance.apparitionDelay) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                }
                Toggle(tr("Fondu à la fermeture du sélecteur", "Fade out the switcher"), isOn: a.fadeOut)
                Toggle(tr("Fondu à l’apparition de l’aperçu", "Fade in the preview"), isOn: a.fadeInPreview)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(tr("Rafraîchir les miniatures en arrière-plan", "Refresh thumbnails in the background"), isOn: a.backgroundCapture)
                    Text(tr("Miniatures plus à jour à l’ouverture, mais macOS affiche alors en permanence que Flick capture l’écran.", "Fresher thumbnails when opening, but macOS then keeps showing that Flick is capturing the screen."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !Permissions.hasScreenRecording {
                    HStack {
                        Label(tr("Sans l’autorisation d’enregistrement de l’écran, les icônes remplacent les miniatures.", "Without the Screen Recording permission, icons replace thumbnails."),
                              systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Autoriser…", "Allow…")) { Permissions.requestScreenRecording() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Exceptions

private struct ExceptionSettings: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                if prefs.config.exceptions.isEmpty {
                    Text(tr("Aucune exception.", "No exceptions.")).foregroundStyle(.secondary)
                }
                ForEach($prefs.config.exceptions) { $exception in
                    ExceptionRow(exception: $exception) {
                        prefs.config.exceptions.removeAll { $0.id == exception.id }
                    }
                }
            } header: {
                Text(tr("Apps à part", "Special apps"))
            } footer: {
                Text(tr("Masquer retire les fenêtres de l’app du sélecteur (ou seulement celles dont le titre contient le texte indiqué). Ignorer les raccourcis laisse l’app recevoir ⌥⇥ elle-même : utile pour les machines virtuelles, le bureau à distance ou les jeux.", "Hide removes the app’s windows from the switcher (or only those whose title contains the given text). Ignore shortcuts lets the app receive ⌥⇥ itself: useful for virtual machines, remote desktop or games."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Menu(tr("Ajouter une app ouverte", "Add a running app")) {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app.bundleIdentifier) }
                        }
                    }
                    .fixedSize()
                    Button(tr("Ajouter une app du disque…", "Add an app from disk…")) { addFromDisk() }
                    Button(tr("Ajouter par identifiant", "Add by bundle ID")) { prefs.config.exceptions.append(AppException(bundleID: "", hide: .always)) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(_ bundleID: String?) {
        guard let bundleID, !prefs.config.exceptions.contains(where: { $0.bundleID == bundleID && $0.titleContains.isEmpty }) else { return }
        prefs.config.exceptions.append(AppException(bundleID: bundleID, hide: .always))
    }

    private func addFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(Bundle(url: url)?.bundleIdentifier)
    }
}

private struct ExceptionRow: View {
    @Binding var exception: AppException
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: exception.bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                    Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")).bold()
                    Text(exception.bundleID).font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField(tr("Identifiant (ex. com.exemple.app)", "Bundle ID (e.g. com.example.app)"), text: $exception.bundleID)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            HStack {
                Picker(tr("Masquer", "Hide"), selection: $exception.hide) {
                    ForEach(HideRule.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 230)
                Picker(tr("Ignorer les raccourcis", "Ignore shortcuts"), selection: $exception.ignoreShortcuts) {
                    ForEach(IgnoreRule.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 260)
            }
            if exception.hide == .always {
                TextField(tr("Seulement si le titre contient… (facultatif)", "Only if the title contains… (optional)"), text: $exception.titleContains)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: About

private struct AboutSettings: View {
    @State private var accessibility = Permissions.hasAccessibility
    @State private var screenRecording = Permissions.hasScreenRecording
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Flick").font(.title2.bold())
                        Text(verbatim: "Version \(Updater.shared.currentVersion)").foregroundStyle(.secondary)
                        Text(tr("Passez d’une fenêtre à l’autre avec un aperçu de chacune.", "Switch between windows with a preview of each one.")).font(.callout)
                    }
                }
                .padding(.vertical, 4)
            }
            Section(tr("Autorisations", "Permissions")) {
                PermissionRow(title: tr("Accessibilité", "Accessibility"), detail: tr("Pour lister, activer, fermer et réduire les fenêtres.", "To list, focus, close and minimize windows."), granted: accessibility) {
                    Permissions.requestAccessibility()
                }
                PermissionRow(title: tr("Enregistrement de l’écran", "Screen Recording"), detail: tr("Pour les miniatures et l’aperçu des fenêtres.", "For window thumbnails and previews."), granted: screenRecording) {
                    Permissions.requestScreenRecording()
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            accessibility = Permissions.hasAccessibility
            screenRecording = Permissions.hasScreenRecording
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text(tr("Autorisé", "Allowed")).foregroundStyle(.secondary)
            } else {
                Button(tr("Autoriser…", "Allow…"), action: request)
            }
        }
    }
}
