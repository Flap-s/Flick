import XCTest
@testable import FlickCore

final class EntryBuilderTests: XCTestCase {
    private func window(_ id: UInt32, pid: Int32 = 1, app: String = "App", title: String = "", focus: Int = 0) -> WindowSnapshot {
        var w = WindowSnapshot(id: id, pid: pid, bundleID: "b\(pid)", appName: app, title: title.isEmpty ? "W\(id)" : title)
        w.focusOrder = focus
        w.creationOrder = Int(id)
        return w
    }

    func testRecentlyFocusedOrderAndMinimizedAtEnd() {
        var minimized = window(3, focus: 30)
        minimized.isMinimized = true
        let windows = [window(1, focus: 10), window(2, focus: 20), minimized]
        var f = Filters()
        f.minimized = .showAtEnd
        let ids = EntryBuilder.build(windows: windows, apps: [], filters: f, exceptions: [], context: BuildContext()).compactMap { $0.window?.id }
        XCTAssertEqual(ids, [2, 1, 3])
        f.minimized = .hide
        XCTAssertEqual(EntryBuilder.build(windows: windows, apps: [], filters: f, exceptions: [], context: BuildContext()).count, 2)
    }

    func testActiveAppFilterAndOneWindowPerApp() {
        let windows = [window(1, pid: 1, focus: 5), window(2, pid: 2, focus: 9), window(3, pid: 1, focus: 7)]
        var f = Filters()
        f.apps = .activeApp
        let active = EntryBuilder.build(windows: windows, apps: [], filters: f, exceptions: [], context: BuildContext(activePid: 1))
        XCTAssertEqual(active.compactMap { $0.window?.id }, [3, 1])
        f.apps = .all
        f.oneWindowPerApp = true
        let grouped = EntryBuilder.build(windows: windows, apps: [], filters: f, exceptions: [], context: BuildContext())
        XCTAssertEqual(grouped.compactMap { $0.window?.id }, [2, 3])
    }

    func testExceptionsAndWindowlessApps() {
        let windows = [window(1, pid: 1, title: "Secret notes"), window(2, pid: 1, title: "Inbox")]
        var empty = AppSnapshot(pid: 5, bundleID: "b5", name: "Calc")
        empty.focusOrder = 100
        let exceptions = [AppException(bundleID: "b1", titleContains: "secret", hide: .always)]
        var f = Filters()
        f.windowless = .showAtEnd
        let entries = EntryBuilder.build(windows: windows, apps: [empty], filters: f, exceptions: exceptions, context: BuildContext())
        XCTAssertEqual(entries.map(\.key), ["w2", "a5"])
        f.windowless = .show
        let merged = EntryBuilder.build(windows: windows, apps: [empty], filters: f, exceptions: exceptions, context: BuildContext())
        XCTAssertEqual(merged.map(\.key), ["a5", "w2"])
        let hidden = EntryBuilder.build(windows: windows, apps: [empty], filters: f,
                                        exceptions: [AppException(bundleID: "b5", hide: .whenNoOpenWindow)], context: BuildContext())
        XCTAssertFalse(hidden.contains { $0.key == "a5" })
    }

    func testSpaceFilterAndTabs() {
        var other = window(1)
        other.isOnVisibleSpace = false
        var tab = window(2)
        tab.isBackgroundTab = true
        var f = Filters()
        f.spaces = .visible
        XCTAssertEqual(EntryBuilder.build(windows: [other, tab, window(3)], apps: [], filters: f, exceptions: [], context: BuildContext()).map(\.key), ["w3"])
        f.separateTabs = true
        XCTAssertEqual(EntryBuilder.build(windows: [other, tab, window(3)], apps: [], filters: f, exceptions: [], context: BuildContext()).count, 2)
    }

    func testInitialSelectionSkipsFrontWindow() {
        let entries = [SwitcherEntry.window(window(1)), .window(window(2))]
        XCTAssertEqual(EntryBuilder.initialSelection(entries, frontWindowID: 1, frontPid: 1, reverse: false), 1)
        XCTAssertEqual(EntryBuilder.initialSelection(entries, frontWindowID: 9, frontPid: 1, reverse: false), 0)
        XCTAssertEqual(EntryBuilder.initialSelection(entries, frontWindowID: 1, frontPid: 1, reverse: true), 1)
    }
}

final class KeyMachineTests: XCTestCase {
    private func machine() -> KeyMachine {
        KeyMachine(settings: KeyMachine.Settings(Config()))
    }

