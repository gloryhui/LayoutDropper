import Cocoa

@main
enum SettingsWindowTests {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let suite = "LayoutDropperWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let controller = SettingsWindowController(store: store)
        controller.refreshStatus(.stopped)
        controller.showWindow(nil)
        let window = controller.window!
        let initialWindow = window
        settle(window)

        let enabled: NSButton = control("layout.enabled", in: controller)
        enabled.state = .off
        app.sendAction(enabled.action!, to: enabled.target, from: enabled)
        precondition(!store.preferences.enabled)
        store.update { $0.enabled = true }
        precondition(enabled.state == .on)
        let modifier: NSPopUpButton = control("layout.modifier", in: controller)
        modifier.selectItem(at: 3)
        app.sendAction(modifier.action!, to: modifier.target, from: modifier)
        precondition(store.preferences.modifier == .controlOption)
        let distance: NSSlider = control("layout.distance", in: controller)
        distance.doubleValue = 52
        app.sendAction(distance.action!, to: distance.target, from: distance)
        precondition(store.preferences.activationDistance == 52)

        controller.tabs.selectTabViewItem(at: 1)
        settle(window)
        let topLeft: NSButton = control("layout.zone.topLeft", in: controller)
        topLeft.state = .off
        app.sendAction(topLeft.action!, to: topLeft.target, from: topLeft)
        precondition(!store.preferences.enabledZones.contains(.topLeft))
        let debug: NSButton = control("layout.zone.debug1080", in: controller)
        debug.state = .off
        app.sendAction(debug.action!, to: debug.target, from: debug)
        let width: NSTextField = control("layout.debugWidth", in: controller)
        precondition(!width.isEnabled)
        debug.state = .on
        app.sendAction(debug.action!, to: debug.target, from: debug)
        precondition(width.isEnabled)
        precondition(window.makeFirstResponder(width))
        let editor = window.fieldEditor(true, for: width) as! NSTextView
        editor.string = "1600"
        window.performClose(nil)
        precondition(store.preferences.debugWidth == 1600)
        controller.showWindow(nil)
        precondition(SettingsStore(defaults: defaults).preferences == store.preferences)

        controller.tabs.selectTabViewItem(at: 2)
        settle(window)
        precondition(controller.tabs.numberOfTabViewItems == 4)
        let disabledWidth: NSTextField = control("layout.trigger.topLeft.width", in: controller)
        precondition(!disabledWidth.isEnabled)
        store.update { $0.enabledZones.insert(.topLeft) }
        precondition(disabledWidth.isEnabled)
        for (index, kind) in LayoutZone.Kind.allCases.filter({ $0 != .debug1080 }).enumerated() {
            let widthStepper: NSStepper = control("layout.trigger.\(kind.rawValue).width.stepper", in: controller)
            let heightStepper: NSStepper = control("layout.trigger.\(kind.rawValue).height.stepper", in: controller)
            widthStepper.integerValue = 12 + index * 4
            app.sendAction(widthStepper.action!, to: widthStepper.target, from: widthStepper)
            heightStepper.integerValue = 600 + index * 20
            app.sendAction(heightStepper.action!, to: heightStepper.target, from: heightStepper)
            precondition(store.preferences.triggerDimensions(for: kind) ==
                         LayoutTriggerSize(width: 12 + index * 4, height: 600 + index * 20))
            let width: NSTextField = control("layout.trigger.\(kind.rawValue).width", in: controller)
            let height: NSTextField = control("layout.trigger.\(kind.rawValue).height", in: controller)
            precondition(width.integerValue == widthStepper.integerValue && height.integerValue == heightStepper.integerValue)
        }
        let topWidth: NSTextField = control("layout.trigger.maximized.width", in: controller)
        precondition(window.makeFirstResponder(topWidth))
        let triggerEditor = window.fieldEditor(true, for: topWidth) as! NSTextView
        triggerEditor.string = "1200"
        window.performClose(nil)
        precondition(store.preferences.triggerDimensions(for: .maximized).width == 1200)
        precondition(store.preferences.triggerDimensions(for: .maximized).height == 720)
        precondition(store.preferences.debugWidth == 1600, "Trigger edits must not change debug size")
        controller.showWindow(nil)
        precondition(SettingsStore(defaults: defaults).preferences == store.preferences)

