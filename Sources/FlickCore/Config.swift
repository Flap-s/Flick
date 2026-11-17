import Foundation

// Every setting Flick has, as one Codable value. Decoding tolerates missing or unknown keys so older and newer
// settings files both load: each field falls back to its default.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// Keyboard modifiers, independent of AppKit and Core Graphics so the core can be tested.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

public enum AppFilter: String, Codable, CaseIterable, Sendable {
    case all, activeApp, nonActiveApps, appUnderCursor
}

public enum SpaceFilter: String, Codable, CaseIterable, Sendable {
    case all, visible, nonVisible
}

public enum ScreenFilter: String, Codable, CaseIterable, Sendable {
    case all, showingSwitcher
}

public enum Visibility: String, Codable, CaseIterable, Sendable {
    case show, showAtEnd, hide
}

public enum WindowOrder: String, Codable, CaseIterable, Sendable {
    case recentlyFocused, recentlyCreated, alphabetical, space
}

public enum ReleaseAction: String, Codable, CaseIterable, Sendable {
    case focusSelected, doNothing
}

/// Which windows a shortcut lists, and in what order.
public struct Filters: Codable, Equatable, Sendable {
    public var apps: AppFilter = .all
    public var spaces: SpaceFilter = .all
    public var screens: ScreenFilter = .all
    public var minimized: Visibility = .show
    public var hidden: Visibility = .show
    public var fullscreen: Visibility = .show
    public var windowless: Visibility = .showAtEnd
    public var order: WindowOrder = .recentlyFocused
    public var oneWindowPerApp = false
    public var separateTabs = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Filters()
        apps = c.value(.apps, d.apps)
        spaces = c.value(.spaces, d.spaces)
        screens = c.value(.screens, d.screens)
        minimized = c.value(.minimized, d.minimized)
        hidden = c.value(.hidden, d.hidden)
        fullscreen = c.value(.fullscreen, d.fullscreen)
        windowless = c.value(.windowless, d.windowless)
        order = c.value(.order, d.order)
        oneWindowPerApp = c.value(.oneWindowPerApp, d.oneWindowPerApp)
        separateTabs = c.value(.separateTabs, d.separateTabs)
    }
}

/// A shortcut's own values for some filters; `nil` follows the global value.
public struct FilterOverrides: Codable, Equatable, Sendable {
    public var apps: AppFilter?
    public var spaces: SpaceFilter?
    public var screens: ScreenFilter?
    public var minimized: Visibility?
    public var hidden: Visibility?
    public var fullscreen: Visibility?
    public var windowless: Visibility?
    public var order: WindowOrder?
    public var oneWindowPerApp: Bool?
    public var separateTabs: Bool?

    public init() {}

    public var isEmpty: Bool { self == FilterOverrides() }

    public func applied(to base: Filters) -> Filters {
        var f = base
        if let apps { f.apps = apps }
        if let spaces { f.spaces = spaces }
        if let screens { f.screens = screens }
        if let minimized { f.minimized = minimized }
        if let hidden { f.hidden = hidden }
        if let fullscreen { f.fullscreen = fullscreen }
        if let windowless { f.windowless = windowless }
        if let order { f.order = order }
        if let oneWindowPerApp { f.oneWindowPerApp = oneWindowPerApp }
        if let separateTabs { f.separateTabs = separateTabs }
        return f
    }
}

public struct Shortcut: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var hold: Modifiers = .option
    public var keyCode: UInt16 = KeyCode.tab
    public var releaseAction: ReleaseAction = .focusSelected
    public var overrides = FilterOverrides()

    public init(hold: Modifiers = .option, keyCode: UInt16 = KeyCode.tab, overrides: FilterOverrides = FilterOverrides()) {
        self.hold = hold
        self.keyCode = keyCode
        self.overrides = overrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Shortcut()
        id = c.value(.id, UUID())
        hold = c.value(.hold, d.hold)
        keyCode = c.value(.keyCode, d.keyCode)
        releaseAction = c.value(.releaseAction, d.releaseAction)
        overrides = c.value(.overrides, d.overrides)
    }
}

public enum GestureKind: String, Codable, CaseIterable, Sendable {
    case none, threeFingerHorizontal, threeFingerVertical, fourFingerHorizontal, fourFingerVertical

    public var fingers: Int {
        switch self {
        case .none: 0
        case .threeFingerHorizontal, .threeFingerVertical: 3
        case .fourFingerHorizontal, .fourFingerVertical: 4
        }
    }

    public var isVertical: Bool { self == .threeFingerVertical || self == .fourFingerVertical }
}

public struct GestureConfig: Codable, Equatable, Sendable {
    public var kind: GestureKind = .none
    public var overrides = FilterOverrides()
    public var haptics = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        kind = c.value(.kind, d.kind)
        overrides = c.value(.overrides, d.overrides)
        haptics = c.value(.haptics, d.haptics)
    }
}

/// Keys that act on the switcher while it is open (pressed while still holding the shortcut's modifiers).
public enum ControlAction: String, Codable, CaseIterable, Sendable {
    case focus, cancel, closeWindow, minimizeWindow, fullscreenWindow, quitApp, hideApp, search
}