    func testHoldPressRelease() {
        var m = machine()
        XCTAssertEqual(m.keyDown(KeyCode.tab, modifiers: .command, characters: nil), .pass)
        XCTAssertEqual(m.keyDown(KeyCode.tab, modifiers: .option, characters: nil), .consume([.open(.shortcut(0), reverse: false)]))
        XCTAssertEqual(m.keyDown(KeyCode.tab, modifiers: .option, characters: nil), .consume([.next]))
        XCTAssertEqual(m.keyDown(KeyCode.tab, modifiers: [.option, .shift], characters: nil), .consume([.previous]))
        XCTAssertEqual(m.flagsChanged([.option, .shift]), [])
        XCTAssertEqual(m.flagsChanged([]), [.release])
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(m.keyUp(KeyCode.tab), .consume([]))
        XCTAssertEqual(m.keyUp(KeyCode.tab), .pass)
    }

    func testReverseOpenSwitchShortcutAndControls() {
        var m = machine()
        XCTAssertEqual(m.keyDown(KeyCode.tab, modifiers: [.option, .shift], characters: nil), .consume([.open(.shortcut(0), reverse: true)]))
        XCTAssertEqual(m.keyDown(KeyCode.grave, modifiers: .option, characters: nil), .consume([.open(.shortcut(1), reverse: false)]))
        XCTAssertEqual(m.keyDown(KeyCode.w, modifiers: .option, characters: "w"), .consume([.control(.closeWindow)]))
        XCTAssertEqual(m.keyDown(KeyCode.right, modifiers: .option, characters: nil), .consume([.move(.right)]))
        XCTAssertEqual(m.keyDown(KeyCode.escape, modifiers: .option, characters: nil), .consume([.control(.cancel)]))
        XCTAssertFalse(m.isActive)
    }

    func testSearchKeepsSwitcherOpenAfterRelease() {
        var m = machine()
        _ = m.keyDown(KeyCode.tab, modifiers: .option, characters: nil)
        XCTAssertEqual(m.keyDown(KeyCode.s, modifiers: .option, characters: "s"), .consume([.control(.search)]))
        XCTAssertEqual(m.flagsChanged([]), [])
        XCTAssertEqual(m.keyDown(KeyCode.w, modifiers: [], characters: "w"), .consume([.searchInput("w")]))
        XCTAssertEqual(m.keyDown(KeyCode.delete, modifiers: [], characters: "\u{8}"), .consume([.searchBackspace]))
        XCTAssertEqual(m.keyDown(KeyCode.returnKey, modifiers: [], characters: "\r"), .consume([.control(.focus)]))
        XCTAssertFalse(m.isActive)
    }

    func testIgnoredApp() {
        var m = machine()
        m.ignoringShortcuts = true
        XCTAssertEqual(m.keyDown(KeyCode.tab, modifiers: .option, characters: nil), .pass)
    }
}

final class SearchAndLayoutTests: XCTestCase {
    func testFuzzySearch() {
        XCTAssertNotNil(FuzzySearch.score(query: "sfr", in: "Safari — Réglages"))
        XCTAssertNotNil(FuzzySearch.score(query: "regl", in: "Safari — Réglages"))
        XCTAssertNil(FuzzySearch.score(query: "xyz", in: "Safari"))
        let a = SwitcherEntry.window(WindowSnapshot(id: 1, pid: 1, appName: "Mail", title: "Boîte de réception"))
        let b = SwitcherEntry.window(WindowSnapshot(id: 2, pid: 2, appName: "Safari", title: "Mail web"))
        XCTAssertEqual(FuzzySearch.filter([a, b], query: "mail").first?.key, "w1")
    }

    func testLayoutWrapsAndNavigates() {
        let layout = SwitcherLayout.compute(style: .thumbnails, size: .medium, screen: CGSize(width: 1000, height: 800),
                                            aspectRatios: Array(repeating: 1.6, count: 10))
        XCTAssertGreaterThan(layout.rows.count, 1)
        XCTAssertLessThanOrEqual(layout.contentSize.width, 1000 * 0.9)
        XCTAssertEqual(layout.neighbour(of: 0, .left), 9)
        let below = layout.neighbour(of: 0, .down)
        XCTAssertEqual(layout.row(of: below), 1)
        let auto = SwitcherLayout.compute(style: .thumbnails, size: .auto, screen: CGSize(width: 2000, height: 1200), aspectRatios: [1.6, 1.6])
        XCTAssertEqual(auto.metrics.mainSize, SwitcherLayout.metrics(style: .thumbnails, size: .large, screen: CGSize(width: 2000, height: 1200), showTitles: true).mainSize)
    }

    func testConfigRoundTripAndTolerantDecoding() throws {
        var config = Config()
        config.appearance.style = .appIcons
        config.controls[.search] = nil
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: data), config)
        let partial = try JSONDecoder().decode(Config.self, from: Data(#"{"vimKeys":true,"appearance":{"size":"large"}}"#.utf8))
        XCTAssertTrue(partial.vimKeys)
        XCTAssertEqual(partial.appearance.size, .large)
        XCTAssertEqual(partial.shortcuts.count, 2)
    }
}
