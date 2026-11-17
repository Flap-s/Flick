import Foundation

/// What the switcher knows about a window when it opens.
public struct WindowSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var isMinimized = false
    public var isAppHidden = false
    public var isFullscreen = false
    /// A tab of a native tabbed window that isn't the visible one.
    public var isBackgroundTab = false
    public var isOnVisibleSpace = true
    public var isOnAllSpaces = false
    /// 1-based Space number across all displays, when known.
    public var spaceNumber: Int?
    public var screenIndex: Int?
    public var focusOrder = 0
    public var creationOrder = 0

    public init(id: UInt32, pid: Int32, bundleID: String? = nil, appName: String, title: String) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
    }
}

/// A running app, listed on its own when it has no window.
public struct AppSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var name: String
    public var isHidden = false
    public var hasWindows = false
    public var focusOrder = 0
    public var launchOrder = 0

    public init(pid: Int32, bundleID: String? = nil, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

public enum SwitcherEntry: Equatable, Sendable {
    case window(WindowSnapshot)
    case app(AppSnapshot)

    public var pid: Int32 {
        switch self {
        case .window(let w): w.pid
        case .app(let a): a.pid
        }
    }

    public var appName: String {
        switch self {
        case .window(let w): w.appName
        case .app(let a): a.name
        }
    }

    public var title: String {
        switch self {
        case .window(let w): w.title
        case .app(let a): a.name
        }
    }

    /// Stable identity, to keep the selection on the same entry when the list is rebuilt.
    public var key: String {
        switch self {
        case .window(let w): "w\(w.id)"
        case .app(let a): "a\(a.pid)"
        }
    }

    public var window: WindowSnapshot? {
        if case .window(let w) = self { return w }
        return nil
    }
}

public struct BuildContext: Sendable {
    public var activePid: Int32?
    public var pidUnderCursor: Int32?
    public var switcherScreenIndex: Int?

    public init(activePid: Int32? = nil, pidUnderCursor: Int32? = nil, switcherScreenIndex: Int? = nil) {
        self.activePid = activePid
        self.pidUnderCursor = pidUnderCursor
        self.switcherScreenIndex = switcherScreenIndex
    }
}

public enum EntryBuilder {
    public static func build(windows: [WindowSnapshot], apps: [AppSnapshot], filters f: Filters,
                             exceptions: [AppException], context: BuildContext) -> [SwitcherEntry] {
        func passesAppFilter(_ pid: Int32) -> Bool {
            switch f.apps {
            case .all: true
            case .activeApp: pid == context.activePid
            case .nonActiveApps: pid != context.activePid
            case .appUnderCursor: pid == context.pidUnderCursor
            }
        }

        func hiddenByException(_ bundleID: String?, title: String?) -> Bool {
            guard let bundleID else { return false }
            return exceptions.contains { e in
                guard e.bundleID == bundleID, e.hide == .always else { return false }
                guard !e.titleContains.isEmpty else { return true }
                guard let title else { return false }
                return title.localizedCaseInsensitiveContains(e.titleContains)
            }
        }

        // 0: normal, 1: "show at the end", nil: hidden.
        func tier(_ w: WindowSnapshot) -> Int? {
            var tier = 0
            for (applies, visibility) in [(w.isMinimized, f.minimized), (w.isAppHidden, f.hidden), (w.isFullscreen, f.fullscreen)] where applies {
                switch visibility {
                case .hide: return nil
                case .showAtEnd: tier = 1
                case .show: break
                }
            }
            return tier
        }

        var tiers: [[SwitcherEntry]] = [[], []]
        var kept: [(WindowSnapshot, Int)] = []
        for w in windows {
            guard passesAppFilter(w.pid), !hiddenByException(w.bundleID, title: w.title) else { continue }
            if w.isBackgroundTab && !f.separateTabs { continue }
            switch f.spaces {
            case .all: break
            case .visible: if !(w.isOnVisibleSpace || w.isOnAllSpaces) { continue }
            case .nonVisible: if w.isOnVisibleSpace || w.isOnAllSpaces { continue }
            }
            if f.screens == .showingSwitcher, let screen = context.switcherScreenIndex, w.screenIndex != screen,
               !w.isMinimized { continue }
            guard let t = tier(w) else { continue }
            kept.append((w, t))
        }

        for t in 0...1 {
            var group = kept.filter { $0.1 == t }.map(\.0)
            group.sort(by: windowOrder(f.order))
            if f.oneWindowPerApp {
                var seen = Set<Int32>()
                group = group.filter { seen.insert($0.pid).inserted }
            }
            tiers[t] = group.map(SwitcherEntry.window)
        }

        // Apps without any window.
        if f.windowless != .hide && f.spaces != .nonVisible && f.screens != .showingSwitcher {
            let windowless = apps.filter { a in
                !a.hasWindows && passesAppFilter(a.pid) && !hiddenByException(a.bundleID, title: nil)
                    && !exceptions.contains { $0.bundleID == a.bundleID && $0.hide == .whenNoOpenWindow }
            }
            .sorted { a, b in
                switch f.order {
                case .recentlyFocused, .space: a.focusOrder > b.focusOrder
                case .recentlyCreated: a.launchOrder > b.launchOrder
                case .alphabetical: a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
            if f.windowless == .showAtEnd {
                tiers[1] += windowless.map(SwitcherEntry.app)
            } else {
                tiers[0] = merge(tiers[0], windowless, order: f.order)
            }
        }
        return tiers[0] + tiers[1]
    }

    static func windowOrder(_ order: WindowOrder) -> (WindowSnapshot, WindowSnapshot) -> Bool {
        switch order {
        case .recentlyFocused:
            return { $0.focusOrder > $1.focusOrder }
        case .recentlyCreated:
            return { $0.creationOrder > $1.creationOrder }
        case .alphabetical:
            return { a, b in
                let byApp = a.appName.localizedStandardCompare(b.appName)
                if byApp != .orderedSame { return byApp == .orderedAscending }
                let byTitle = a.title.localizedStandardCompare(b.title)
                if byTitle != .orderedSame { return byTitle == .orderedAscending }
                return a.focusOrder > b.focusOrder
            }
        case .space:
            return { a, b in
                // Windows on every Space come first, then Space 1, 2…
                let sa = a.isOnAllSpaces ? 0 : (a.spaceNumber ?? Int.max)
                let sb = b.isOnAllSpaces ? 0 : (b.spaceNumber ?? Int.max)
                if sa != sb { return sa < sb }
                return a.focusOrder > b.focusOrder
            }
        }
    }

    /// Interleaves windowless apps with windows following the list's order.
    static func merge(_ windows: [SwitcherEntry], _ apps: [AppSnapshot], order: WindowOrder) -> [SwitcherEntry] {
        guard !apps.isEmpty else { return windows }
        func rank(_ e: SwitcherEntry) -> (Int, String) {
            switch e {
            case .window(let w):
                switch order {
                case .recentlyFocused, .space: return (w.focusOrder, w.appName)
                case .recentlyCreated: return (w.creationOrder, w.appName)
                case .alphabetical: return (0, w.appName)
                }
            case .app(let a):
                switch order {
                case .recentlyFocused, .space: return (a.focusOrder, a.name)
                case .recentlyCreated: return (a.launchOrder, a.name)
                case .alphabetical: return (0, a.name)
                }
            }
        }
        if order == .space {
            return windows + apps.map(SwitcherEntry.app)
        }
        var result: [SwitcherEntry] = []
        var w = windows[...], a = apps.map(SwitcherEntry.app)[...]
        while let x = w.first, let y = a.first {
            let rx = rank(x), ry = rank(y)
            let takeWindow = order == .alphabetical
                ? rx.1.localizedStandardCompare(ry.1) != .orderedDescending
                : rx.0 >= ry.0
            if takeWindow { result.append(x); w.removeFirst() } else { result.append(y); a.removeFirst() }
        }
        return result + w + a
    }

    /// The entry to select when the switcher opens: the second one when the first is the window already in front.
    public static func initialSelection(_ entries: [SwitcherEntry], frontWindowID: UInt32?, frontPid: Int32?, reverse: Bool) -> Int {
        guard !entries.isEmpty else { return 0 }
        if reverse { return entries.count - 1 }
        let firstIsFront: Bool
        switch entries[0] {
        case .window(let w): firstIsFront = frontWindowID != nil ? w.id == frontWindowID : w.pid == frontPid
        case .app(let a): firstIsFront = a.pid == frontPid
        }
        return firstIsFront && entries.count > 1 ? 1 : 0
    }
}
