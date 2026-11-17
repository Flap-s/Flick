import AppKit

/// Spaces of every display, numbered the way Mission Control shows them (1, 2… across displays).
struct SpacesSnapshot {
    struct Space {
        let id: UInt64
        let number: Int
        let displayUUID: String
        let isFullscreen: Bool
    }

    var spaces: [UInt64: Space] = [:]
    /// The Space currently shown on each display.
    var visible: Set<UInt64> = []

    static func current() -> SpacesSnapshot {
        var snapshot = SpacesSnapshot()
        var number = 0
        for display in Private.managedDisplaySpaces() {
            let uuid = display["Display Identifier"] as? String ?? ""
            if let current = display["Current Space"] as? [String: Any], let id = (current["id64"] as? NSNumber)?.uint64Value {
                snapshot.visible.insert(id)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                number += 1
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                snapshot.spaces[id] = Space(id: id, number: number, displayUUID: uuid, isFullscreen: type == 4)
            }
        }
        return snapshot
    }
}

/// One row of the window server's window list.
struct ServerWindow {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let isOnScreen: Bool
    let alpha: Double

    /// Every window the window server knows, front to back for those on screen.
    static func all() -> [ServerWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            var bounds = CGRect.zero
            if let dict = info[kCGWindowBounds as String] as? NSDictionary {
                bounds = CGRect(dictionaryRepresentation: dict) ?? .zero
            }
            return ServerWindow(id: id, pid: pid, layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                bounds: bounds, isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
    }

    /// Could this be a document window (as opposed to a menu, tooltip or offscreen helper)?
    var looksLikeWindow: Bool { layer == 0 && bounds.width >= 60 && bounds.height >= 40 && alpha > 0.01 }
}

enum ScreenGeometry {
    /// Height of the primary screen, to flip between Quartz (top-left origin) and Cocoa (bottom-left) coordinates.
    @MainActor static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    @MainActor static func cocoaRect(fromQuartz r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    @MainActor static func quartzPoint(fromCocoa p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// Index in `NSScreen.screens` of the screen holding most of a Quartz rect.
    @MainActor static func screenIndex(forQuartz r: CGRect) -> Int? {
        let rect = cocoaRect(fromQuartz: r)
        var best: (Int, CGFloat)?
        for (i, screen) in NSScreen.screens.enumerated() {
            let overlap = screen.frame.intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.1 ?? 0) { best = (i, area) }
        }
        return best?.0
    }
}
