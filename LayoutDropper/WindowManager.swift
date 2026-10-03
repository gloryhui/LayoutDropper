import Cocoa
import ApplicationServices

enum WindowManager {
    static func apply(zone: LayoutZone) {
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }

        guard let window = activeWindow() else {
            NSSound.beep()
            return
        }

        apply(zone: zone, window: window)
    }

    static func apply(zone: LayoutZone, window: AXUIElement) {
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }

        let axFrame = convertToAccessibilityCoordinates(zone.targetFrame)
        set(window: window, frame: axFrame)
    }

    static func activeWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedWindow(for: app.processIdentifier)
    }

    static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
           let element {
            var windowValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
               let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
                return (windowValue as! AXUIElement)
            }
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
               role as? String == kAXWindowRole as String {
                return element
            }
        }
        return activeWindow()
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func focusedWindow(for pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        )
        if focusedResult == .success,
           let focusedValue,
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            return (focusedValue as! AXUIElement)
        }

        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        if windowsResult == .success,
           let windowsValue,
           CFGetTypeID(windowsValue) == CFArrayGetTypeID(),
           let windows = windowsValue as? [AXUIElement],
           let first = windows.first {
            return first
        }

        return nil
    }

    private static func set(window: AXUIElement, frame: CGRect) {
        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
    }

    /// AppKit/NSScreen 使用左下角为原点；Accessibility API 窗口坐标使用左上角为原点。
    private static func convertToAccessibilityCoordinates(_ rect: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let y = mainHeight - rect.maxY
        return CGRect(x: rect.minX, y: y, width: rect.width, height: rect.height).integral
    }
}
