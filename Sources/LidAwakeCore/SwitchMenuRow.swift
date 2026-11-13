import AppKit

/// The compact title's cell. AppKit draws a label's text this far inside the cell's frame and reports a cell size
/// that includes it on both sides, so a label framed to the string width would truncate and start its ink late.
/// This cell removes that inset, so the frame is the text rectangle.
private final class TitleCell: NSTextFieldCell {
    private static let textInset: CGFloat = 2

    override var cellSize: NSSize { Self.trimmed(super.cellSize) }
    override func cellSize(forBounds rect: NSRect) -> NSSize { Self.trimmed(super.cellSize(forBounds: rect)) }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: cellFrame.insetBy(dx: -Self.textInset, dy: 0), in: controlView)
    }

    private static func trimmed(_ size: NSSize) -> NSSize { NSSize(width: size.width - 2 * textInset, height: size.height) }
}

private final class TitleField: NSTextField {
    override class var cellClass: AnyClass? { get { TitleCell.self } set {} }
}

/// A persistent menu row with a native, accessible on/off switch. The regular layout is the two-line
/// header; the compact layout is a one-line row that sits among standard rows and keeps the menu open.
final class SwitchMenuRow: NSView {
    enum Layout { case regular, compact }

    private enum Compact {
        static let height: CGFloat = 24
        static let inset: (withStateColumn: CGFloat, without: CGFloat) = (24, 16)
        static let indentStep: CGFloat = 12
        static let iconColumn: CGFloat = 19
        static let iconGap: CGFloat = 6.5
        static let iconNudge: CGFloat = 1.25
        static let titleToSwitch: CGFloat = 16
        static let switchSize = NSSize(width: 32, height: 18)
        static let switchTrailing: CGFloat = 14
    }

    let rowLayout: Layout
    private weak var item: NSMenuItem?
    private let label: NSTextField
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    let toggle = NSSwitch()
    /// A user operation is running. Set by `StableMenu`; the row keeps its look, only the knob is held.
    var operationInFlight = false
    /// The position a click asked for, kept until the operation ends.
    private var requestedState: NSControl.StateValue?
    private var fitIndent = 0

