import CoreGraphics
import Foundation

/// Places the switcher's cells. Coordinates are top-left based inside the scrollable content; the panel adds its
/// own padding around them.
public struct SwitcherLayout: Equatable, Sendable {
    public struct Metrics: Equatable, Sendable {
        /// Thumbnail height (thumbnails), icon side (app icons) or row height (titles).
        public var mainSize: CGFloat
        public var cellPadding: CGFloat
        public var spacing: CGFloat
        public var titleHeight: CGFloat
        public var iconSize: CGFloat
    }

    public var style: Style
    public var metrics: Metrics
    public var cells: [CGRect]
    public var rows: [[Int]]
    public var contentSize: CGSize
    /// Visible part of the content; smaller than `contentSize` when the list scrolls.
    public var viewportSize: CGSize

    public static let panelPadding: CGFloat = 18

    public static func metrics(style: Style, size: SizeOption, screen: CGSize, showTitles: Bool) -> Metrics {
        let short = min(screen.width, screen.height)
        switch style {
        case .thumbnails:
            let factor: CGFloat = switch size {
            case .small: 0.13
            case .medium, .auto: 0.17
            case .large: 0.23
            }
            return Metrics(mainSize: max(70, (short * factor).rounded()), cellPadding: 8, spacing: 6, titleHeight: 24, iconSize: 20)
        case .appIcons:
            let side: CGFloat = switch size {
            case .small: 54
            case .medium, .auto: 78
            case .large: 108
            }
            return Metrics(mainSize: side, cellPadding: 10, spacing: 4, titleHeight: showTitles ? 18 : 0, iconSize: side)
        case .titles:
            let row: CGFloat = switch size {
            case .small: 26
            case .medium, .auto: 32
            case .large: 40
            }
            return Metrics(mainSize: row, cellPadding: 8, spacing: 2, titleHeight: row, iconSize: row - 8)
        }
    }

    /// - Parameters:
    ///   - aspectRatios: width / height of each window (thumbnails style), 0 when unknown.
    ///   - screen: the visible frame size of the screen showing the switcher.
    ///   - titleWidths: natural width of each title (titles style).
    public static func compute(style: Style, size: SizeOption, screen: CGSize, aspectRatios: [CGFloat],
                               titleWidths: [CGFloat] = [], showTitles: Bool = true) -> SwitcherLayout {
        if size == .auto && style == .thumbnails {
            // The largest size that shows every window without scrolling.
            for candidate in [SizeOption.large, .medium, .small] {
                let layout = compute(style: style, size: candidate, screen: screen, aspectRatios: aspectRatios,
                                     titleWidths: titleWidths, showTitles: showTitles)
                if layout.viewportSize.height >= layout.contentSize.height - 0.5 || candidate == .small { return layout }
            }
        }
        let m = metrics(style: style, size: size, screen: screen, showTitles: showTitles)
        let maxWidth = (screen.width * 0.9 - 2 * panelPadding).rounded(.down)
        let maxHeight = (screen.height * 0.82 - 2 * panelPadding).rounded(.down)

        var widths: [CGFloat] = []
        var cellHeight: CGFloat
        switch style {
        case .thumbnails:
            let h = m.mainSize
            widths = aspectRatios.map { ratio in
                let r = ratio > 0 ? ratio : 1.5
                return (min(max(h * r, h * 0.75), h * 1.85, maxWidth - 2 * m.cellPadding) + 2 * m.cellPadding).rounded()
            }
            cellHeight = m.cellPadding * 2 + m.titleHeight + 6 + h
        case .appIcons:
            let w = m.mainSize + 2 * m.cellPadding + (showTitles ? 16 : 0)
            widths = Array(repeating: w, count: aspectRatios.count)
            cellHeight = m.cellPadding * 2 + m.mainSize + (showTitles ? m.titleHeight + 4 : 0)
        case .titles:
            let natural = titleWidths.max() ?? 300
            let w = min(max(natural + m.iconSize + 3 * m.cellPadding + 40, 380), screen.width * 0.5, maxWidth)
            widths = Array(repeating: w.rounded(), count: aspectRatios.count)
            cellHeight = m.mainSize
        }

        // Fill rows left to right.
        var rows: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for (i, w) in widths.enumerated() {
            let needed = current.isEmpty ? w : x + m.spacing + w
            if !current.isEmpty && (needed > maxWidth || style == .titles) {
                rows.append(current)
                current = [i]
                x = w
            } else {
                current.append(i)
                x = needed
            }
        }
        if !current.isEmpty { rows.append(current) }

        let rowWidths = rows.map { row in row.map { widths[$0] }.reduce(0, +) + CGFloat(max(row.count - 1, 0)) * m.spacing }
        let contentWidth = rowWidths.max() ?? 0
        let contentHeight = rows.isEmpty ? 0 : CGFloat(rows.count) * cellHeight + CGFloat(rows.count - 1) * m.spacing

        var cells = Array(repeating: CGRect.zero, count: widths.count)
        for (r, row) in rows.enumerated() {
            var cx: CGFloat = style == .appIcons || style == .thumbnails ? ((contentWidth - rowWidths[r]) / 2).rounded() : 0
            let y = CGFloat(r) * (cellHeight + m.spacing)
            for i in row {
                cells[i] = CGRect(x: cx, y: y, width: widths[i], height: cellHeight)
                cx += widths[i] + m.spacing
            }
        }
        return SwitcherLayout(style: style, metrics: m, cells: cells, rows: rows,
                              contentSize: CGSize(width: contentWidth, height: contentHeight),
                              viewportSize: CGSize(width: contentWidth, height: min(contentHeight, maxHeight)))
    }

    /// Left-aligns rows instead of centring them.
    public func leftAligned() -> SwitcherLayout {
        var copy = self
        for row in rows {
            guard let first = row.first else { continue }
            let shift = cells[first].minX
            for i in row { copy.cells[i].origin.x -= shift }
        }
        return copy
    }

    public func row(of index: Int) -> Int? { rows.firstIndex { $0.contains(index) } }

    /// The cell reached from `index` by an arrow key, wrapping around at the ends.
    public func neighbour(of index: Int, _ direction: Direction) -> Int {
        let count = cells.count
        guard count > 0, cells.indices.contains(index) else { return 0 }
        switch direction {
        case .left: return (index - 1 + count) % count
        case .right: return (index + 1) % count
        case .up, .down:
            guard let r = row(of: index), rows.count > 1 else {
                return direction == .down ? (index + 1) % count : (index - 1 + count) % count
            }
            let target = direction == .down ? (r + 1) % rows.count : (r - 1 + rows.count) % rows.count
            let midX = cells[index].midX
            return rows[target].min { abs(cells[$0].midX - midX) < abs(cells[$1].midX - midX) } ?? index
        }
    }
}
