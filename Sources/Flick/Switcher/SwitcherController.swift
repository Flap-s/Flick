import AppKit
import FlickCore

/// Runs a switcher session: builds the list, follows the commands of the event tap and the mouse, and focuses the
/// chosen window.
@MainActor
final class SwitcherController {
    static let shared = SwitcherController()

    private let panel = SwitcherPanel()
    private let preview = PreviewWindow()
    private var sessionActive = false
    private var source: SwitcherSource = .manual
    private var filters = Filters()
    private var allEntries: [SwitcherEntry] = []
    private var entries: [SwitcherEntry] = []
    private var selected = 0
    private var searching = false
    private var query = ""
    private var screen: NSScreen?
    private var showWork: DispatchWorkItem?
    private var badges: [String: String] = [:]
    private var outsideClickMonitor: Any?
    private var fadeGeneration = 0

    private(set) var isVisible = false

    private var config: Config { Preferences.shared.config }

    init() {
        panel.onHover = { [weak self] index in self?.select(index, fromMouse: true) }
        panel.onClick = { [weak self] index in
            guard let self else { return }
            self.select(index, fromMouse: true)
            self.focusSelected()
        }
        panel.onControl = { [weak self] index, control in
            guard let self, self.entries.indices.contains(index) else { return }
            self.select(index, fromMouse: true)
            switch control {
            case .close: self.perform(.closeWindow)
            case .minimize: self.perform(.minimizeWindow)
            case .fullscreen: self.perform(.fullscreenWindow)
            }
        }
        WindowTracker.shared.onChange = { [weak self] in self?.windowsChanged() }
        Thumbnails.shared.onUpdate = { [weak self] id in self?.thumbnailUpdated(id) }
    }

    // MARK: Commands

    func handle(_ command: SwitcherCommand) {
        switch command {
        case .open(let source, let reverse):
            open(source, reverse: reverse)
        case .next:
            guard sessionActive else { return }
            select(entries.isEmpty ? 0 : (selected + 1) % entries.count)
        case .previous:
            guard sessionActive else { return }
            select(entries.isEmpty ? 0 : (selected - 1 + entries.count) % entries.count)
        case .move(let direction):
            guard sessionActive else { return }
            select(panel.layoutInfo.neighbour(of: selected, direction))
        case .release:
            guard sessionActive else { return }
            focusSelected()
        case .control(let action):
            guard sessionActive else { return }
            perform(action)
        case .searchInput(let text):
            guard sessionActive else { return }
            query += text
            applySearch()
        case .searchBackspace:
            guard sessionActive, !query.isEmpty else { return }
            query.removeLast()
            applySearch()
        case .searchEnd:
            guard sessionActive else { return }
            searching = false
            query = ""
            applySearch()
        }
    }

    /// From the menu bar or `flick://show`.
    func openManually() {
        if sessionActive { cancel(); return }
        EventTap.shared.beginExternalSession()
        open(.manual, reverse: false)
    }