public enum Style: String, Codable, CaseIterable, Sendable {
    case thumbnails, appIcons, titles
}

public enum SizeOption: String, Codable, CaseIterable, Sendable {
    case small, medium, large, auto
}

public enum Theme: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

public enum ShowOn: String, Codable, CaseIterable, Sendable {
    case activeScreen, mouseScreen, menuBarScreen
}

public enum TitleSource: String, Codable, CaseIterable, Sendable {
    case windowTitle, appName, appAndWindowTitle
}

public enum Truncation: String, Codable, CaseIterable, Sendable {
    case start, middle, end
}

public enum Alignment: String, Codable, CaseIterable, Sendable {
    case leading, center
}

public struct Appearance: Codable, Equatable, Sendable {
    public var style: Style = .thumbnails
    public var size: SizeOption = .medium
    public var theme: Theme = .system
    public var showOn: ShowOn = .activeScreen
    public var alignment: Alignment = .center
    /// Milliseconds between pressing the shortcut and the switcher appearing; a quick press-and-release switches
    /// without the switcher ever showing.
    public var apparitionDelay = 100
    public var fadeOut = true
    public var fadeInPreview = true
    public var previewSelectedWindow = true
    public var hideSpaceLabels = false
    public var hideStatusIcons = false
    public var hideWindowControls = false
    public var showBadges = true
    public var showTitles = true
    public var titleSource: TitleSource = .windowTitle
    public var truncation: Truncation = .end
    /// Off by default: while it runs, macOS keeps showing that Flick is capturing the screen.
    public var backgroundCapture = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        style = c.value(.style, d.style)
        size = c.value(.size, d.size)
        theme = c.value(.theme, d.theme)
        showOn = c.value(.showOn, d.showOn)
        alignment = c.value(.alignment, d.alignment)
        apparitionDelay = c.value(.apparitionDelay, d.apparitionDelay)
        fadeOut = c.value(.fadeOut, d.fadeOut)
        fadeInPreview = c.value(.fadeInPreview, d.fadeInPreview)
        previewSelectedWindow = c.value(.previewSelectedWindow, d.previewSelectedWindow)
        hideSpaceLabels = c.value(.hideSpaceLabels, d.hideSpaceLabels)
        hideStatusIcons = c.value(.hideStatusIcons, d.hideStatusIcons)
        hideWindowControls = c.value(.hideWindowControls, d.hideWindowControls)
        showBadges = c.value(.showBadges, d.showBadges)
        showTitles = c.value(.showTitles, d.showTitles)
        titleSource = c.value(.titleSource, d.titleSource)
        truncation = c.value(.truncation, d.truncation)
        backgroundCapture = c.value(.backgroundCapture, d.backgroundCapture)
    }
}

public enum HideRule: String, Codable, CaseIterable, Sendable {
    case never, always, whenNoOpenWindow
}

public enum IgnoreRule: String, Codable, CaseIterable, Sendable {
    case never, whenFullscreen, always
}

/// Per-app behaviour: hide its windows from the switcher, or let its own shortcuts through (games, virtual machines…).
public struct AppException: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var bundleID: String
    /// When not empty, only windows whose title contains this text are hidden.
    public var titleContains = ""
    public var hide: HideRule = .never
    public var ignoreShortcuts: IgnoreRule = .never

    public init(bundleID: String, titleContains: String = "", hide: HideRule = .never, ignoreShortcuts: IgnoreRule = .never) {
        self.bundleID = bundleID
        self.titleContains = titleContains
        self.hide = hide
        self.ignoreShortcuts = ignoreShortcuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        bundleID = c.value(.bundleID, "")
        titleContains = c.value(.titleContains, "")
        hide = c.value(.hide, HideRule.never)
        ignoreShortcuts = c.value(.ignoreShortcuts, IgnoreRule.never)
    }
}

public enum MenuBarIcon: String, Codable, CaseIterable, Sendable {
    case stack, windows, arrows, hidden
}

public struct Config: Codable, Equatable, Sendable {
    public static let maxShortcuts = 9

    public var shortcuts: [Shortcut] = Config.defaultShortcuts
    public var filters = Filters()
    public var gesture = GestureConfig()
    /// Key code for each additional control; a missing entry means unassigned.
    public var controls: [ControlAction: UInt16] = Config.defaultControls
    /// Held together with a shortcut's key, it walks the list backwards.
    public var previousModifier: Modifiers = .shift
    public var arrowKeys = true
    public var vimKeys = false
    public var mouseHover = true
    public var cursorFollowsFocus = false
    public var appearance = Appearance()
    public var exceptions: [AppException] = Config.defaultExceptions
    public var menuBarIcon: MenuBarIcon = .stack
    public var showSearchHint = true

    public init() {}

    public static let defaultShortcuts: [Shortcut] = {
        var sameApp = FilterOverrides()
        sameApp.apps = .activeApp
        sameApp.windowless = .hide
        return [
            Shortcut(hold: .option, keyCode: KeyCode.tab),
            Shortcut(hold: .option, keyCode: KeyCode.grave, overrides: sameApp),
        ]
    }()

