import AppKit
import FlickCore

/// The floating switcher. It never becomes key or activates Flick, so the app in front keeps its focus; the
/// keyboard is handled by the event tap and the mouse here.
final class SwitcherPanel: NSPanel {
    private let effect = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let grid = GridView()
    private let searchBar = SearchBar()
    private let hintField = NSTextField(labelWithString: "")
    private var itemViews: [ItemView] = []
    private(set) var layoutInfo = SwitcherLayout.compute(style: .thumbnails, size: .medium, screen: CGSize(width: 1440, height: 900), aspectRatios: [])
    private var appearanceSettings = Appearance()
    private var mouseHoverSelects = true

    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onControl: ((Int, WindowControl) -> Void)?

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 18)
        contentView = effect

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = grid
        scrollView.contentView.drawsBackground = false
        effect.addSubview(scrollView)
        effect.addSubview(searchBar)

        hintField.font = .systemFont(ofSize: 11)
        hintField.textColor = .tertiaryLabelColor
        hintField.alignment = .center
        effect.addSubview(hintField)

        grid.onMove = { [weak self] point in self?.mouseMoved(to: point) }
        grid.onExit = { [weak self] in self?.setHovered(nil) }
        grid.onClick = { [weak self] point in
            guard let self, let index = self.index(at: point) else { return }
            self.onClick?(index)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Content

    struct Content {
        var items: [ItemModel]
        var aspectRatios: [CGFloat]
        var selected: Int
        var searching: Bool
        var query: String
        var hint: String?
    }

    /// Lays out and shows `content` on `screen` (centred on its visible frame).
    func show(_ content: Content, appearance: Appearance, mouseHover: Bool, on screen: NSScreen) {
        appearanceSettings = appearance
        mouseHoverSelects = mouseHover
        self.appearance = switch appearance.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }

        let visible = screen.visibleFrame
        let titleWidths = appearance.style == .titles ? content.items.map { Self.titleWidth($0.title) } : []
        var layout = SwitcherLayout.compute(style: appearance.style, size: appearance.size, screen: visible.size,
                                            aspectRatios: content.aspectRatios, titleWidths: titleWidths,
                                            showTitles: appearance.showTitles)
        if appearance.alignment == .leading { layout = layout.leftAligned() }
        layoutInfo = layout

        // Reuse views.
        while itemViews.count < content.items.count {
            let view = ItemView(frame: .zero)
            let index = itemViews.count
            view.onControl = { [weak self] control in self?.onControl?(index, control) }
            itemViews.append(view)
            grid.addSubview(view)
        }
        for (i, view) in itemViews.enumerated() {
            guard i < content.items.count else {
                view.isHidden = true
                continue
            }
            view.isHidden = false
            view.frame = layout.cells[i]
            view.configure(content.items[i], style: appearance.style, metrics: layout.metrics, appearance: appearance)
            view.isSelected = i == content.selected
            view.isHovered = false
        }

        let pad = SwitcherLayout.panelPadding
        let searchHeight: CGFloat = content.searching ? 36 : 0
        let hintHeight: CGFloat = content.hint != nil && !content.searching ? 18 : 0
        let minWidth: CGFloat = content.searching ? 420 : 0
        let gridWidth = max(layout.contentSize.width, minWidth - 2 * pad)
        let size = CGSize(width: gridWidth + 2 * pad,
                          height: layout.viewportSize.height + 2 * pad + searchHeight + hintHeight)
        grid.frame = CGRect(x: 0, y: 0, width: gridWidth, height: layout.contentSize.height)
        if gridWidth > layout.contentSize.width {
            for (i, view) in itemViews.enumerated() where i < content.items.count {
                view.frame.origin.x += ((gridWidth - layout.contentSize.width) / 2).rounded()
            }
        }

        searchBar.isHidden = !content.searching
        searchBar.query = content.query
        searchBar.frame = CGRect(x: pad, y: size.height - pad - searchHeight + 6, width: size.width - 2 * pad, height: 28)
        hintField.isHidden = hintHeight == 0
        hintField.stringValue = content.hint ?? ""
        hintField.frame = CGRect(x: pad, y: pad / 2 - 2, width: size.width - 2 * pad, height: 16)
        scrollView.frame = CGRect(x: pad, y: pad + hintHeight * 0.6, width: gridWidth, height: layout.viewportSize.height)

        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        setFrame(CGRect(origin: origin, size: size), display: true)
        scrollToSelected(content.selected)
    }

    func updateSearch(query: String) {
        searchBar.query = query
    }

    private static func titleWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
    }

    func select(_ index: Int) {
        for (i, view) in itemViews.enumerated() { view.isSelected = i == index }
        scrollToSelected(index)
    }

    private func scrollToSelected(_ index: Int) {
        guard layoutInfo.cells.indices.contains(index), layoutInfo.contentSize.height > layoutInfo.viewportSize.height else { return }
        grid.scrollToVisible(layoutInfo.cells[index].insetBy(dx: 0, dy: -8))
    }

    func updateThumbnail(at index: Int, _ image: CGImage?) {
        guard itemViews.indices.contains(index), !itemViews[index].isHidden else { return }
        itemViews[index].setThumbnail(image)
    }

    func updateBadge(at index: Int, _ badge: String?) {
        guard itemViews.indices.contains(index), !itemViews[index].isHidden else { return }
        itemViews[index].setBadge(badge)
    }

    // MARK: Mouse

    private func index(at point: CGPoint) -> Int? {
        itemViews.indices.first { !itemViews[$0].isHidden && itemViews[$0].frame.contains(point) }
    }

    private func mouseMoved(to point: CGPoint) {
        let index = index(at: point)
        setHovered(index)
        if let index, mouseHoverSelects { onHover?(index) }
    }

    private func setHovered(_ index: Int?) {
        for (i, view) in itemViews.enumerated() { view.isHovered = i == index }
    }

    func resetHover() { setHovered(nil) }
}