    private func open(_ newSource: SwitcherSource, reverse: Bool) {
        let switchingShortcut = sessionActive
        source = newSource
        switch newSource {
        case .shortcut(let index): filters = config.filters(forShortcut: index)
        case .gesture: filters = config.gestureFilters
        case .manual: filters = config.filters
        }
        if !switchingShortcut {
            searching = false
            query = ""
            screen = chooseScreen()
        }
        rebuild(keepingSelection: false, reverse: reverse)
        guard !entries.isEmpty || switchingShortcut else {
            EventTap.shared.endSession()
            NSSound.beep()
            return
        }
        sessionActive = true
        loadBadges()

        if switchingShortcut {
            if isVisible {
                render()
                captureThumbnails()
            }
            return
        }
        var delay = 0
        if case .shortcut = newSource { delay = max(0, config.appearance.apparitionDelay) }
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reveal() }
        showWork = work
        if delay == 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: work) }
    }

    private func reveal() {
        guard sessionActive, !isVisible else { return }
        isVisible = true
        fadeGeneration += 1
        panel.alphaValue = 1
        render()
        panel.orderFrontRegardless()
        updatePreview()
        // Capturing makes macOS show its screen-capture indicator: only do it once the switcher is really on
        // screen, never for a quick press-and-release.
        captureThumbnails()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { SwitcherController.shared.cancel() }
        }
    }

    private func chooseScreen() -> NSScreen? {
        switch config.appearance.showOn {
        case .menuBarScreen:
            return NSScreen.screens.first
        case .mouseScreen:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        case .activeScreen:
            if let front = WindowTracker.shared.frontWindow, let (_, window) = WindowTracker.shared.window(front.id),
               let index = ScreenGeometry.screenIndex(forQuartz: window.frame) {
                return NSScreen.screens[index]
            }
            return NSScreen.main
        }
    }

    // MARK: Building the list

    private func rebuild(keepingSelection: Bool, reverse: Bool = false) {
        let previousKey = entries.indices.contains(selected) ? entries[selected].key : nil
        let spaces = SpacesSnapshot.current()
        WindowTrackerSpacesInfo.hasSeveralSpaces = spaces.spaces.values.filter { !$0.isFullscreen }.count > 1
        let server = Dictionary(ServerWindow.all().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var windows: [WindowSnapshot] = []
        var apps: [AppSnapshot] = []
        let screenIndex = screen.flatMap { NSScreen.screens.firstIndex(of: $0) }

        for app in WindowTracker.shared.apps.values {
            let running = app.running
            guard !running.isTerminated else { continue }
            var appSnapshot = AppSnapshot(pid: app.pid, bundleID: running.bundleIdentifier, name: app.name)
            appSnapshot.isHidden = running.isHidden
            appSnapshot.focusOrder = app.focusOrder
            appSnapshot.launchOrder = app.launchOrder
            appSnapshot.hasWindows = !app.windows.isEmpty
            // Menu bar apps without a window aren't something to switch to.
            if running.activationPolicy == .regular || !app.windows.isEmpty { apps.append(appSnapshot) }

            for w in app.windows.values {
                var s = WindowSnapshot(id: w.id, pid: app.pid, bundleID: running.bundleIdentifier, appName: app.name, title: w.title)
                s.isMinimized = w.isMinimized
                s.isAppHidden = running.isHidden
                s.isFullscreen = w.isFullscreen
                s.focusOrder = w.focusOrder
                s.creationOrder = Int(w.id)
                let spaceIDs = Private.spaces(of: w.id)
                s.isOnAllSpaces = spaceIDs.count > 1
                s.isOnVisibleSpace = spaceIDs.isEmpty || spaceIDs.contains { spaces.visible.contains($0) }
                if spaceIDs.count == 1 { s.spaceNumber = spaces.spaces[spaceIDs[0]]?.number }
                s.screenIndex = ScreenGeometry.screenIndex(forQuartz: w.frame)
                if let info = server[w.id] {
                    s.isBackgroundTab = !info.isOnScreen && !w.isMinimized && !running.isHidden && s.isOnVisibleSpace && !w.isFullscreen
                }
                windows.append(s)
            }
        }

        let context = BuildContext(activePid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                   pidUnderCursor: Self.pidUnderCursor(), switcherScreenIndex: screenIndex)
        allEntries = EntryBuilder.build(windows: windows, apps: apps, filters: filters, exceptions: config.exceptions, context: context)
        entries = FuzzySearch.filter(allEntries, query: query)

        if keepingSelection, let previousKey, let index = entries.firstIndex(where: { $0.key == previousKey }) {
            selected = index
        } else if keepingSelection {
            selected = min(selected, max(entries.count - 1, 0))
        } else {
            let front = WindowTracker.shared.frontWindow
            selected = EntryBuilder.initialSelection(entries, frontWindowID: front?.id,
                                                     frontPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                                     reverse: reverse)
        }
    }

    private static func pidUnderCursor() -> Int32? {
        let mouse = ScreenGeometry.quartzPoint(fromCocoa: NSEvent.mouseLocation)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.contains(mouse),
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != getpid() else { continue }
            return pid
        }
        return nil
    }

    private func applySearch() {
        entries = FuzzySearch.filter(allEntries, query: query)
        selected = 0
        if isVisible { render() }
        updatePreview()
    }

    private func itemModel(_ entry: SwitcherEntry) -> ItemModel {
        let app = WindowTracker.shared.apps[entry.pid]
        var model = ItemModel(key: entry.key, title: entry.title, icon: app?.running.icon)
        switch entry {
        case .window(let w):
            let tracked = app?.windows[w.id]
            let title = w.title.isEmpty ? w.appName : w.title
            model.title = switch config.appearance.titleSource {
            case .windowTitle: title
            case .appName: w.appName
            case .appAndWindowTitle: w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)"
            }
            model.thumbnail = tracked?.thumbnail
            model.isMinimized = w.isMinimized
            model.isHidden = w.isAppHidden
            model.isFullscreen = w.isFullscreen
            model.isOnAllSpaces = w.isOnAllSpaces
            model.spaceNumber = w.spaceNumber
            model.hasWindowControls = true
        case .app(let a):
            model.title = a.name
            model.isWindowless = true
            model.isHidden = a.isHidden
        }
        if let path = app?.running.bundleURL?.standardizedFileURL.path { model.badge = badges[path] }
        return model
    }

    private func render() {
        guard let screen = screen ?? NSScreen.main else { return }
        let models = entries.map(itemModel)
        let ratios = entries.map { entry -> CGFloat in
            guard let w = entry.window, let tracked = WindowTracker.shared.apps[w.pid]?.windows[w.id] else { return 0 }
            if let image = tracked.thumbnail { return CGFloat(image.width) / CGFloat(max(image.height, 1)) }
            return tracked.frame.height > 0 ? tracked.frame.width / tracked.frame.height : 0
        }
        var hint: String?
        if config.showSearchHint, let code = config.controls[.search] {
            hint = tr("\(config.shortcuts.first?.hold.symbols ?? "")\(KeyNames.name(code)) pour rechercher", "\(config.shortcuts.first?.hold.symbols ?? "")\(KeyNames.name(code)) to search")
        }
        panel.show(SwitcherPanel.Content(items: models, aspectRatios: ratios, selected: selected, searching: searching,
                                         query: query, hint: hint),
                   appearance: config.appearance, mouseHover: config.mouseHover, on: screen)
    }

    // MARK: Selection

    private func select(_ index: Int, fromMouse: Bool = false) {
        guard entries.indices.contains(index), index != selected || fromMouse else { return }
        let changed = index != selected
        selected = index
        panel.select(index)
        if changed { updatePreview() }
    }

    private func updatePreview() {
        guard isVisible, config.appearance.previewSelectedWindow, entries.indices.contains(selected),
              let w = entries[selected].window, !w.isMinimized, !w.isAppHidden,
              let tracked = WindowTracker.shared.apps[w.pid]?.windows[w.id], let image = tracked.thumbnail,
              tracked.frame.width > 0 else {
            preview.hide()
            return
        }
        preview.show(image: image, quartzFrame: tracked.frame, fadeIn: config.appearance.fadeInPreview)
    }

    // MARK: Ending

    func focusSelected() {
        guard sessionActive else { return }
        let entry = entries.indices.contains(selected) ? entries[selected] : nil
        close(animated: false)
        guard let entry, let app = WindowTracker.shared.apps[entry.pid] else { return }
        let window = entry.window.flatMap { app.windows[$0.id] }
        WindowActions.focus(app: app.running, window: window, moveCursor: config.cursorFollowsFocus)
    }

    func cancel() {
        guard sessionActive else { return }
        close(animated: config.appearance.fadeOut)
    }

    private func close(animated: Bool) {
        sessionActive = false
        showWork?.cancel()
        showWork = nil
        EventTap.shared.endSession()
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        preview.hide()
        guard isVisible else { return }
        isVisible = false
        panel.resetHover()
        fadeGeneration += 1
        let generation = fadeGeneration
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    let controller = SwitcherController.shared
                    guard controller.fadeGeneration == generation else { return }
                    controller.panel.orderOut(nil)
                    controller.panel.alphaValue = 1
                }
            })
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Actions on the selection

    private func perform(_ action: ControlAction) {
        switch action {
        case .focus: focusSelected(); return
        case .cancel: cancel(); return
        case .search:
            searching = true
            if isVisible { render() } else { reveal() }
            return
        default: break
        }
        guard entries.indices.contains(selected) else { return }
        let entry = entries[selected]
        guard let app = WindowTracker.shared.apps[entry.pid] else { return }
        let window = entry.window.flatMap { app.windows[$0.id] }
        switch action {
        case .closeWindow:
            guard let window else { return }
            WindowActions.close(window)
            WindowTracker.shared.remove(windowID: window.id)
            removeEntries { $0.key == entry.key }
        case .minimizeWindow:
            guard let window else { return }
            WindowActions.toggleMinimized(window)
            rebuild(keepingSelection: true)
            if isVisible { render() }
        case .fullscreenWindow:
            guard let window else { return }
            WindowActions.toggleFullscreen(window)
            rebuild(keepingSelection: true)
            if isVisible { render() }
        case .quitApp:
            WindowActions.quit(app.running)
            if app.running.bundleIdentifier != "com.apple.finder" { removeEntries { $0.pid == entry.pid } }
        case .hideApp:
            WindowActions.toggleHidden(app.running)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.sessionActive else { return }
                self.rebuild(keepingSelection: true)
                if self.isVisible { self.render() }
            }
        default: break
        }
        updatePreview()
    }

    private func removeEntries(where predicate: (SwitcherEntry) -> Bool) {
        allEntries.removeAll(where: predicate)
        entries.removeAll(where: predicate)
        guard !entries.isEmpty else { cancel(); return }
        selected = min(selected, entries.count - 1)
        if isVisible { render() }
    }

    // MARK: Updates while open

    private func windowsChanged() {
        guard sessionActive else { return }
        let before = entries.map(\.key)
        rebuild(keepingSelection: true)
        if entries.isEmpty { cancel(); return }
        if isVisible && entries.map(\.key) != before { render() }
        if isVisible { captureThumbnails() }
    }

    private func captureThumbnails() {
        let windows = entries.compactMap { entry in entry.window.flatMap { WindowTracker.shared.apps[$0.pid]?.windows[$0.id] } }
        let scale = (screen ?? NSScreen.main)?.backingScaleFactor ?? 2
        let height = SwitcherLayout.metrics(style: .thumbnails, size: config.appearance.size == .auto ? .large : config.appearance.size,
                                            screen: (screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900),
                                            showTitles: true).mainSize
        // The preview needs full size; thumbnails only their displayed size.
        let pixels = config.appearance.previewSelectedWindow ? 2400 : height * 2 * scale
        Thumbnails.shared.capture(windows, maxPixelSize: pixels)
    }

    private func thumbnailUpdated(_ id: CGWindowID) {
        guard sessionActive, let index = entries.firstIndex(where: { $0.window?.id == id }),
              let tracked = WindowTracker.shared.apps[entries[index].pid]?.windows[id] else { return }
        if isVisible {
            // A first image changes the cell's shape; a later one only its contents.
            panel.updateThumbnail(at: index, tracked.thumbnail)
        }
        if index == selected { updatePreview() }
    }

    private func loadBadges() {
        guard config.appearance.showBadges else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let badges = DockBadges.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let controller = SwitcherController.shared
                    controller.badges = badges
                    guard controller.isVisible else { return }
                    for (i, entry) in controller.entries.enumerated() {
                        let path = WindowTracker.shared.apps[entry.pid]?.running.bundleURL?.standardizedFileURL.path
                        controller.panel.updateBadge(at: i, path.flatMap { badges[$0] })
                    }
                }
            }
        }
    }
}
