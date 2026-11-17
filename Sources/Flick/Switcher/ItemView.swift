import AppKit
import FlickCore

/// Everything an item view shows, resolved by the controller.
struct ItemModel {
    var key: String
    var title: String
    var icon: NSImage?
    var thumbnail: CGImage?
    var isWindowless = false
    var isMinimized = false
    var isHidden = false
    var isFullscreen = false
    var isOnAllSpaces = false
    var spaceNumber: Int?
    var badge: String?
    var hasWindowControls = false
}

enum WindowControl {
    case close, minimize, fullscreen
}

/// One cell of the switcher.
final class ItemView: NSView {
    private let highlight = CALayer()
    private let thumbnailLayer = CALayer()
    private let iconLayer = CALayer()
    /// Stands in for the thumbnail when there is no picture (minimized, no permission, app without window).
    private let placeholderLayer = CALayer()
    private let titleField = NSTextField(labelWithString: "")
    private let statusStack = NSStackView()
    private let badgeView = BadgeView()
    private var controlButtons: [TrafficLightButton] = []
    private(set) var model = ItemModel(key: "", title: "")
    private var style: Style = .thumbnails
    private var metrics = SwitcherLayout.metrics(style: .thumbnails, size: .medium, screen: CGSize(width: 1440, height: 900), showTitles: true)
    private var appearanceSettings = Appearance()

    var onControl: ((WindowControl) -> Void)?

    var isSelected = false { didSet { if isSelected != oldValue { updateHighlight() } } }
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateHighlight()
            updateControls()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        highlight.cornerRadius = 10
        highlight.cornerCurve = .continuous
        layer?.addSublayer(highlight)

        thumbnailLayer.contentsGravity = .resizeAspect
        thumbnailLayer.minificationFilter = .trilinear
        thumbnailLayer.shadowOpacity = 0.25
        thumbnailLayer.shadowRadius = 3
        thumbnailLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(thumbnailLayer)

        iconLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(iconLayer)
        placeholderLayer.contentsGravity = .resizeAspect
        placeholderLayer.opacity = 0.9
        layer?.addSublayer(placeholderLayer)

        titleField.font = .systemFont(ofSize: 13)
        titleField.textColor = .labelColor
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        addSubview(titleField)

        statusStack.orientation = .horizontal
        statusStack.spacing = 3
        addSubview(statusStack)
        addSubview(badgeView)

        for control in [WindowControl.close, .minimize, .fullscreen] {
            let button = TrafficLightButton(control: control)
            button.onPress = { [weak self] in self?.onControl?(control) }
            button.isHidden = true
            controlButtons.append(button)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ model: ItemModel, style: Style, metrics: SwitcherLayout.Metrics, appearance: Appearance) {
        self.model = model
        self.style = style
        self.metrics = metrics
        self.appearanceSettings = appearance
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        iconLayer.contentsScale = scale
        thumbnailLayer.contentsScale = scale
        iconLayer.contents = model.icon.map { $0.layerContents(forContentsScale: scale) }
        placeholderLayer.contentsScale = scale
        placeholderLayer.contents = iconLayer.contents
        setThumbnail(model.thumbnail)

        titleField.stringValue = model.title
        titleField.lineBreakMode = switch appearance.truncation {
        case .start: .byTruncatingHead
        case .middle: .byTruncatingMiddle
        case .end: .byTruncatingTail
        }
        titleField.font = style == .appIcons ? .systemFont(ofSize: 11) : .systemFont(ofSize: style == .titles ? 13 : 12.5)
        titleField.alignment = style == .appIcons ? .center : .left
        titleField.textColor = model.isWindowless ? .secondaryLabelColor : .labelColor
        titleField.isHidden = style == .appIcons && !appearance.showTitles

        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !appearance.hideStatusIcons {
            if model.isMinimized { statusStack.addArrangedSubview(Self.symbol("minus.circle.fill", tr("Fenêtre réduite", "Minimized window"))) }
            if model.isHidden { statusStack.addArrangedSubview(Self.symbol("eye.slash.fill", tr("App masquée", "Hidden app"))) }
            if model.isFullscreen { statusStack.addArrangedSubview(Self.symbol("arrow.up.left.and.arrow.down.right.circle.fill", tr("Plein écran", "Full screen"))) }
            if model.isWindowless { statusStack.addArrangedSubview(Self.symbol("circle.dashed", tr("Aucune fenêtre ouverte", "No open window"))) }
        }
        if !appearance.hideSpaceLabels {
            if model.isOnAllSpaces {
                statusStack.addArrangedSubview(Self.symbol("square.on.square.fill", tr("Sur tous les Spaces", "On every Space")))
            } else if let number = model.spaceNumber, WindowTrackerSpacesInfo.hasSeveralSpaces {
                statusStack.addArrangedSubview(SpaceLabel(number: number))
            }
        }
        badgeView.text = appearance.showBadges ? model.badge : nil
        updateHighlight()
        updateControls()
        needsLayout = true
    }

