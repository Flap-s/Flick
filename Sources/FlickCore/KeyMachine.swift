import Foundation

public enum SwitcherSource: Equatable, Sendable {
    case shortcut(Int)
    case gesture
    case manual
}

public enum SwitcherCommand: Equatable, Sendable {
    case open(SwitcherSource, reverse: Bool)
    case next
    case previous
    case move(Direction)
    /// The shortcut's modifiers were released: focus the selection.
    case release
    case control(ControlAction)
    case searchInput(String)
    case searchBackspace
    case searchEnd
}

/// Decides, for each keyboard event, whether Flick consumes it and what the switcher should do. It runs inside the
/// event tap, so it is pure and synchronous; the app feeds it the configuration and reads back commands.
public struct KeyMachine: Sendable {
    public struct Trigger: Equatable, Sendable {
        public var hold: Modifiers
        public var keyCode: UInt16
        public var releaseAction: ReleaseAction

        public init(hold: Modifiers, keyCode: UInt16, releaseAction: ReleaseAction) {
            self.hold = hold
            self.keyCode = keyCode
            self.releaseAction = releaseAction
        }
    }

    public struct Settings: Equatable, Sendable {
        public var triggers: [Trigger] = []
        public var previousModifier: Modifiers = .shift
        public var controls: [UInt16: ControlAction] = [:]
        public var arrowKeys = true
        public var vimKeys = false

        public init() {}

        public init(_ config: Config) {
            triggers = config.shortcuts.map { Trigger(hold: $0.hold, keyCode: $0.keyCode, releaseAction: $0.releaseAction) }
            previousModifier = config.previousModifier
            for (action, code) in config.controls { controls[code] = action }
            arrowKeys = config.arrowKeys
            vimKeys = config.vimKeys
        }
    }

    struct Session: Equatable, Sendable {
        var trigger: Int?
        var hold: Modifiers
        var releaseAction: ReleaseAction
    }

    public var settings: Settings
    /// Set by the app when the frontmost app is excluded from Flick's shortcuts.
    public var ignoringShortcuts = false
    private(set) var session: Session?
    public private(set) var holding = false
    public private(set) var searching = false
    private var swallowedKeys: Set<UInt16> = []

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public var isActive: Bool { session != nil }

    public enum Outcome: Equatable, Sendable {
        case pass
        case consume([SwitcherCommand])
    }

    /// `characters` is what the key types on the current layout with Shift only, for search.
    public mutating func keyDown(_ keyCode: UInt16, modifiers: Modifiers, characters: String?) -> Outcome {
        guard let current = session else {
            guard !ignoringShortcuts else { return .pass }
            for (index, t) in settings.triggers.enumerated() where t.keyCode == keyCode && !t.hold.isEmpty {
                let reverse = !t.hold.contains(settings.previousModifier) && modifiers == t.hold.union(settings.previousModifier)
                guard modifiers == t.hold || reverse else { continue }
                session = Session(trigger: index, hold: t.hold, releaseAction: t.releaseAction)
                holding = true
                swallowedKeys.insert(keyCode)
                return .consume([.open(.shortcut(index), reverse: reverse)])
            }
            return .pass
        }

        swallowedKeys.insert(keyCode)
        let backwards = modifiers.contains(settings.previousModifier)
            && !(current.hold.contains(settings.previousModifier))
        let step: SwitcherCommand = backwards ? .previous : .next
        let isOwnTrigger = current.trigger.map { settings.triggers.indices.contains($0) && settings.triggers[$0].keyCode == keyCode } ?? false

        if searching {
            switch keyCode {
            case KeyCode.returnKey, KeyCode.keypadEnter: return finish(.control(.focus))
            case KeyCode.escape:
                searching = false
                return .consume([.searchEnd])
            case KeyCode.delete, KeyCode.forwardDelete: return .consume([.searchBackspace])
            default: break
            }
            if let direction = KeyCode.arrows[keyCode] { return .consume([.move(direction)]) }
            if isOwnTrigger { return .consume([step]) }
            if let characters, !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                return .consume([.searchInput(characters)])
            }
            return .consume([])
        }

        if isOwnTrigger { return .consume([step]) }
        // Another shortcut pressed while holding: switch to its list.
        if holding {
            let base = modifiers.subtracting(current.hold.contains(settings.previousModifier) ? [] : settings.previousModifier)
            for (index, t) in settings.triggers.enumerated() where t.keyCode == keyCode && t.hold == base && index != current.trigger {
                session = Session(trigger: index, hold: t.hold, releaseAction: t.releaseAction)
                return .consume([.open(.shortcut(index), reverse: base != modifiers)])
            }
        }
        if settings.arrowKeys, let direction = KeyCode.arrows[keyCode] { return .consume([.move(direction)]) }
        if settings.vimKeys, let direction = KeyCode.vim[keyCode] { return .consume([.move(direction)]) }
        if keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter { return finish(.control(.focus)) }
        if let action = settings.controls[keyCode] {
            switch action {
            case .focus, .cancel: return finish(.control(action))
            case .search: searching = true
            default: break
            }
            return .consume([.control(action)])
        }
        return .consume([])
    }

    public mutating func keyUp(_ keyCode: UInt16) -> Outcome {
        if swallowedKeys.remove(keyCode) != nil || session != nil { return .consume([]) }
        return .pass
    }

    public mutating func flagsChanged(_ modifiers: Modifiers) -> [SwitcherCommand] {
        guard let current = session, holding, !modifiers.isSuperset(of: current.hold) else { return [] }
        holding = false
        guard !searching, current.releaseAction == .focusSelected else { return [] }
        session = nil
        return [.release]
    }

    /// A switcher opened by a gesture or from the menu: keys act on it, but releasing modifiers doesn't.
    public mutating func beginExternal(_ source: SwitcherSource) {
        session = Session(trigger: nil, hold: [], releaseAction: .doNothing)
        holding = false
        searching = false
    }

    /// The app closed the switcher by itself (click, gesture end, window gone…).
    public mutating func end() {
        session = nil
        holding = false
        searching = false
    }

    private mutating func finish(_ command: SwitcherCommand) -> Outcome {
        session = nil
        holding = false
        searching = false
        return .consume([command])
    }
}