    init(item: NSMenuItem, layout: Layout = .regular) {
        self.item = item
        self.rowLayout = layout
        self.label = layout == .compact ? TitleField(labelWithString: "") : NSTextField(labelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: layout == .compact ? Compact.height : 64))
        autoresizingMask = [.width]
        if layout == .compact { setUpCompact() } else { setUpRegular() }
        update()
    }

    private func setUpRegular() {
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.setAccessibilityElement(false)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .labelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        statusIcon.contentTintColor = .labelColor
        statusIcon.setAccessibilityElement(false)
        toggle.controlSize = .regular
        toggle.target = self
        toggle.action = #selector(switchChanged)
        for view in [label, subtitleLabel, statusIcon, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -16),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            statusIcon.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 16),
            statusIcon.heightAnchor.constraint(equalToConstant: 16),
            statusIcon.centerYAnchor.constraint(equalTo: subtitleLabel.centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 6),
            subtitleLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14)
        ])
    }

    private func setUpCompact() {
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        statusIcon.imageScaling = .scaleNone
        statusIcon.imageAlignment = .alignCenter
        statusIcon.setAccessibilityElement(false)
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = #selector(switchChanged)
        for view in [label, statusIcon, toggle] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Whether the menu shows a state column; the compact row aligns its content with the plain titles.
    var hasStateColumn = false {
        didSet { if hasStateColumn != oldValue { needsLayout = true } }
    }

    func updateStatus(subtitle: String, image: NSImage?) {
        if rowLayout == .regular, subtitleLabel.stringValue != subtitle { subtitleLabel.stringValue = subtitle }
        if statusIcon.image !== image {
            statusIcon.image = image
            fitWidth()
        }
    }

    // The width the compact row needs at the larger inset, so a later inset change never needs a new width.
    private func fitWidth() {
        guard rowLayout == .compact, let item = item else { return }
        let title = titleWidth(of: item)
        let width = ceil(Compact.inset.withStateColumn + indent(of: item) + iconColumn + title
                         + Compact.titleToSwitch + Compact.switchSize.width + Compact.switchTrailing)
        if frame.width != width { setFrameSize(NSSize(width: width, height: frame.height)) }
        needsLayout = true
    }

    private func titleWidth(of item: NSMenuItem) -> CGFloat {
        ceil((item.title as NSString).size(withAttributes: [.font: label.font as Any]).width)
    }

    private func indent(of item: NSMenuItem) -> CGFloat { CGFloat(item.indentationLevel) * Compact.indentStep }

    private var iconColumn: CGFloat { statusIcon.image == nil ? 0 : Compact.iconColumn + Compact.iconGap }

    override func layout() {
        super.layout()
        guard rowLayout == .compact, let item = item else { return }
        let height = bounds.height
        let switchFrame = NSRect(x: bounds.width - Compact.switchTrailing - Compact.switchSize.width,
                                 y: (height - Compact.switchSize.height) / 2,
                                 width: Compact.switchSize.width, height: Compact.switchSize.height)
        if toggle.frame != switchFrame { toggle.frame = switchFrame }
        let contentX = (hasStateColumn ? Compact.inset.withStateColumn : Compact.inset.without) + indent(of: item)
        let iconFrame = NSRect(x: contentX + Compact.iconNudge, y: 0, width: Compact.iconColumn, height: height)
        if statusIcon.frame != iconFrame { statusIcon.frame = iconFrame }
        let titleX = contentX + iconColumn
        let textHeight = ceil(label.intrinsicContentSize.height)
        let titleFrame = NSRect(x: titleX, y: (height - textHeight) / 2,
                                width: max(0, min(titleWidth(of: item), switchFrame.minX - Compact.titleToSwitch - titleX)),
                                height: textHeight)
        if label.frame != titleFrame { label.frame = titleFrame }
    }

    func update() {
        guard let item = item else { return }
        if label.stringValue != item.title {
            label.stringValue = item.title
            toggle.setAccessibilityLabel(item.title)
            fitWidth()
        }
        if rowLayout == .compact, fitIndent != item.indentationLevel {
            fitIndent = item.indentationLevel
            fitWidth()
        }
        if toggle.isEnabled != item.isEnabled { toggle.isEnabled = item.isEnabled }
        // A click animates immediately. While the operation runs, keep that position; when it ends the
        // knob shows the item's state: the new one on success, the old one on failure or a rejected click.
        if !operationInFlight { requestedState = nil }
        let shown = operationInFlight ? requestedState ?? item.state : item.state
        if toggle.state != shown { toggle.state = shown }
        let color = item.isEnabled ? NSColor.labelColor : .disabledControlTextColor
        if label.textColor != color { label.textColor = color }
        if rowLayout == .compact {
            if statusIcon.contentTintColor != color { statusIcon.contentTintColor = color }
            return
        }
        let hint = item.keyEquivalent.isEmpty ? item.title : "\(item.title) (⌘\(item.keyEquivalent.uppercased()))"
        if toolTip != hint { toolTip = hint }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // The status line is informational; only the title/switch area toggles.
        guard bounds.contains(point) else { return }
        if rowLayout == .regular, point.y < bounds.height - 34 { return }
        toggle.performClick(nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === label || (rowLayout == .compact && hit === statusIcon) ? self : hit
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        // A click during an operation neither starts another nor moves the knob.
        guard let item = item, item.isEnabled, !operationInFlight, let action = item.action else { update(); return }
        requestedState = toggle.state
        NSApplication.shared.sendAction(action, to: item.target, from: sender)
        // Setup may have been canceled without starting an operation.
        update()
    }
}
