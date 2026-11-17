import AppKit
import Carbon
import FlickCore

/// Watches the keyboard (and trackpad gestures) on its own thread, so a busy main thread never delays or drops a
/// key. Shortcut keys are consumed here; everything else passes through untouched.
final class EventTap: @unchecked Sendable {
    static let shared = EventTap()

    private let lock = NSLock()
    private var machine = KeyMachine()
    private var gesture = GestureConfig()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var disabledHotKeys: Set<Private.SymbolicHotKey> = []

    var isRunning: Bool { lock.withLock { port != nil } }

    /// Starts the tap; fails without the Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << 29) // 29: gesture (trackpad touches)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: eventTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        lock.withLock { self.port = port }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let loop = CFRunLoopGetCurrent()
            self.lock.withLock { self.runLoop = loop }
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "app.flick.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    func apply(_ config: Config) {
        lock.withLock {
            machine.settings = KeyMachine.Settings(config)
            gesture = config.gesture
        }
        updateSymbolicHotKeys(config)
    }

    private var ignoredByApp = false
    private var suspended = false

    func setIgnoringShortcuts(_ ignoring: Bool) {
        lock.withLock {
            ignoredByApp = ignoring
            machine.ignoringShortcuts = ignoredByApp || suspended
        }
    }

    /// While a shortcut is being recorded in the settings.
    func setSuspended(_ value: Bool) {
        lock.withLock {
            suspended = value
            machine.ignoringShortcuts = ignoredByApp || suspended
        }
    }

    func endSession() {
        lock.withLock {
            machine.end()
            gestureOpened = false
        }
    }

    func beginExternalSession() {
        lock.withLock { machine.beginExternal(.manual) }
    }

    // MARK: Native shortcuts

    /// ⌘⇥ and ⌘` belong to macOS; when a Flick shortcut uses them, the native ones are turned off while Flick runs.
    private func updateSymbolicHotKeys(_ config: Config) {
        var wanted: Set<Private.SymbolicHotKey> = []
        for s in config.shortcuts where s.hold == .command || s.hold == [.command, .shift] {
            if s.keyCode == KeyCode.tab { wanted.formUnion([.commandTab, .commandShiftTab]) }
            if s.keyCode == KeyCode.grave { wanted.insert(.commandKeyAboveTab) }
        }
        for key in disabledHotKeys.subtracting(wanted) { Private.setEnabled(key, true) }
        for key in wanted.subtracting(disabledHotKeys) { Private.setEnabled(key, false) }
        disabledHotKeys = wanted
    }

    func restoreSymbolicHotKeys() {
        for key in disabledHotKeys { Private.setEnabled(key, true) }
        disabledHotKeys = []
    }

    // MARK: Events

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = lock.withLock({ self.port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = Self.modifiers(event.flags)
            let outcome: KeyMachine.Outcome = lock.withLock {
                let characters = machine.searching ? KeyboardLayout.shared.characters(code, shift: event.flags.contains(.maskShift)) : nil
                return machine.keyDown(code, modifiers: modifiers, characters: characters)
            }
            return dispatch(outcome, event)
        case .keyUp:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return dispatch(lock.withLock { machine.keyUp(code) }, event)
        case .flagsChanged:
            let commands = lock.withLock { machine.flagsChanged(Self.modifiers(event.flags)) }
            post(commands)
            return Unmanaged.passUnretained(event)
        default:
            if type.rawValue == 29 { handleGesture(event) }
            return Unmanaged.passUnretained(event)
        }
    }

    private func dispatch(_ outcome: KeyMachine.Outcome, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch outcome {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .consume(let commands):
            post(commands)
            return nil
        }
    }

    private func post(_ commands: [SwitcherCommand]) {
        guard !commands.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for command in commands { SwitcherController.shared.handle(command) }
            }
        }
    }

    static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        return m
    }

    // MARK: Trackpad

    private var gestureOrigin: CGFloat?
    private var gestureOpened = false
    /// Fraction of the trackpad a swipe travels per step.
    private let gestureStep: CGFloat = 0.09

    private func handleGesture(_ event: CGEvent) {
        let config = lock.withLock { gesture }
        guard config.kind != .none, let nsEvent = NSEvent(cgEvent: event) else { return }
        let touches = nsEvent.allTouches().filter { $0.phase != .ended && $0.phase != .cancelled }
        guard touches.count == config.kind.fingers else {
            // Fingers lifted (or a different number of them): finish the swipe.
            if touches.count < config.kind.fingers {
                let wasOpen = lock.withLock { () -> Bool in
                    let open = gestureOpened
                    gestureOrigin = nil
                    gestureOpened = false
                    if open { machine.end() }
                    return open
                }
                if wasOpen { post([.release]) }
            }
            return
        }
        let positions = touches.map { config.kind.isVertical ? $0.normalizedPosition.y : $0.normalizedPosition.x }
        let average = positions.reduce(0, +) / CGFloat(positions.count)
        var commands: [SwitcherCommand] = []
        lock.withLock {
            guard let origin = gestureOrigin else {
                gestureOrigin = average
                return
            }
            let delta = average - origin
            guard abs(delta) >= gestureStep else { return }
            // Right (or down) moves forward.
            let forward = config.kind.isVertical ? delta < 0 : delta > 0
            if !gestureOpened {
                gestureOpened = true
                machine.beginExternal(.gesture)
                commands.append(.open(.gesture, reverse: !forward))
            } else {
                commands.append(forward ? .next : .previous)
            }
            gestureOrigin = average
        }
        guard !commands.isEmpty else { return }
        if config.haptics {
            DispatchQueue.main.async { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
        post(commands)
    }
}

private func eventTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                              _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

/// Characters typed by a key on the current layout, for search. The layout is read on the main thread (the Text
/// Input Sources API requires it) and translated from any thread.
final class KeyboardLayout: @unchecked Sendable {
    static let shared = KeyboardLayout()
    private let lock = NSLock()
    private var layoutData: Data?
    private var keyboardType: UInt32 = 0

    @MainActor func refresh() {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let data = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }
            .map { Unmanaged<CFData>.fromOpaque($0).takeUnretainedValue() as Data }
        let type = UInt32(LMGetKbdType())
        lock.withLock {
            layoutData = data
            keyboardType = type
        }
    }

    @MainActor func observeChanges() {
        refresh()
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardLayout.shared.refresh() }
        }
    }

    func characters(_ keyCode: UInt16, shift: Bool) -> String? {
        let (data, type) = lock.withLock { (layoutData, keyboardType) }
        guard let data else { return nil }
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let modifierState: UInt32 = shift ? UInt32(shiftKey >> 8) & 0xff : 0
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifierState, type,
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