        for _ in 0..<3 {
            window.close()
            controller.showWindow(nil)
            precondition(controller.window === initialWindow && window.isVisible)
        }
        store.reset()
        precondition(disabledWidth.integerValue == LayoutPreferences().triggerSize)
        checkScreenPreviews(controller, window: window)
        if let directory = ProcessInfo.processInfo.environment["LAYOUTDROPPER_SCREENSHOTS"] {
            store.update {
                $0.setTriggerDimensions(LayoutTriggerSize(width: 1200, height: 12), for: .maximized)
                $0.setTriggerDimensions(LayoutTriggerSize(width: 12, height: 800), for: .leftHalf)
                $0.setTriggerDimensions(LayoutTriggerSize(width: 12, height: 800), for: .rightHalf)
            }
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                for index in 0..<controller.tabs.numberOfTabViewItems {
                    controller.tabs.selectTabViewItem(at: index)
                    settle(window)
                    let content = window.contentView!
                    precondition(abs(content.frame.width - 720) < 1, "Window width changed with its tab")
                    precondition(abs(content.frame.height - 640) < 1, "Window height changed with its tab")
                    precondition(!content.hasAmbiguousLayout)
                    precondition(!controller.tabs.hasAmbiguousLayout)
                    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    let data = bitmap.representation(using: .png, properties: [:])!
                    try data.write(to: URL(fileURLWithPath: "\(directory)/settings-\(name)-\(index).png"))
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)",
                                         "\(directory)/window-\(name)-\(index).png"]
                    try capture.run()
                    capture.waitUntilExit()
                    precondition(capture.terminationStatus == 0, "Window screenshot failed")
                }
            }
        }
        window.close()
        checkOverlays()
        print("Settings UI, current-screen previews, display refresh, edge/debug switching and movement guards passed.")
    }

    static func checkScreenPreviews(_ controller: SettingsWindowController, window: NSWindow) {
        let info: NSTextField = control("layout.screenInfo", in: controller, root: window.contentView)
        let originalFrame = window.frame
        defer { window.setFrame(originalFrame, display: true) }
        for screen in NSScreen.screens where screen.frame.width >= window.frame.width && screen.frame.height >= window.frame.height {
            window.setFrameOrigin(CGPoint(x: screen.frame.midX - window.frame.width / 2,
                                          y: screen.frame.midY - window.frame.height / 2))
            settle(window)
            precondition(window.screen == screen)
            let expectedInfo = "\(Int(screen.frame.width))×\(Int(screen.frame.height)) pt"
            precondition(info.stringValue.contains(screen.localizedName) && info.stringValue.contains(expectedInfo))
            for (tab, identifier) in [(1, "layout.preview"), (2, "layout.triggerPreview")] {
                controller.tabs.selectTabViewItem(at: tab)
                settle(window)
                let preview: LayoutSettingsPreview = control(identifier, in: controller)
                precondition(preview.previewScreen == screen, "Preview must follow the settings window's screen")
                let actual = preview.previewZones()
                let expected = LayoutZone.zones(for: screen, preferences: preview.preferences)
                precondition(actual.count == expected.count)
                for (a, b) in zip(actual, expected) {
                    precondition(a.kind == b.kind && a.triggerFrame == b.triggerFrame && a.targetFrame == b.targetFrame)
                }
            }
            info.stringValue = "stale"
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            precondition(info.stringValue.contains(expectedInfo), "Display parameter changes must refresh screen metadata")
        }
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 190)
        for screen in [CGRect(x: 0, y: 0, width: 3456, height: 2234),
                       CGRect(x: -2560, y: -400, width: 2560, height: 1440),
                       CGRect(x: 400, y: 1080, width: 1080, height: 1920)] {
            let frame = LayoutSettingsPreview.fittedFrame(screen, screenFrame: screen, in: bounds)!
            precondition(bounds.contains(frame))
            precondition(abs(frame.midX - bounds.midX) < 0.01 && abs(frame.midY - bounds.midY) < 0.01)
            precondition(abs(frame.width / frame.height - screen.width / screen.height) < 0.0001)
            let bottomLeft = CGRect(x: screen.minX, y: screen.minY, width: 8, height: 8)
            let mapped = LayoutSettingsPreview.fittedFrame(bottomLeft, screenFrame: screen, in: bounds)!
            precondition(mapped.minX == frame.minX && mapped.minY == frame.minY,
                         "Secondary screen offsets must not displace preview zones")
        }
        precondition(LayoutSettingsPreview.fittedFrame(.zero, screenFrame: .zero, in: bounds) == nil)
    }

    static func checkOverlays() {
        let screen = NSScreen.screens.first!
        let manager = OverlayManager()
        let edge = CGPoint(x: screen.frame.minX + 1, y: screen.frame.midY)
        let center = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        manager.update(at: edge, modifierPressed: false, windowMoved: false, dragDistance: 100)
        precondition(!manager.isVisible, "Text selection must not show an edge preview")
        manager.update(at: edge, modifierPressed: false, windowMoved: true, dragDistance: 100)
        precondition(manager.isVisible, "Normal window drag must show an edge preview")
        manager.update(at: edge, modifierPressed: true, windowMoved: true, dragDistance: 100)
        manager.update(at: edge, modifierPressed: false, windowMoved: true, dragDistance: 100)
        precondition(manager.isVisible, "Releasing Shift must not cancel edge snapping")
        manager.update(at: center, modifierPressed: false, windowMoved: true, dragDistance: 100)
        precondition(!manager.isVisible, "Leaving an edge must hide the preview")
        manager.update(at: center, modifierPressed: true, windowMoved: true, dragDistance: 100)
        precondition(manager.isVisible, "Shift must still show the debug overlay")
        manager.update(at: center, modifierPressed: false, windowMoved: true, dragDistance: 100)
        precondition(!manager.isVisible, "Releasing Shift away from edges must hide debug")
        manager.update(at: edge, modifierPressed: false, windowMoved: true, dragDistance: 2)
        precondition(!manager.isVisible, "Tiny movements must not show previews")
        manager.update(at: edge, modifierPressed: false, windowMoved: true, dragDistance: 100)
        manager.hide()
        precondition(!manager.isVisible)
        var paused = LayoutPreferences()
        paused.enabled = false
        manager.preferences = paused
        manager.update(at: center, modifierPressed: true, windowMoved: true, dragDistance: 100)
        precondition(!manager.isVisible, "Paused layouts must not show debug")
    }

    static func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }

    static func control<T: NSView>(_ id: String, in controller: SettingsWindowController, root: NSView? = nil) -> T {
        func search(_ view: NSView) -> T? {
            if view.identifier?.rawValue == id { return view as? T }
            return view.subviews.compactMap(search).first
        }
        guard let result = search(root ?? controller.tabs.selectedTabViewItem!.view!) else {
            fatalError("Missing control: \(id)")
        }
        return result
    }
}
