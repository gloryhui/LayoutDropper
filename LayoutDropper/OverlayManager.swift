import Cocoa

final class OverlayManager {
    var preferences = LayoutPreferences() {
        didSet { hide() }
    }
    private var windows: [OverlayWindow] = []
    private var previewWindow: OverlayWindow?
    private var highlightedKind: LayoutZone.Kind?
    private var zones: [LayoutZone] = []
    private var currentScreen: NSScreen?

    var isVisible: Bool {
        !windows.isEmpty
    }

    func showIfNeeded(at point: CGPoint) {
        guard let screen = screen(containing: point) else { return }
        if currentScreen == screen, isVisible { return }

        hide()
        currentScreen = screen
        zones = LayoutZone.zones(for: screen, preferences: preferences)
        windows = zones.map { zone in
            let window = OverlayWindow(zone: zone, isTrigger: zone.kind != .debug1080,
                                       opacity: CGFloat(preferences.previewOpacity))
            window.orderFrontRegardless()
            return window
        }
        // 保证小触发块位于 1080P 遮罩之上。
        for window in windows where window.zone.kind != .debug1080 {
            window.orderFrontRegardless()
        }
    }

    func updateHighlight(at point: CGPoint) {
        let selectedZone = zone(at: point)
        guard highlightedKind != selectedZone?.kind else { return }
        highlightedKind = selectedZone?.kind

        previewWindow?.orderOut(nil)
        previewWindow = nil
        for window in windows {
            window.setHighlighted(window.zone.kind == highlightedKind)
            if window.zone.kind == .debug1080 {
                if selectedZone == nil || highlightedKind == .debug1080 {
                    window.orderFrontRegardless()
                } else {
                    window.orderOut(nil)
                }
            }
        }

        if let selectedZone, selectedZone.kind != .debug1080 {
            let preview = OverlayWindow(zone: selectedZone, opacity: CGFloat(preferences.previewOpacity))
            preview.setHighlighted(true)
            preview.orderFrontRegardless()
            previewWindow = preview
        }

        for window in windows where window.zone.kind != .debug1080 {
            window.orderFrontRegardless()
        }
    }

    func zone(at point: CGPoint) -> LayoutZone? {
        guard let screen = screen(containing: point) else { return nil }
        let screenZones = currentScreen == screen ? zones : LayoutZone.zones(for: screen, preferences: preferences)
        return screenZones.first { $0.triggerFrame.contains(point) }
    }

    func hide() {
        previewWindow?.orderOut(nil)
        previewWindow = nil
        highlightedKind = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        zones.removeAll()
        currentScreen = nil
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }
}
