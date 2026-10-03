import Cocoa

final class OverlayWindow: NSWindow {
    let zone: LayoutZone
    private let zoneView: OverlayZoneView

    init(zone: LayoutZone, isTrigger: Bool = false, opacity: CGFloat = 0.12) {
        self.zone = zone
        self.zoneView = OverlayZoneView(name: zone.name, isTrigger: isTrigger, opacity: opacity)
        super.init(
            contentRect: isTrigger ? zone.triggerFrame : zone.previewFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = zoneView
    }

    func setHighlighted(_ highlighted: Bool) {
        zoneView.highlighted = highlighted
    }
}

final class OverlayZoneView: NSView {
    private let name: String
    private let isTrigger: Bool
    private let opacity: CGFloat

    var highlighted: Bool = false {
        didSet { needsDisplay = true }
    }

    init(name: String, isTrigger: Bool = false, opacity: CGFloat = 0.12) {
        self.name = name
        self.isTrigger = isTrigger
        self.opacity = opacity
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 5, dy: 5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        let fillAlpha: CGFloat = isTrigger ? (highlighted ? 0.8 : 0.55) : (highlighted ? min(0.6, opacity * 2) : opacity)
        let strokeAlpha: CGFloat = highlighted ? 0.95 : 0.65
        let color = isTrigger ? NSColor.systemTeal : NSColor.systemBlue
        color.withAlphaComponent(fillAlpha).setFill()
        path.fill()

        path.lineWidth = isTrigger ? 2 : (highlighted ? 5 : 3)
        color.withAlphaComponent(strokeAlpha).setStroke()
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = CGSize(width: 0, height: -1)

        let fontSize: CGFloat = isTrigger ? 13 : 22
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]

        let text = name as NSString
        let availableWidth = max(1, bounds.width - 20)
        let measuredWidth = text.size(withAttributes: attrs).width
        if measuredWidth > availableWidth {
            attrs[.font] = NSFont.systemFont(ofSize: fontSize * availableWidth / measuredWidth, weight: .bold)
        }
        let textHeight = text.size(withAttributes: attrs).height
        let textRect = CGRect(
            x: bounds.minX + 10,
            y: bounds.midY - textHeight / 2,
            width: bounds.width - 20,
            height: textHeight
        )
        text.draw(in: textRect, withAttributes: attrs)
    }
}
