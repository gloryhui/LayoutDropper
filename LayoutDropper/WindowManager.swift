import Cocoa
import ApplicationServices

enum WindowManager {
    private static var pendingApplication: WindowFrameApplication?

    static func cancelPendingApplication() {
        pendingApplication?.cancel()
        pendingApplication = nil
    }

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
        cancelPendingApplication()
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }

        let axFrame = convertToAccessibilityCoordinates(zone.targetFrame)
        let application = WindowFrameApplication(
            target: axFrame,
            readFrame: { frame(of: window) },
            setPosition: { point in
                var point = point
                guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
                return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            },
            setSize: { size in
                var size = size
                guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
                return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            },
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            },
            completion: { actual, errors in
                if !WindowFrameApplication.matches(actual, target: axFrame) {
                    print("[LayoutDropper] Window did not reach target after bounded retries. target=\(axFrame), actual=\(String(describing: actual)), AX errors=\(errors.map(\.rawValue))")
                }
                pendingApplication = nil
            }
        )
        pendingApplication = application
        application.start()
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

    /// AppKit/NSScreen 使用左下角为原点；Accessibility API 窗口坐标使用左上角为原点。
    private static func convertToAccessibilityCoordinates(_ rect: CGRect) -> CGRect {
        let mainMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let y = mainMaxY - rect.maxY
        return CGRect(x: rect.minX, y: y, width: rect.width, height: rect.height).integral
    }
}

/// AX writes can succeed before the application finishes moving/resizing its window.
/// Keep the retry policy independent of AX so delayed and constrained windows can be tested.
final class WindowFrameApplication {
    private let target: CGRect
    private let readFrame: () -> CGRect?
    private let setPosition: (CGPoint) -> AXError
    private let setSize: (CGSize) -> AXError
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let completion: (CGRect?, [AXError]) -> Void
    private var finished = false
    private var attempts = 0
    private var matchingReads = 0
    private var errors: [AXError] = []
    private static let maximumAttempts = 5

    init(target: CGRect, readFrame: @escaping () -> CGRect?,
         setPosition: @escaping (CGPoint) -> AXError, setSize: @escaping (CGSize) -> AXError,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         completion: @escaping (CGRect?, [AXError]) -> Void) {
        self.target = target
        self.readFrame = readFrame
        self.setPosition = setPosition
        self.setSize = setSize
        self.schedule = schedule
        self.completion = completion
    }

    func start() {
        // Let the target application process mouse-up before changing its frame.
        schedule(0.05) { [weak self] in self?.apply() }
    }

    func cancel() {
        finished = true
    }

    static func matches(_ actual: CGRect?, target: CGRect) -> Bool {
        guard let actual else { return false }
        let tolerance: CGFloat = 1
        return abs(actual.minX - target.minX) <= tolerance &&
            abs(actual.minY - target.minY) <= tolerance &&
            abs(actual.width - target.width) <= tolerance &&
            abs(actual.height - target.height) <= tolerance
    }

    private func apply() {
        guard !finished else { return }
        attempts += 1
        // Move onto the destination display before requesting its size. Resizing may
        // shift the origin, so restore the target position once more afterwards.
        record(setPosition(target.origin))
        record(setSize(target.size))
        record(setPosition(target.origin))
        schedule(0.10) { [weak self] in self?.verify() }
    }

    private func record(_ error: AXError) {
        if error != .success { errors.append(error) }
    }

    private func verify() {
        guard !finished else { return }
        let actual = readFrame()
        if Self.matches(actual, target: target) {
            matchingReads += 1
            if matchingReads < 2 {
                // A second read catches a late drag/tiling animation overwriting AX.
                schedule(0.15) { [weak self] in self?.verify() }
                return
            }
        } else if attempts < Self.maximumAttempts {
            matchingReads = 0
            apply()
            return
        }
        finished = true
        completion(actual, errors)
    }
}
