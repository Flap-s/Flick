import AppKit
@preconcurrency import ApplicationServices
import FlickCore

final class TrackedWindow {
    let id: CGWindowID
    let element: AXUIElement
    var title: String
    var isMinimized: Bool
    var isFullscreen: Bool
    /// Quartz coordinates (top-left origin).
    var frame: CGRect
    var focusOrder = 0
    var thumbnail: CGImage?
    var thumbnailDate: Date?

    init(id: CGWindowID, element: AXUIElement, title: String, isMinimized: Bool, isFullscreen: Bool, frame: CGRect) {
        self.id = id
        self.element = element
        self.title = title
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.frame = frame
    }
}

final class TrackedApp {
    let running: NSRunningApplication
    let pid: pid_t
    let element: AXUIElement
    var observer: AXObserver?
    var windows: [CGWindowID: TrackedWindow] = [:]
    var focusOrder = 0
    let launchOrder: Int
    /// Window-server windows of this app that turned out not to be document windows; not looked up again.
    var unresolvedIDs: Set<CGWindowID> = []
    var refreshPending = false
    /// Something changed while a refresh was already running: run another one after it.
    var refreshAgain = false
    var observedWindows: Set<CGWindowID> = []

    init(running: NSRunningApplication, launchOrder: Int) {
        self.running = running
        pid = running.processIdentifier
        element = AXUIElementCreateApplication(pid)
        self.launchOrder = launchOrder
        AXUIElementSetMessagingTimeout(element, 0.4)
    }

    var name: String { running.localizedName ?? running.bundleIdentifier ?? "App" }
}

/// A window as read from the app over Accessibility, off the main thread.
struct ScannedWindow {
    let id: CGWindowID
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
    let isFullscreen: Bool
    let frame: CGRect
}

/// Keeps the list of apps and windows current through Accessibility notifications, and remembers the order in
/// which windows were focused.
@MainActor
final class WindowTracker {
    static let shared = WindowTracker()

