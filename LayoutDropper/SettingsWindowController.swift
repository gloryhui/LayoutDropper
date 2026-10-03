import Cocoa
import ApplicationServices
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    var onRequestAccessibility: (() -> Void)?
    var onRestartMonitoring: (() -> Void)?
    private let store: SettingsStore
    private var observer: NSObjectProtocol?
    private let enabled = NSButton(checkboxWithTitle: "启用窗口布局", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let movement = NSButton(checkboxWithTitle: "仅在窗口实际移动时触发", target: nil, action: nil)
    private let modifier = NSPopUpButton(frame: .zero, pullsDown: false)
    private var sliders: [String: NSSlider] = [:]
    private var sliderLabels: [String: NSTextField] = [:]
    private var zoneButtons: [LayoutZone.Kind: NSButton] = [:]
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let widthStepper = NSStepper()
    private let heightStepper = NSStepper()
    private let status = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let inputStatus = NSTextField(labelWithString: "")
    private let monitorStatus = NSTextField(labelWithString: "")
    private let loginStatus = NSTextField(labelWithString: "")
    private let loginSettings = NSButton(title: "登录项设置…", target: nil, action: nil)
    private let layoutPreview = LayoutSettingsPreview()
    private(set) var tabs = NSTabView()

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "LayoutDropper 设置"
        window.minSize = CGSize(width: 660, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("LayoutDropperSettings")
        super.init(window: window)
        window.delegate = self
        buildInterface()
        reloadControls()
        observer = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: store,
                                                           queue: .main) { [weak self] _ in
            self?.reloadControls()
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func showWindow(_ sender: Any?) {
        reloadControls()
        refreshLoginStatus()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
    }

    func refreshStatus(_ state: EventController.State) {
        status.stringValue = store.preferences.enabled && store.preferences.enabledZones.isEmpty
            ? "未启用布局区域" : state.title
        status.textColor = state == .listening ? .systemGreen : (state == .stopped ? .secondaryLabelColor : .systemOrange)
        monitorStatus.stringValue = state.title
        accessibilityStatus.stringValue = AXIsProcessTrusted() ? "已授权" : "未授权"
        accessibilityStatus.textColor = AXIsProcessTrusted() ? .systemGreen : .systemOrange
        inputStatus.stringValue = CGPreflightListenEventAccess() ? "已授权" : "未授权"
        inputStatus.textColor = CGPreflightListenEventAccess() ? .systemGreen : .secondaryLabelColor
        refreshLoginStatus()
    }

    private func buildInterface() {
        guard let root = window?.contentView else { return }
        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "LayoutDropper")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
        let subtitle = NSTextField(labelWithString: "窗口布局 · \(version)")
        subtitle.textColor = .secondaryLabelColor
        let identity = NSStackView(views: [title, subtitle])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 4
        let header = NSStackView(views: [icon, identity])
        header.spacing = 12
        header.alignment = .centerY
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        tabs.identifier = NSUserInterfaceItemIdentifier("settings.tabs")
        tabs.font = .systemFont(ofSize: 13)
        addTab("通用", id: "general", content: generalPage())
        addTab("布局", id: "layouts", content: layoutsPage())
        addTab("权限", id: "permissions", content: permissionsPage())

        let reset = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "恢复默认设置")!,
                             target: self, action: #selector(resetSettings))
        reset.bezelStyle = .texturedRounded
        reset.toolTip = "恢复默认设置"
        let about = button("关于", action: #selector(showAbout))
        let footer = NSStackView(views: [reset, about])
        footer.spacing = 10
        status.font = .systemFont(ofSize: 12)

        for view in [header, tabs, status, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 720),
            root.heightAnchor.constraint(equalToConstant: 640),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            tabs.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            status.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: footer.leadingAnchor, constant: -16)
        ])
    }

    private func generalPage() -> NSStackView {
        configure(enabled, id: "layout.enabled", action: #selector(toggleEnabled))
        configure(login, id: "layout.login", action: #selector(toggleLogin))
        configure(movement, id: "layout.movement", action: #selector(toggleMovement))
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        loginSettings.target = self
        loginSettings.action = #selector(openLoginSettings)
        loginSettings.bezelStyle = .rounded
        let loginRow = NSStackView(views: [login, loginStatus, loginSettings])
        loginRow.spacing = 12
        modifier.addItems(withTitles: LayoutModifier.allCases.map(\.title))
        modifier.identifier = NSUserInterfaceItemIdentifier("layout.modifier")
        modifier.target = self
        modifier.action = #selector(changeModifier)
        modifier.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let grid = NSGridView(views: [
            [label("触发组合键"), modifier],
            [label("拖动距离"), sliderRow("distance", range: 4...200)],
            [label("窗口顶部范围"), sliderRow("titleHeight", range: 24...160)],
            [label("边角触发块大小"), sliderRow("triggerSize", range: 32...180)],
            [label("遮罩透明度"), sliderRow("opacity", range: 5...45)]
        ])
        grid.column(at: 0).width = 125
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 18
        grid.columnSpacing = 18
        let stack = pageStack([enabled, loginRow, separator(), grid, movement])
        grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func layoutsPage() -> NSStackView {
        layoutPreview.heightAnchor.constraint(equalToConstant: 190).isActive = true
        let kinds = LayoutZone.Kind.allCases
        for kind in kinds {
            let checkbox = NSButton(checkboxWithTitle: kind.title, target: self, action: #selector(toggleZone(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier("layout.zone.\(kind.rawValue)")
            checkbox.tag = kinds.firstIndex(of: kind)!
            zoneButtons[kind] = checkbox
        }
        let grid = NSGridView(views: stride(from: 0, to: kinds.count, by: 2).map {
            [zoneButtons[kinds[$0]]!, zoneButtons[kinds[$0 + 1]]!]
        })
        grid.column(at: 0).width = 280
        grid.rowSpacing = 10
        configureDimension(widthField, stepper: widthStepper, id: "layout.debugWidth", range: 320...7680, tag: 0)
        configureDimension(heightField, stepper: heightStepper, id: "layout.debugHeight", range: 200...4320, tag: 1)
        let dimensions = NSStackView(views: [label("调试区域尺寸"), widthField, widthStepper,
                                             label("×"), heightField, heightStepper, label("pt")])
        dimensions.spacing = 10
        let stack = pageStack([layoutPreview, grid, separator(), dimensions])
        layoutPreview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func permissionsPage() -> NSStackView {
        let grid = NSGridView(views: [
            [label("辅助功能"), accessibilityStatus, button("授权…", action: #selector(requestAccessibility))],
            [label("输入监控"), inputStatus, button("系统设置…", action: #selector(openInputSettings))],
            [label("事件监听"), monitorStatus, button("重新连接", action: #selector(restartMonitoring))]
        ])
        grid.column(at: 0).width = 110
        grid.column(at: 1).width = 240
        grid.rowSpacing = 24
        let settings = button("打开辅助功能设置…", action: #selector(openAccessibilitySettings))
        return pageStack([grid, separator(), settings])
    }

    private func addTab(_ title: String, id: String, content: NSStackView) {
        let scroll = NSScrollView()
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        // 避免滚动内容的固有宽度限制整个窗口缩放。
        let documentWidth = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        documentWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            documentWidth,
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        let item = NSTabViewItem(identifier: id)
        item.label = title
        item.view = scroll
        tabs.addTabViewItem(item)
    }

    private func sliderRow(_ id: String, range: ClosedRange<Double>) -> NSStackView {
        let slider = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: #selector(changeSlider(_:)))
        slider.isContinuous = true
        slider.identifier = NSUserInterfaceItemIdentifier("layout.\(id)")
        slider.setAccessibilityLabel(["distance": "拖动距离", "titleHeight": "窗口顶部范围",
                                      "triggerSize": "边角触发块大小", "opacity": "遮罩透明度"][id])
        let value = NSTextField(labelWithString: "")
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.widthAnchor.constraint(equalToConstant: 64).isActive = true
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        sliders[id] = slider
        sliderLabels[id] = value
        let row = NSStackView(views: [slider, value])
        row.spacing = 12
        row.setHuggingPriority(.defaultLow, for: .horizontal)
        row.distribution = .fill
        return row
    }

    private func configureDimension(_ field: NSTextField, stepper: NSStepper, id: String,
                                    range: ClosedRange<Int>, tag: Int) {
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.tag = tag
        field.delegate = self
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 82).isActive = true
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        field.formatter = formatter
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 10
        stepper.tag = tag
        stepper.target = self
        stepper.action = #selector(changeDimensionStepper(_:))
    }

    private func reloadControls() {
        let p = store.preferences
        enabled.state = p.enabled ? .on : .off
        movement.state = p.requireWindowMovement ? .on : .off
        modifier.selectItem(at: LayoutModifier.allCases.firstIndex(of: p.modifier)!)
        let values: [String: Double] = ["distance": Double(p.activationDistance), "titleHeight": Double(p.titleBarHeight),
                                       "triggerSize": Double(p.triggerSize), "opacity": p.previewOpacity * 100]
        for (id, value) in values {
            sliders[id]?.doubleValue = value
            sliderLabels[id]?.stringValue = "\(Int(value.rounded())) \(id == "opacity" ? "%" : "pt")"
        }
        for (kind, checkbox) in zoneButtons { checkbox.state = p.enabledZones.contains(kind) ? .on : .off }
        widthField.integerValue = p.debugWidth
        heightField.integerValue = p.debugHeight
        widthStepper.integerValue = p.debugWidth
        heightStepper.integerValue = p.debugHeight
        widthField.isEnabled = p.enabledZones.contains(.debug1080)
        heightField.isEnabled = widthField.isEnabled
        widthStepper.isEnabled = widthField.isEnabled
        heightStepper.isEnabled = widthField.isEnabled
        layoutPreview.preferences = p
    }

    private func refreshLoginStatus() {
        let state = SMAppService.mainApp.status
        login.state = state == .enabled || state == .requiresApproval ? .on : .off
        loginStatus.stringValue = state == .requiresApproval ? "等待系统批准" : (state == .enabled ? "已开启" : "未开启")
        loginSettings.isHidden = state != .requiresApproval
    }

    private func configure(_ checkbox: NSButton, id: String, action: Selector) {
        checkbox.identifier = NSUserInterfaceItemIdentifier(id)
        checkbox.target = self
        checkbox.action = action
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let result = NSButton(title: title, target: self, action: action)
        result.bezelStyle = .rounded
        return result
    }

    private func label(_ text: String) -> NSTextField {
        let result = NSTextField(labelWithString: text)
        result.font = .systemFont(ofSize: 13)
        return result
    }

    private func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    private func pageStack(_ views: [NSView]) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = .vertical
        result.alignment = .leading
        result.spacing = 22
        result.setHuggingPriority(.defaultLow, for: .horizontal)
        for view in views where view is NSBox { view.widthAnchor.constraint(equalTo: result.widthAnchor).isActive = true }
        return result
    }

    @objc private func toggleEnabled() { store.update { $0.enabled = enabled.state == .on } }
    @objc private func toggleMovement() { store.update { $0.requireWindowMovement = movement.state == .on } }
    @objc private func changeModifier() {
        store.update { $0.modifier = LayoutModifier.allCases[modifier.indexOfSelectedItem] }
    }
    @objc private func changeSlider(_ sender: NSSlider) {
        store.update {
            switch sender.identifier?.rawValue {
            case "layout.distance": $0.activationDistance = Int(sender.doubleValue.rounded())
            case "layout.titleHeight": $0.titleBarHeight = Int(sender.doubleValue.rounded())
            case "layout.triggerSize": $0.triggerSize = Int(sender.doubleValue.rounded())
            case "layout.opacity": $0.previewOpacity = sender.doubleValue.rounded() / 100
            default: break
            }
        }
    }
    @objc private func toggleZone(_ sender: NSButton) {
        let kind = LayoutZone.Kind.allCases[sender.tag]
        store.update {
            if sender.state == .on { $0.enabledZones.insert(kind) } else { $0.enabledZones.remove(kind) }
        }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let value = Int(field.stringValue) else {
            reloadControls()
            return
        }
        store.update {
            if field.tag == 0 { $0.debugWidth = value } else { $0.debugHeight = value }
        }
        reloadControls()
    }
    @objc private func changeDimensionStepper(_ sender: NSStepper) {
        store.update {
            if sender.tag == 0 { $0.debugWidth = sender.integerValue } else { $0.debugHeight = sender.integerValue }
        }
    }
    @objc private func toggleLogin() {
        do {
            if login.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改登录启动"
            alert.informativeText = "请将 LayoutDropper 放入“应用程序”后重试。\n\(error.localizedDescription)"
            if let window { alert.beginSheetModal(for: window) }
        }
        refreshLoginStatus()
    }
    @objc private func resetSettings() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "恢复默认设置？"
        alert.informativeText = "将恢复 Shift 触发、默认拖动距离和所有布局。登录启动设置保留。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.store.reset() }
        }
    }
    @objc private func requestAccessibility() { onRequestAccessibility?() }
    @objc private func restartMonitoring() { onRestartMonitoring?() }
    @objc private func openAccessibilitySettings() { openPrivacy("Privacy_Accessibility") }
    @objc private func openInputSettings() { openPrivacy("Privacy_ListenEvent") }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    private func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class LayoutSettingsPreview: NSView {
    var preferences = LayoutPreferences() { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 48, width: 1920, height: 1008)
        let scale = min((bounds.width - 16) / screen.width, (bounds.height - 16) / screen.height)
        let origin = CGPoint(x: bounds.midX - screen.width * scale / 2, y: bounds.midY - screen.height * scale / 2)
        func mapped(_ rect: CGRect) -> CGRect {
            CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
                   width: rect.width * scale, height: rect.height * scale)
        }
        let outline = NSBezierPath(roundedRect: mapped(screen), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        for zone in LayoutZone.zones(screenFrame: screen, visibleFrame: visible, preferences: preferences).reversed() {
            let rect = mapped(zone.triggerFrame).insetBy(dx: 1, dy: 1)
            let color: NSColor = zone.kind == .debug1080 ? .systemBlue : .systemTeal
            color.withAlphaComponent(zone.kind == .debug1080 ? 0.08 : 0.65).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            path.fill()
            color.withAlphaComponent(0.65).setStroke()
            path.stroke()
            if zone.kind == .debug1080 {
                let text = zone.name as NSString
                text.draw(in: CGRect(x: rect.minX, y: rect.midY - 9, width: rect.width, height: 18),
                          withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                           .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
            }
        }
    }
}