    func setThumbnail(_ image: CGImage?) {
        model.thumbnail = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbnailLayer.contents = image
        thumbnailLayer.isHidden = style != .thumbnails || image == nil
        placeholderLayer.isHidden = style != .thumbnails || image != nil
        CATransaction.commit()
        needsLayout = true
    }

    func setBadge(_ badge: String?) {
        model.badge = badge
        badgeView.text = appearanceSettings.showBadges ? badge : nil
        needsLayout = true
    }

    private static func symbol(_ name: String, _ description: String) -> NSView {
        let view = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(config)
        view.contentTintColor = .secondaryLabelColor
        view.toolTip = description
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    private func updateHighlight() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isSelected {
            highlight.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            highlight.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            highlight.borderWidth = 2
        } else if isHovered {
            highlight.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            highlight.borderWidth = 0
        } else {
            highlight.backgroundColor = nil
            highlight.borderWidth = 0
        }
        CATransaction.commit()
    }

    private func updateControls() {
        let show = isHovered && model.hasWindowControls && !appearanceSettings.hideWindowControls && style == .thumbnails
        for button in controlButtons {
            button.isHidden = !show
            if button.control == .minimize { button.isActive = !model.isFullscreen }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        highlight.frame = bounds
        let p = metrics.cellPadding
        let statusSize = statusStack.fittingSize
        switch style {
        case .thumbnails:
            let icon = metrics.iconSize
            let headerY = p + (metrics.titleHeight - icon) / 2
            iconLayer.frame = CGRect(x: p, y: headerY, width: icon, height: icon)
            let statusX = bounds.width - p - statusSize.width
            statusStack.frame = CGRect(x: statusX, y: p + (metrics.titleHeight - statusSize.height) / 2,
                                       width: statusSize.width, height: statusSize.height)
            let titleX = p + icon + 6
            let titleHeight = titleField.fittingSize.height
            titleField.frame = CGRect(x: titleX, y: p + (metrics.titleHeight - titleHeight) / 2,
                                      width: max(0, statusX - titleX - 4), height: titleHeight)
            let area = CGRect(x: p, y: p + metrics.titleHeight + 6, width: bounds.width - 2 * p, height: metrics.mainSize)
            if let image = model.thumbnail {
                // Fit the image so the shadow hugs it.
                let ratio = CGFloat(image.width) / CGFloat(max(image.height, 1))
                var w = area.width, h = area.width / ratio
                if h > area.height { h = area.height; w = h * ratio }
                thumbnailLayer.frame = CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h).integral
            } else {
                let side = min(area.width, area.height) * 0.55
                thumbnailLayer.frame = .zero
                placeholderLayer.frame = CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side)
            }
            badgeView.frame = badgeFrame(around: iconLayer.frame)
            var x = (model.thumbnail != nil ? thumbnailLayer.frame.minX : area.minX) + 6
            let y = (model.thumbnail != nil ? thumbnailLayer.frame.minY : area.minY) + 6
            for button in controlButtons {
                button.frame = CGRect(x: x, y: y, width: 14, height: 14)
                x += 20
            }
        case .appIcons:
            let side = metrics.mainSize
            iconLayer.frame = CGRect(x: (bounds.width - side) / 2, y: p, width: side, height: side)
            badgeView.frame = badgeFrame(around: iconLayer.frame)
            statusStack.frame = CGRect(x: iconLayer.frame.minX, y: iconLayer.frame.maxY - statusSize.height,
                                       width: statusSize.width, height: statusSize.height)
            let titleHeight = titleField.fittingSize.height
            titleField.frame = CGRect(x: 4, y: p + side + 4, width: bounds.width - 8, height: titleHeight)
        case .titles:
            let icon = metrics.iconSize
            iconLayer.frame = CGRect(x: p, y: (bounds.height - icon) / 2, width: icon, height: icon)
            badgeView.frame = badgeFrame(around: iconLayer.frame)
            let statusX = bounds.width - p - statusSize.width
            statusStack.frame = CGRect(x: statusX, y: (bounds.height - statusSize.height) / 2, width: statusSize.width, height: statusSize.height)
            let titleX = p + icon + 8
            let titleHeight = titleField.fittingSize.height
            titleField.frame = CGRect(x: titleX, y: (bounds.height - titleHeight) / 2, width: max(0, statusX - titleX - 6), height: titleHeight)
        }
    }

    private func badgeFrame(around icon: CGRect) -> CGRect {
        let size = badgeView.fittingSize
        let height = max(14, min(20, icon.height * 0.38))
        let width = max(height, size.width * height / 18)
        return CGRect(x: icon.maxX - width * 0.7, y: icon.minY - height * 0.25, width: width, height: height)
    }
}