    private(set) var apps: [pid_t: TrackedApp] = [:]
    private var focusCounter = 1
    private var launchCounter = 0
    private let queue = DispatchQueue(label: "app.flick.ax", qos: .userInitiated, attributes: .concurrent)
    private var started = false
    /// Called after the window list changed (to refresh an open switcher).
    var onChange: (() -> Void)?
    /// Called with the window that just lost focus, to capture its latest content.
    var onFocusLeft: ((TrackedWindow) -> Void)?
    private var lastFocused: (pid: pid_t, id: CGWindowID)?
    private var changeScheduled = false

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { WindowTracker.shared.track(app, retries: true) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { WindowTracker.shared.untrack(app.processIdentifier) }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { WindowTracker.shared.appActivated(app) }
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WindowTracker.shared.changed() }
            }
        }
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowTracker.shared.refreshAll() }
        }

        // Seed the focus order with the current stacking order: frontmost window first.
        let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        seedOrder = Dictionary(uniqueKeysWithValues: onScreen.enumerated().map { ($1, onScreen.count - $0) })
        focusCounter = onScreen.count + 10

        for app in NSWorkspace.shared.runningApplications { track(app, retries: false) }
        if let front = NSWorkspace.shared.frontmostApplication { appActivated(front) }
    }

    private var seedOrder: [CGWindowID: Int] = [:]

    // MARK: Apps

    private func isSwitchable(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != getpid(), !app.isTerminated else { return false }
        // Regular apps, plus accessory apps that may own windows (menu bar apps with a settings window…).
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    func track(_ app: NSRunningApplication, retries: Bool) {
        guard isSwitchable(app), apps[app.processIdentifier] == nil else { return }
        launchCounter += 1
        let tracked = TrackedApp(running: app, launchOrder: launchCounter)
        apps[tracked.pid] = tracked
        observe(tracked)
        refresh(tracked)
        if retries {
            // Freshly launched apps answer Accessibility requests only after a moment.
            for delay in [0.5, 1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let app = self.apps[tracked.pid] else { return }
                    if app.observer == nil { self.observe(app) }
                    self.refresh(app)
                }
            }
        }
    }

    private func untrack(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        if let observer = app.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        changed()
    }

    private func observe(_ app: TrackedApp) {
        var observer: AXObserver?
        guard AXObserverCreate(app.pid, axCallback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(app).toOpaque()
        var any = false
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                     kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            if AXObserverAddNotification(observer, app.element, name as CFString, refcon) == .success { any = true }
        }
        // Apps that aren't ready yet refuse every registration; try again later.
        guard any else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        app.observer = observer
    }

    private func observeWindow(_ window: TrackedWindow, of app: TrackedApp) {
        guard let observer = app.observer, !app.observedWindows.contains(window.id) else { return }
        let refcon = Unmanaged.passUnretained(app).toOpaque()
        for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXTitleChangedNotification, kAXWindowResizedNotification, kAXWindowMovedNotification] {
            AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
        app.observedWindows.insert(window.id)
    }

    fileprivate func handle(_ notification: String, element: AXUIElement, app: TrackedApp) {
        guard apps[app.pid] === app else { return }
        switch notification {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if app.running.isActive, let id = element.windowID {
                focused(app: app, windowID: id)
            }
            refresh(app)
        case kAXApplicationHiddenNotification, kAXApplicationShownNotification:
            changed()
        case kAXUIElementDestroyedNotification:
            // The element is dead: find which window went away by asking the window server.
            refresh(app)
        default:
            if let id = element.windowID, let window = app.windows[id] {
                update(window, of: app)
            } else {
                refresh(app)
            }
        }
    }

    private func appActivated(_ app: NSRunningApplication) {
        guard let tracked = apps[app.processIdentifier] else { return }
        focusCounter += 1
        tracked.focusOrder = focusCounter
        let order = focusCounter
        let element = tracked.element
        queue.async {
            let id = element.element(kAXFocusedWindowAttribute)?.windowID
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let id else { WindowTracker.shared.changed(); return }
                    WindowTracker.shared.focused(app: tracked, windowID: id, order: order)
                }
            }
        }
    }

    private func focused(app: TrackedApp, windowID: CGWindowID, order: Int? = nil) {
        if let last = lastFocused, last.id != windowID, let previous = apps[last.pid]?.windows[last.id] {
            onFocusLeft?(previous)
        }
        lastFocused = (app.pid, windowID)
        let value: Int
        if let order { value = order } else { focusCounter += 1; value = focusCounter }
        app.focusOrder = max(app.focusOrder, value)
        if let window = app.windows[windowID] {
            window.focusOrder = max(window.focusOrder, value)
        } else {
            pendingFocus[windowID] = value
            refresh(app)
        }
        changed()
    }

    /// Focus order of windows that got focus before we knew them.
    private var pendingFocus: [CGWindowID: Int] = [:]

    /// Called by the switcher right after it focuses a window, so the order is right even before macOS reports it.
    func markFocused(pid: pid_t, windowID: CGWindowID?) {
        guard let app = apps[pid] else { return }
        focusCounter += 1
        app.focusOrder = focusCounter
        if let windowID {
            if let last = lastFocused, last.id != windowID, let previous = apps[last.pid]?.windows[last.id] {
                onFocusLeft?(previous)
            }
            lastFocused = (pid, windowID)
            app.windows[windowID]?.focusOrder = focusCounter
        }
    }

    // MARK: Refreshing

    func refreshAll() {
        for app in apps.values { refresh(app) }
    }

    /// Re-reads an app's windows in the background, merging the result.
    func refresh(_ app: TrackedApp) {
        guard !app.refreshPending else { app.refreshAgain = true; return }
        app.refreshPending = true
        let pid = app.pid
        let element = app.element
        let known = Set(app.windows.keys)
        let unresolved = app.unresolvedIDs
        queue.async {
            let server = ServerWindow.all()
            let serverIDs = Set(server.filter { $0.pid == pid }.map(\.id))
            var scanned = Self.scan(element.elements(kAXWindowsAttribute))
            // Windows the window server has but Accessibility didn't list: on another Space, or tabs.
            let found = Set(scanned.map(\.id))
            let missing = Set(server.filter { $0.pid == pid && $0.looksLikeWindow }.map(\.id))
                .subtracting(found).subtracting(known).subtracting(unresolved)
            var newlyUnresolved: Set<CGWindowID> = []
            if !missing.isEmpty {
                let extra = Self.scan(Private.windowElementsByToken(pid: pid, stopAfter: missing))
                scanned += extra
                newlyUnresolved = missing.subtracting(extra.map(\.id))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    WindowTracker.shared.merge(pid: pid, scanned: scanned, serverIDs: serverIDs, unresolved: newlyUnresolved)
                }
            }
        }
    }

    nonisolated static func scan(_ elements: [AXUIElement]) -> [ScannedWindow] {
        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, AXAttr.fullScreen,
                          kAXPositionAttribute, kAXSizeAttribute] as [String]
        return elements.compactMap { element in
            guard let id = element.windowID else { return nil }
            let v = element.values(attributes)
            guard (v[kAXRoleAttribute] as? String) == kAXWindowRole else { return nil }
            let subrole = v[kAXSubroleAttribute] as? String
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            let origin = AXUIElement.point(v[kAXPositionAttribute]) ?? .zero
            let size = AXUIElement.size(v[kAXSizeAttribute]) ?? .zero
            let minimized = (v[kAXMinimizedAttribute] as? NSNumber)?.boolValue ?? false
            guard minimized || (size.width >= 50 && size.height >= 30) else { return nil }
            return ScannedWindow(id: id, element: element, title: v[kAXTitleAttribute] as? String ?? "",
                                 isMinimized: minimized, isFullscreen: (v[AXAttr.fullScreen] as? NSNumber)?.boolValue ?? false,
                                 frame: CGRect(origin: origin, size: size))
        }
    }

    private func merge(pid: pid_t, scanned: [ScannedWindow], serverIDs: Set<CGWindowID>, unresolved: Set<CGWindowID>) {
        guard let app = apps[pid] else { return }
        app.refreshPending = false
        app.unresolvedIDs.formUnion(unresolved)
        app.unresolvedIDs.formIntersection(serverIDs)
        var changed = false
        var seen = Set<CGWindowID>()
        for s in scanned where !seen.contains(s.id) {
            seen.insert(s.id)
            if let w = app.windows[s.id] {
                if w.title != s.title || w.isMinimized != s.isMinimized || w.isFullscreen != s.isFullscreen { changed = true }
                w.title = s.title
                w.isMinimized = s.isMinimized
                w.isFullscreen = s.isFullscreen
                w.frame = s.frame
            } else {
                let w = TrackedWindow(id: s.id, element: s.element, title: s.title, isMinimized: s.isMinimized,
                                      isFullscreen: s.isFullscreen, frame: s.frame)
                w.focusOrder = pendingFocus.removeValue(forKey: s.id) ?? seedOrder[s.id] ?? 0
                app.windows[s.id] = w
                observeWindow(w, of: app)
                changed = true
            }
        }
        // Windows not listed this time are kept while the window server still has them (other Space).
        for id in app.windows.keys where !seen.contains(id) && !serverIDs.contains(id) {
            app.windows.removeValue(forKey: id)
            app.observedWindows.remove(id)
            changed = true
        }
        if changed { self.changed() }
        if app.refreshAgain {
            app.refreshAgain = false
            refresh(app)
        }
    }

    private func update(_ window: TrackedWindow, of app: TrackedApp) {
        let element = window.element
        queue.async {
            let scanned = Self.scan([element]).first
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let scanned else { WindowTracker.shared.refresh(app); return }
                    window.title = scanned.title
                    window.isMinimized = scanned.isMinimized
                    window.isFullscreen = scanned.isFullscreen
                    window.frame = scanned.frame
                    WindowTracker.shared.changed()
                }
            }
        }
    }

    /// Coalesces change notifications.
    func changed() {
        guard !changeScheduled else { return }
        changeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.changeScheduled = false
            self.onChange?()
        }
    }

    func window(_ id: CGWindowID) -> (TrackedApp, TrackedWindow)? {
        for app in apps.values { if let w = app.windows[id] { return (app, w) } }
        return nil
    }

    func remove(windowID: CGWindowID) {
        for app in apps.values where app.windows.removeValue(forKey: windowID) != nil {
            app.observedWindows.remove(windowID)
        }
        changed()
    }

    /// The frontmost app's focused window, as last reported.
    var frontWindow: (pid: pid_t, id: CGWindowID)? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        if let last = lastFocused, last.pid == front.processIdentifier { return last }
        return nil
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let app = Unmanaged<TrackedApp>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        WindowTracker.shared.handle(name, element: element, app: app)
    }
}