    public static let defaultControls: [ControlAction: UInt16] = [
        .focus: KeyCode.space,
        .cancel: KeyCode.escape,
        .closeWindow: KeyCode.w,
        .minimizeWindow: KeyCode.m,
        .fullscreenWindow: KeyCode.f,
        .quitApp: KeyCode.q,
        .hideApp: KeyCode.h,
        .search: KeyCode.s,
    ]

    /// Remote desktops and virtual machines forward ⌥⇥ to the machine they show when fullscreen.
    public static let defaultExceptions: [AppException] = [
        "com.microsoft.rdc.macos", "com.vmware.fusion", "com.parallels.desktop.console", "com.citrix.XenAppViewer",
        "com.utmapp.UTM", "com.apple.ScreenSharing",
    ].map { AppException(bundleID: $0, ignoreShortcuts: .whenFullscreen) }

    public func filters(forShortcut index: Int) -> Filters {
        guard shortcuts.indices.contains(index) else { return filters }
        return shortcuts[index].overrides.applied(to: filters)
    }

    public var gestureFilters: Filters { gesture.overrides.applied(to: filters) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        shortcuts = Array(c.value(.shortcuts, d.shortcuts).prefix(Config.maxShortcuts))
        filters = c.value(.filters, d.filters)
        gesture = c.value(.gesture, d.gesture)
        let rawControls: [String: UInt16]? = try? c.decodeIfPresent([String: UInt16].self, forKey: .controls)
        if let rawControls {
            controls = Dictionary(uniqueKeysWithValues: rawControls.compactMap { key, code in
                ControlAction(rawValue: key).map { ($0, code) }
            })
        } else {
            controls = d.controls
        }
        previousModifier = c.value(.previousModifier, d.previousModifier)
        arrowKeys = c.value(.arrowKeys, d.arrowKeys)
        vimKeys = c.value(.vimKeys, d.vimKeys)
        mouseHover = c.value(.mouseHover, d.mouseHover)
        cursorFollowsFocus = c.value(.cursorFollowsFocus, d.cursorFollowsFocus)
        appearance = c.value(.appearance, d.appearance)
        exceptions = c.value(.exceptions, d.exceptions)
        menuBarIcon = c.value(.menuBarIcon, d.menuBarIcon)
        showSearchHint = c.value(.showSearchHint, d.showSearchHint)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortcuts, forKey: .shortcuts)
        try c.encode(filters, forKey: .filters)
        try c.encode(gesture, forKey: .gesture)
        try c.encode(Dictionary(uniqueKeysWithValues: controls.map { ($0.key.rawValue, $0.value) }), forKey: .controls)
        try c.encode(previousModifier, forKey: .previousModifier)
        try c.encode(arrowKeys, forKey: .arrowKeys)
        try c.encode(vimKeys, forKey: .vimKeys)
        try c.encode(mouseHover, forKey: .mouseHover)
        try c.encode(cursorFollowsFocus, forKey: .cursorFollowsFocus)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(exceptions, forKey: .exceptions)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
        try c.encode(showSearchHint, forKey: .showSearchHint)
    }

    private enum CodingKeys: String, CodingKey {
        case shortcuts, filters, gesture, controls, previousModifier, arrowKeys, vimKeys, mouseHover, cursorFollowsFocus
        case appearance, exceptions, menuBarIcon, showSearchHint
    }

    /// Controls whose key is also used by vim navigation while vim keys are on (vim wins).
    public var controlsShadowedByVim: [ControlAction] {
        guard vimKeys else { return [] }
        return ControlAction.allCases.filter { action in controls[action].map(KeyCode.vim.keys.contains) ?? false }
    }

    /// The other shortcut, if any, already using this hold + key combination.
    public func shortcutConflict(hold: Modifiers, keyCode: UInt16, excluding index: Int) -> Int? {
        shortcuts.indices.first { $0 != index && shortcuts[$0].hold == hold && shortcuts[$0].keyCode == keyCode }
    }
}

/// ANSI virtual key codes Flick needs by name. They identify physical keys, so they hold on any layout.
public enum KeyCode {
    public static let tab: UInt16 = 48
    public static let grave: UInt16 = 50
    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53
    public static let returnKey: UInt16 = 36
    public static let keypadEnter: UInt16 = 76
    public static let delete: UInt16 = 51
    public static let forwardDelete: UInt16 = 117
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126
    public static let w: UInt16 = 13
    public static let m: UInt16 = 46
    public static let f: UInt16 = 3
    public static let q: UInt16 = 12
    public static let h: UInt16 = 4
    public static let j: UInt16 = 38
    public static let k: UInt16 = 40
    public static let l: UInt16 = 37
    public static let s: UInt16 = 1

    public static let vim: [UInt16: Direction] = [h: .left, j: .down, k: .up, l: .right]
    public static let arrows: [UInt16: Direction] = [left: .left, right: .right, up: .up, down: .down]
}

public enum Direction: Sendable, Equatable {
    case left, right, up, down
}