/// Enough to tell whether Space numbers are worth showing.
@MainActor
enum WindowTrackerSpacesInfo {
    static var hasSeveralSpaces = false
}

/// The red count apps show on their Dock icon.
final class BadgeView: NSView {
    var text: String? {
        didSet {
            isHidden = text == nil
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let w = attributed.size().width + 10
        return NSSize(width: max(18, w), height: 18)
    }

    private var attributed: NSAttributedString {
        let fontSize = max(9, bounds.height * 0.62)
        return NSAttributedString(string: text ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize == 0 ? 11 : fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let text, !text.isEmpty else { return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.systemRed.setFill()
        path.fill()
        let s = attributed
        let size = s.size()
        s.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// "2" in a rounded box: the window's Space.
final class SpaceLabel: NSView {
    private let number: Int

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        toolTip = tr("Fenêtre sur le Space \(number)", "Window on Space \(number)")
    }

    required init?(coder: NSCoder) { fatalError() }

    private var text: NSAttributedString {
        NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    override var intrinsicContentSize: NSSize { NSSize(width: max(15, text.size().width + 8), height: 15) }
    override var fittingSize: NSSize { intrinsicContentSize }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.secondaryLabelColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        let s = text
        let size = s.size()
        s.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// Close / minimize / fullscreen circles shown over a hovered thumbnail.
final class TrafficLightButton: NSView {
    let control: WindowControl
    var onPress: (() -> Void)?
    var isActive = true { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    init(control: WindowControl) {
        self.control = control
        super.init(frame: .zero)
        toolTip = switch control {
        case .close: tr("Fermer la fenêtre", "Close window")
        case .minimize: tr("Réduire la fenêtre", "Minimize window")
        case .fullscreen: tr("Plein écran", "Full screen")
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        onPress?()
    }

    override func draw(_ dirtyRect: NSRect) {
        var color: NSColor = switch control {
        case .close: NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)
        case .minimize: NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1)
        case .fullscreen: NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)
        }
        if !isActive { color = .systemGray }
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        guard hovering, isActive else { return }
        let name = switch control {
        case .close: "xmark"
        case .minimize: "minus"
        case .fullscreen: "arrow.up.left.and.arrow.down.right"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .black)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tinted = image.tinted(NSColor.black.withAlphaComponent(0.6))
            let size = tinted.size
            tinted.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }
}
