@preconcurrency import ApplicationServices
import AppKit
import FlickCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionTimer: Timer?
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardLayout.shared.observeChanges()
        _ = Preferences.shared
        StatusItem.shared.install()
        Preferences.shared.apply()

        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

        if PermissionsWindowController.isNeeded { PermissionsWindowController.show() }
        if Permissions.hasAccessibility {
            startSwitching()
        } else {
            // Start as soon as the permission is granted, without a relaunch.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let delegate = NSApp.delegate as? AppDelegate
                    if Permissions.hasAccessibility { delegate?.startSwitching() }
                }
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppDelegate.updateIgnoredShortcuts() }
            }
        }
        Updater.shared.startAutomaticChecks()
    }

    private func startSwitching() {
        guard !started else { return }
        guard EventTap.shared.start() else { return }
        started = true
        permissionTimer?.invalidate()
        permissionTimer = nil
        WindowTracker.shared.start()
        _ = SwitcherController.shared
        Preferences.shared.apply()
        AppDelegate.updateIgnoredShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventTap.shared.restoreSymbolicHotKeys()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // With the menu bar icon hidden, opening Flick again is the way back to its settings.
        SettingsWindowController.show()
        return false
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: string) else { return }
        switch url.host {
        case "show": SwitcherController.shared.openManually()
        case "settings": SettingsWindowController.show()
        case "update":
            // Check now and install a newer version if there is one.
            SettingsWindowController.show(tab: .updates)
            Task {
                await Updater.shared.check(userInitiated: true)
                if Updater.shared.availableRelease != nil { await Updater.shared.install() }
            }
        default: break
        }
    }

    /// Lets the frontmost app keep Flick's shortcuts when an exception says so (virtual machines, games…).
    static func updateIgnoredShortcuts() {
        guard let front = NSWorkspace.shared.frontmostApplication, let bundleID = front.bundleIdentifier,
              let rule = Preferences.shared.config.exceptions.first(where: { $0.bundleID == bundleID && $0.ignoreShortcuts != .never })?.ignoreShortcuts else {
            EventTap.shared.setIgnoringShortcuts(false)
            return
        }
        switch rule {
        case .never:
            EventTap.shared.setIgnoringShortcuts(false)
        case .always:
            EventTap.shared.setIgnoringShortcuts(true)
        case .whenFullscreen:
            let element = AXUIElementCreateApplication(front.processIdentifier)
            DispatchQueue.global(qos: .userInitiated).async {
                AXUIElementSetMessagingTimeout(element, 0.3)
                let fullscreen = element.element(kAXFocusedWindowAttribute)?.bool(AXAttr.fullScreen) ?? false
                EventTap.shared.setIgnoringShortcuts(fullscreen)
            }
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

enum Permissions {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Flick: launch at login: \(error)")
        }
    }
}