/// Holds the item views and reports the mouse.
final class GridView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?
    var onClick: ((CGPoint) -> Void)?
    /// Mouse moves right after the panel appears come from the pointer resting where it was, not from the user.
    private var lastPoint: CGPoint?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastPoint = nil
    }

    func resetMouse() { lastPoint = nil }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { lastPoint = point }
        guard let last = lastPoint, hypot(point.x - last.x, point.y - last.y) > 0.5 else { return }
        onMove?(point)
    }

    override func mouseEntered(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseExited(with event: NSEvent) { onExit?() }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }
}

/// The search field shown at the top of the switcher. It only displays the query; typing goes through the event tap.
final class SearchBar: NSView {
    private let icon = NSImageView()
    private let field = NSTextField(labelWithString: "")

    var query = "" {
        didSet { update() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: tr("Rechercher", "Search"))
        icon.contentTintColor = .secondaryLabelColor
        addSubview(icon)
        field.font = .systemFont(ofSize: 14)
        field.lineBreakMode = .byTruncatingHead
        addSubview(field)
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func update() {
        field.stringValue = query.isEmpty ? tr("Tapez pour rechercher une fenêtre…", "Type to search for a window…") : query + "▏"
        field.textColor = query.isEmpty ? .tertiaryLabelColor : .labelColor
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        icon.frame = CGRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let h = field.fittingSize.height
        field.frame = CGRect(x: 30, y: (bounds.height - h) / 2, width: bounds.width - 38, height: h)
    }
}

/// The selected window drawn at its real place on screen, under the switcher.
final class PreviewWindow: NSPanel {
    private let imageLayer = CALayer()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        imageLayer.contentsGravity = .resize
        view.layer?.addSublayer(imageLayer)
        contentView = view
    }

    override var canBecomeKey: Bool { false }

    func show(image: CGImage, quartzFrame: CGRect, fadeIn: Bool) {
        let frame = ScreenGeometry.cocoaRect(fromQuartz: quartzFrame)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.frame = CGRect(origin: .zero, size: frame.size)
        CATransaction.commit()
        setFrame(frame, display: false)
        if !isVisible {
            alphaValue = fadeIn ? 0 : 1
            orderFrontRegardless()
            if fadeIn {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    animator().alphaValue = 1
                }
            }
        }
    }

    func hide() {
        orderOut(nil)
    }
}
