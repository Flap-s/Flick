import AppKit
@preconcurrency import ApplicationServices

/// What the switcher can do to a window or an app.
@MainActor
enum WindowActions {
    private static let queue = DispatchQueue(label: "app.flick.actions", qos: .userInteractive)

    static func focus(app: NSRunningApplication, window: TrackedWindow?, moveCursor: Bool) {
        guard let window else {
            focusWindowless(app)
            return
        }
        let pid = app.processIdentifier
        let element = window.element
        let id = window.id
        let wasMinimized = window.isMinimized
        let frame = window.frame
        if app.isHidden { app.unhide() }
        WindowTracker.shared.markFocused(pid: pid, windowID: id)
        queue.async {
            if wasMinimized { element.set(kAXMinimizedAttribute, kCFBooleanFalse) }
            if !Private.focus(pid: pid, windowID: id) {
                DispatchQueue.main.sync { _ = app.activate(options: []) }
            }
            element.perform(kAXRaiseAction)
            element.set(kAXMainAttribute, kCFBooleanTrue)
            if moveCursor {
                let target = CGPoint(x: frame.midX, y: frame.midY)
                DispatchQueue.main.async { CGWarpMouseCursorPosition(target) }
            }
        }
    }

    /// Activating an app without windows the way the Dock does, which usually opens a new window.
    private static func focusWindowless(_ app: NSRunningApplication) {
        WindowTracker.shared.markFocused(pid: app.processIdentifier, windowID: nil)
        if app.isHidden { app.unhide() }
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        } else {
            app.activate(options: [])
        }
    }

    static func close(_ window: TrackedWindow) {
        let element = window.element
        queue.async {
            if window.isFullscreen { element.set(AXAttr.fullScreen, kCFBooleanFalse) }
            if let button = element.element(kAXCloseButtonAttribute) {
                button.perform(kAXPressAction)
            }
        }
    }

    static func toggleMinimized(_ window: TrackedWindow) {
        let element = window.element
        let minimized = window.isMinimized
        window.isMinimized = !minimized
        queue.async { element.set(kAXMinimizedAttribute, minimized ? kCFBooleanFalse : kCFBooleanTrue) }
    }

    static func toggleFullscreen(_ window: TrackedWindow) {
        let element = window.element
        let fullscreen = window.isFullscreen
        window.isFullscreen = !fullscreen
        queue.async { element.set(AXAttr.fullScreen, fullscreen ? kCFBooleanFalse : kCFBooleanTrue) }
    }

    static func quit(_ app: NSRunningApplication) {
        // Finder can't be quit from the outside without leaving the desktop empty; hide it instead, like the Dock.
        if app.bundleIdentifier == "com.apple.finder" {
            app.hide()
        } else {
            app.terminate()
        }
    }

    static func toggleHidden(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() } else { app.hide() }
    }
}
