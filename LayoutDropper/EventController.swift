import Cocoa
import ApplicationServices

final class EventController {
    enum State {
        case stopped, waitingForPermission, listening, failed

        var title: String {
            switch self {
            case .stopped: return "已暂停"
            case .waitingForPermission: return "等待辅助功能授权"
            case .listening: return "正在运行"
            case .failed: return "监听未启动"
            }
        }
    }

    var onStateChange: (() -> Void)?
    private(set) var state: State = .stopped {
        didSet { if state != oldValue { onStateChange?() } }
    }
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keepAliveTimer: Timer?

    private let overlayManager = OverlayManager()
    private var preferences = LayoutPreferences()
    private var generation = 0
    private var hasDragged = false
    private var windowHasMoved = false
    private var dragStartLocation: CGPoint?
    private var initialWindowFrame: CGRect?
    private var lastOverlayUpdateTime: TimeInterval = 0
    private var candidateWindow: AXUIElement?

    func configure(_ preferences: LayoutPreferences) {
        generation += 1
        self.preferences = preferences
        forceResetOverlayState()
        overlayManager.preferences = preferences
    }

    func start() {
        stop()
        guard preferences.enabled else { return }
        guard AXIsProcessTrusted() else {
            state = .waitingForPermission
            return
        }

        let mask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) != 53 {
                return Unmanaged.passUnretained(event)
            }
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let controller = Unmanaged<EventController>
                .fromOpaque(refcon)
                .takeUnretainedValue()

            let activeGeneration = controller.generation
            let modifierPressed = controller.isLayoutModifierPressed(event.flags)
            let location = event.location

            // CGEventTap 回调里只收事件，重活都扔回主线程，避免 macOS 禁用 event tap。
            DispatchQueue.main.async {
                guard controller.generation == activeGeneration, controller.state == .listening else { return }
                controller.handleOnMainThread(type: type, modifierPressed: modifierPressed, location: location)
            }

            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        )

        guard let eventTap else {
            print("[LayoutDropper] eventTap create failed. Enable Accessibility / Input Monitoring permissions.")
            state = .failed
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        state = .listening

        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let eventTap = self.eventTap else { return }
            guard AXIsProcessTrusted() else {
                self.stop()
                self.state = .waitingForPermission
                return
            }
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                print("[LayoutDropper] re-enable eventTap")
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }

    func stop() {
        generation += 1
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        forceResetOverlayState()
        state = .stopped
    }

    deinit {
        stop()
    }

    private func handleOnMainThread(type: CGEventType, modifierPressed: Bool, location: CGPoint) {
        switch type {
        case .leftMouseDown:
            prepareLayoutDrag(location: location)

        case .leftMouseDragged:
            handleDragged(modifierPressed: modifierPressed, location: location)

        case .leftMouseUp:
            handleMouseUp(modifierPressed: modifierPressed, location: location)

        case .flagsChanged:
            if hasDragged {
                updateOverlay(modifierPressed: modifierPressed, location: location)
            }

        case .keyDown:
            forceResetOverlayState()

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

        default:
            break
        }
    }

    private func handleDragged(modifierPressed: Bool, location: CGPoint) {
        guard candidateWindow != nil else { return }
        hasDragged = true
        recordWindowMovement()

        let now = CACurrentMediaTime()
        if now - lastOverlayUpdateTime < 0.03 {
            return
        }
        lastOverlayUpdateTime = now

        updateOverlay(modifierPressed: modifierPressed, location: location)
    }

    private func handleMouseUp(modifierPressed: Bool, location: CGPoint) {
        recordWindowMovement()
        let selectedZone = hasDragged ? overlayManager.zone(at: appKitLocation(location),
            modifierPressed: modifierPressed, windowMoved: windowHasMoved, dragDistance: dragDistance(location)) : nil
        let selectedWindow = candidateWindow

        forceResetOverlayState()

        guard let selectedZone, let selectedWindow else {
            return
        }

        let activeGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.generation == activeGeneration, self.state == .listening else { return }
            WindowManager.apply(zone: selectedZone, window: selectedWindow)
        }
    }

    private func prepareLayoutDrag(location: CGPoint) {
        forceResetOverlayState()

        guard preferences.enabled, !preferences.enabledZones.isEmpty,
              let window = WindowManager.window(at: location),
              let frame = WindowManager.frame(of: window),
              frame.contains(location),
              location.y <= frame.minY + min(CGFloat(preferences.titleBarHeight), frame.height) else {
            return
        }

        dragStartLocation = location
        candidateWindow = window
        initialWindowFrame = frame
    }

    private func recordWindowMovement() {
        guard !windowHasMoved, let window = candidateWindow, let initialWindowFrame,
              let frame = WindowManager.frame(of: window),
              abs(frame.width - initialWindowFrame.width) < 2,
              abs(frame.height - initialWindowFrame.height) < 2 else { return }
        windowHasMoved = hypot(frame.minX - initialWindowFrame.minX, frame.minY - initialWindowFrame.minY) >= 2
    }

    private func dragDistance(_ location: CGPoint) -> CGFloat {
        guard let start = dragStartLocation else { return 0 }
        return hypot(location.x - start.x, location.y - start.y)
    }

    private func appKitLocation(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - location.y)
    }

    private func updateOverlay(modifierPressed: Bool, location: CGPoint) {
        overlayManager.update(at: appKitLocation(location), modifierPressed: modifierPressed,
                              windowMoved: windowHasMoved, dragDistance: dragDistance(location))
    }

    private func forceResetOverlayState() {
        overlayManager.hide()
        hasDragged = false
        windowHasMoved = false
        dragStartLocation = nil
        initialWindowFrame = nil
        lastOverlayUpdateTime = 0
        candidateWindow = nil
    }

    private func isLayoutModifierPressed(_ flags: CGEventFlags) -> Bool {
        preferences.modifier.matches(flags)
    }
}
