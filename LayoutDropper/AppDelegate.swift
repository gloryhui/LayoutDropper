import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let eventController = EventController()
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var settingsWindow: SettingsWindowController?
    private var observer: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var lastAccessibility: Bool?
    private var lastInputMonitoring: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupMainMenu()
        eventController.configure(store.preferences)
        eventController.onStateChange = { [weak self] in self?.refreshStatus() }
        observer = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: store,
                                                           queue: .main) { [weak self] _ in
            guard let self else { return }
            self.eventController.configure(self.store.preferences)
            self.synchronizeRuntime()
        }
        synchronizeRuntime()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.synchronizeRuntime()
        }
        if !UserDefaults.standard.bool(forKey: "hasOpenedSettings") { showSettings(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        eventController.onStateChange = nil
        eventController.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if statusItem != nil { synchronizeRuntime() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        enabledMenuItem = NSMenuItem(title: "启用窗口布局", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        menu.addItem(enabledMenuItem)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        let reconnect = NSMenuItem(title: "重新连接监听", action: #selector(restartMonitoring), keyEquivalent: "")
        reconnect.target = self
        menu.addItem(reconnect)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "关于 LayoutDropper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)
        let quit = NSMenuItem(title: "退出 LayoutDropper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(title: "LayoutDropper", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "LayoutDropper")
        appItem.submenu = applicationMenu
        main.addItem(appItem)
        applicationMenu.addItem(withTitle: "关于 LayoutDropper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        let settings = applicationMenu.addItem(withTitle: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "退出 LayoutDropper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = NSMenu(title: "编辑")
        main.addItem(editItem)
        editItem.submenu?.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editItem.submenu?.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo?.keyEquivalentModifierMask = [.command, .shift]
        editItem.submenu?.addItem(.separator())
        editItem.submenu?.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editItem.submenu?.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editItem.submenu?.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu?.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    private func synchronizeRuntime(restart: Bool = false) {
        let trusted = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        let permissionChanged = lastAccessibility != trusted || lastInputMonitoring != inputMonitoring
        lastAccessibility = trusted
        lastInputMonitoring = inputMonitoring
        if store.preferences.enabled && !store.preferences.enabledZones.isEmpty {
            if restart || permissionChanged || eventController.state == .stopped ||
                (trusted && eventController.state == .waitingForPermission) {
                eventController.start()
            }
        } else if eventController.state != .stopped {
            eventController.stop()
        }
        refreshStatus()
    }

    private func refreshStatus() {
        guard statusItem != nil else { return }
        let title = store.preferences.enabled && store.preferences.enabledZones.isEmpty
            ? "未启用布局区域" : eventController.state.title
        statusMenuItem.title = title
        enabledMenuItem.state = store.preferences.enabled ? .on : .off
        let image = NSImage(systemSymbolName: store.preferences.enabled ? "rectangle.split.2x2" : "pause.rectangle",
                            accessibilityDescription: "LayoutDropper")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "LayoutDropper · \(title) · 边缘分屏 · \(store.preferences.modifier.title) 调试"
        settingsWindow?.refreshStatus(eventController.state)
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let controller = SettingsWindowController(store: store)
            controller.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
            controller.onRestartMonitoring = { [weak self] in self?.synchronizeRuntime(restart: true) }
            settingsWindow = controller
        }
        UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
        settingsWindow?.refreshStatus(eventController.state)
        settingsWindow?.showWindow(sender)
    }

    @objc private func toggleEnabled() { store.update { $0.enabled.toggle() } }
    @objc private func restartMonitoring() { synchronizeRuntime(restart: true) }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        synchronizeRuntime(restart: true)
    }
}
