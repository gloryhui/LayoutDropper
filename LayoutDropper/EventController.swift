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
    private var isDraggingWithModifier = false
    private var dragStartLocation: CGPoint?
    private var initialWindowFrame: CGRect?
    private var lastOverlayUpdateTime: TimeInterval = 0
    private var candidateWindow: AXUIElement?
    private var targetWindow: AXUIElement?

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
            prepareLayoutDrag(modifierPressed: modifierPressed, location: location)

        case .leftMouseDragged:
            handleDragged(modifierPressed: modifierPressed, location: location)

        case .leftMouseUp:
            if modifierPressed { handleMouseUp() } else { forceResetOverlayState() }

        case .flagsChanged:
            if !modifierPressed {
                forceResetOverlayState()
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
        guard modifierPressed, candidateWindow != nil else {
            forceResetOverlayState()
            return
        }

        if dragStartLocation == nil {
            dragStartLocation = location
            return
        }

        if !isDraggingWithModifier, let dragStartLocation {
            let dx = location.x - dragStartLocation.x
            let dy = location.y - dragStartLocation.y
            let distance = CGFloat(hypot(Double(dx), Double(dy)))
            guard distance >= CGFloat(preferences.activationDistance) else {
                return
            }
            if preferences.requireWindowMovement {
                guard let window = candidateWindow,
                      let initialWindowFrame,
                      let frame = WindowManager.frame(of: window),
                      hypot(frame.minX - initialWindowFrame.minX, frame.minY - initialWindowFrame.minY) >= 2 else {
                    return
                }
            }
        }

        let now = CACurrentMediaTime()
        if now - lastOverlayUpdateTime < 0.03 {
            return
        }
        lastOverlayUpdateTime = now

        if !isDraggingWithModifier {
            targetWindow = candidateWindow
            isDraggingWithModifier = true
        }

        let mouseLocation = NSEvent.mouseLocation
        overlayManager.showIfNeeded(at: mouseLocation)
        overlayManager.updateHighlight(at: mouseLocation)
    }

    private func handleMouseUp() {
        let shouldApply = isDraggingWithModifier || overlayManager.isVisible
        let mouseLocation = NSEvent.mouseLocation
        let selectedZone = shouldApply ? overlayManager.zone(at: mouseLocation) : nil
        let selectedWindow = targetWindow

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

    private func prepareLayoutDrag(modifierPressed: Bool, location: CGPoint) {
        forceResetOverlayState()

        guard modifierPressed,
              !preferences.enabledZones.isEmpty,
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

    private func forceResetOverlayState() {
        overlayManager.hide()
        isDraggingWithModifier = false
        dragStartLocation = nil
        initialWindowFrame = nil
        lastOverlayUpdateTime = 0
        candidateWindow = nil
        targetWindow = nil
    }

    private func isLayoutModifierPressed(_ flags: CGEventFlags) -> Bool {
        preferences.modifier.matches(flags)
    }
}
