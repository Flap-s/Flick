import AppKit
@preconcurrency import ApplicationServices

/// Red badges apps show on their Dock icon (unread counts…), read from the Dock over Accessibility.
enum DockBadges {
    /// Badge text by app bundle path.
    static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var badges: [String: String] = [:]
        for list in element.elements(kAXChildrenAttribute) {
            for item in list.elements(kAXChildrenAttribute) {
                guard let label = item.string(AXAttr.statusLabel), !label.isEmpty else { continue }
                if let url = item.value(kAXURLAttribute) as? URL {
                    badges[url.standardizedFileURL.path] = label
                }
            }
        }
        return badges
    }
}
