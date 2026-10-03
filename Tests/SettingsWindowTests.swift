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

        for _ in 0..<3 {
            window.close()
            controller.showWindow(nil)
            precondition(controller.window === initialWindow && window.isVisible)
        }
        store.reset()
        if let directory = ProcessInfo.processInfo.environment["LAYOUTDROPPER_SCREENSHOTS"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                for index in 0..<3 {
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
        print("Settings UI actions, live refresh, persistence, reopen and window layout checks passed.")
    }

    static func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }

    static func control<T: NSView>(_ id: String, in controller: SettingsWindowController) -> T {
        func search(_ view: NSView) -> T? {
            if view.identifier?.rawValue == id { return view as? T }
            return view.subviews.compactMap(search).first
        }
        guard let result = search(controller.tabs.selectedTabViewItem!.view!) else {
            fatalError("Missing control: \(id)")
        }
        return result
    }
}
