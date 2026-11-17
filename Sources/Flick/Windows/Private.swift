import AppKit
@preconcurrency import ApplicationServices

/// Private macOS window-server and accessibility functions, resolved at run time so a missing symbol degrades a
/// feature instead of preventing launch. These are the calls every window manager on macOS relies on: public APIs
/// can't list windows on other Spaces, tell which Space a window is on, or focus a precise window.
enum Private {
    typealias ConnectionID = Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let hiServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        let pointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) // -2 = RTLD_DEFAULT
            ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        return pointer.map { unsafeBitCast($0, to: type) }
    }

    // MARK: Window server

    private static let mainConnectionID = symbol("SLSMainConnectionID", in: skyLight, as: (@convention(c) () -> ConnectionID).self)
    private static let copyManagedDisplaySpaces = symbol("SLSCopyManagedDisplaySpaces", in: skyLight,
                                                         as: (@convention(c) (ConnectionID) -> Unmanaged<CFArray>?).self)
    private static let copySpacesForWindows = symbol("SLSCopySpacesForWindows", in: skyLight,
                                                     as: (@convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?).self)
    private static let hwCaptureWindowList = symbol("SLSHWCaptureWindowList", in: skyLight,
                                                    as: (@convention(c) (ConnectionID, UnsafeMutablePointer<CGWindowID>, Int32, UInt32) -> Unmanaged<CFArray>?).self)
    private static let setSymbolicHotKeyEnabled = symbol("SLSSetSymbolicHotKeyEnabled", in: skyLight,
                                                         as: (@convention(c) (Int32, Bool) -> CGError).self)
    private static let isSymbolicHotKeyEnabled = symbol("SLSIsSymbolicHotKeyEnabled", in: skyLight,
                                                        as: (@convention(c) (Int32) -> Bool).self)
    private static let setFrontProcessWithOptions = symbol("_SLPSSetFrontProcessWithOptions", in: skyLight,
                                                           as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError).self)
    private static let postEventRecordTo = symbol("SLPSPostEventRecordTo", in: skyLight,
                                                  as: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError).self)
    private static let getProcessForPID = symbol("GetProcessForPID", in: hiServices,
                                                 as: (@convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus).self)

    // MARK: Accessibility

    private static let axGetWindow = symbol("_AXUIElementGetWindow", in: hiServices,
                                            as: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    private static let axCreateWithRemoteToken = symbol("_AXUIElementCreateWithRemoteToken", in: hiServices,
                                                        as: (@convention(c) (CFData) -> Unmanaged<AXUIElement>?).self)

    static let connection: ConnectionID = mainConnectionID?() ?? 0

    static var canFocusPrecisely: Bool { setFrontProcessWithOptions != nil && postEventRecordTo != nil && getProcessForPID != nil }
    static var canCaptureWindows: Bool { hwCaptureWindowList != nil }
    static var canFindWindowsOnOtherSpaces: Bool { axCreateWithRemoteToken != nil }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let axGetWindow, axGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// Raw description of every display and its Spaces.
    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let copyManagedDisplaySpaces, let array = copyManagedDisplaySpaces(connection)?.takeRetainedValue() else { return [] }
        return array as? [[String: Any]] ?? []
    }

    /// Spaces a window belongs to (several for a window shown on every Space).
    static func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard let copySpacesForWindows,
              let array = copySpacesForWindows(connection, 0x7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue() else { return [] }
        return (array as? [NSNumber])?.map(\.uint64Value) ?? []
    }

    /// The window's current contents, even when it is covered or on another Space. Needs Screen Recording.
    static func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        guard let hwCaptureWindowList else { return nil }
        var id = windowID
        // Ignore the global clip shape (1 << 11), best resolution (1 << 8).
        guard let array = hwCaptureWindowList(connection, &id, 1, (1 << 11) | (1 << 8))?.takeRetainedValue(),
              CFArrayGetCount(array) > 0 else { return nil }
        let image = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: CGImage.self)
        return image.width > 1 && image.height > 1 ? image : nil
    }

    /// Native shortcuts Flick can take over: ⌘⇥ (1), ⌘⇧⇥ (2) and ⌘` (6).
    enum SymbolicHotKey: Int32, CaseIterable {
        case commandTab = 1
        case commandShiftTab = 2
        case commandKeyAboveTab = 6
    }

    static func setEnabled(_ hotKey: SymbolicHotKey, _ enabled: Bool) {
        if let isSymbolicHotKeyEnabled, isSymbolicHotKeyEnabled(hotKey.rawValue) == enabled { return }
        _ = setSymbolicHotKeyEnabled?(hotKey.rawValue, enabled)
    }

    /// Brings `windowID` of `pid` to the front and makes it key, switching Space if needed.
    @discardableResult
    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcessWithOptions, let postEventRecordTo, let getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        // 0x200: the change is user initiated.
        guard setFrontProcessWithOptions(&psn, windowID, 0x200) == .success else { return false }
        // A synthetic window-server event record that makes the window key: event type 0xf8 sent twice, as a
        // "mouse down" then "mouse up" on the window's title area.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { raw in
            for (i, b) in raw.enumerated() { bytes[0x3c + i] = b }
        }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecordTo(&psn, &bytes)
        return true
    }

    /// Accessibility elements for an app's windows that `kAXWindowsAttribute` leaves out (windows on other Spaces).
    /// Elements are addressed by a token made of the pid, a magic number and an element id; window ids are small.
    static func windowElementsByToken(pid: pid_t, maxID: UInt64 = 1000, stopAfter wanted: Set<CGWindowID>) -> [AXUIElement] {
        guard let axCreateWithRemoteToken, !wanted.isEmpty else { return [] }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) }) // "coco"
        var found: [AXUIElement] = []
        var remaining = wanted
        for elementID in 0..<maxID {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = axCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            guard let id = windowID(of: element), remaining.contains(id) else { continue }
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            let s = subrole as? String
            guard s == kAXStandardWindowSubrole || s == kAXDialogSubrole else { continue }
            found.append(element)
            remaining.remove(id)
            if remaining.isEmpty { break }
        }
        return found
    }
}
