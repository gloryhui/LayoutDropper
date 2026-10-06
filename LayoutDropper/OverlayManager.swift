import Cocoa

final class OverlayManager {
    var preferences = LayoutPreferences() {
        didSet { hide() }
    }
    private var debugWindow: OverlayWindow?
    private var previewWindow: OverlayWindow?
    private var highlightedKind: LayoutZone.Kind?
    private var currentScreen: NSScreen?

    var isVisible: Bool {
        debugWindow != nil || previewWindow != nil
    }

    func update(at point: CGPoint, modifierPressed: Bool, windowMoved: Bool, dragDistance: CGFloat) {
        guard preferences.enabled, let screen = screen(containing: point) else { hide(); return }
        let selected = zone(at: point, modifierPressed: modifierPressed,
                            windowMoved: windowMoved, dragDistance: dragDistance)
        let debugActive = selected?.kind == .debug1080 ||
            (selected == nil && modifierPressed && (windowMoved || !preferences.requireWindowMovement) &&
             dragDistance >= CGFloat(preferences.activationDistance) && preferences.enabledZones.contains(.debug1080))
        if currentScreen == screen, highlightedKind == selected?.kind, (debugWindow != nil) == debugActive { return }
        hide()
        currentScreen = screen
        highlightedKind = selected?.kind
        if debugActive, let zone = LayoutZone.zones(for: screen, preferences: preferences).first(where: { $0.kind == .debug1080 }) {
            let window = OverlayWindow(zone: zone, opacity: CGFloat(preferences.previewOpacity))
            window.setHighlighted(selected?.kind == .debug1080)
            window.orderFrontRegardless()
            debugWindow = window
        } else if let selected {
            let window = OverlayWindow(zone: selected, opacity: CGFloat(preferences.previewOpacity))
            window.setHighlighted(true)
            window.orderFrontRegardless()
            previewWindow = window
        }
    }

    func zone(at point: CGPoint, modifierPressed: Bool, windowMoved: Bool, dragDistance: CGFloat) -> LayoutZone? {
        guard let screen = screen(containing: point) else { return nil }
        return LayoutZone.selectedZone(at: point, screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                       modifierPressed: modifierPressed, windowMoved: windowMoved,
                                       dragDistance: dragDistance, preferences: preferences)
    }

    func hide() {
        previewWindow?.orderOut(nil)
        previewWindow = nil
        highlightedKind = nil
        debugWindow?.orderOut(nil)
        debugWindow = nil
        currentScreen = nil
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ??
            NSScreen.screens.first { LayoutZone.contains(point, in: $0.frame) }
    }
}
