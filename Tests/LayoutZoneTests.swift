import Cocoa

@main
enum LayoutZoneTests {
    static func main() {
        let screens: [(CGRect, CGRect)] = [
            (CGRect(x: 0, y: 0, width: 1920, height: 1080),
             CGRect(x: 0, y: 48, width: 1920, height: 1008)),
            (CGRect(x: 0, y: 0, width: 3840, height: 2160),
             CGRect(x: 0, y: 60, width: 3840, height: 2076)),
            (CGRect(x: -2560, y: -400, width: 2560, height: 1440),
             CGRect(x: -2560, y: -352, width: 2560, height: 1368)),
            (CGRect(x: 400, y: 1080, width: 1080, height: 1920),
             CGRect(x: 400, y: 1128, width: 1080, height: 1848)),
            (CGRect(x: 0, y: 0, width: 1513, height: 983),
             CGRect(x: 0, y: 48, width: 1513, height: 911)),
            (CGRect(x: 0, y: 0, width: 320, height: 400),
             CGRect(x: 0, y: 24, width: 320, height: 352))
        ]

        for (screen, visible) in screens {
            let zones = LayoutZone.zones(screenFrame: screen, visibleFrame: visible)
            precondition(zones.count == 8)
            for zone in zones {
                precondition(screen.contains(zone.triggerFrame), "Trigger outside screen: \(zone.name)")
                precondition(visible.contains(zone.targetFrame), "Target outside work area: \(zone.name)")
                precondition(zone.previewFrame == zone.targetFrame)
                let center = CGPoint(x: zone.triggerFrame.midX, y: zone.triggerFrame.midY)
                if zone.kind != .debug1080 {
                    precondition(zones.first { $0.triggerFrame.contains(center) }?.kind == zone.kind,
                                 "Incorrect trigger priority: \(zone.name)")
                }
            }

            let quarters = Array(zones.prefix(4)).map(\.targetFrame)
            let area = quarters.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
            precondition(area == visible.width * visible.height)
            for i in quarters.indices {
                for j in quarters.indices where j > i {
                    let overlap = quarters[i].intersection(quarters[j])
                    precondition(overlap.isNull || overlap.width == 0 || overlap.height == 0)
                }
            }
            precondition(quarters[0].minX == visible.minX && quarters[0].maxY == visible.maxY)
            precondition(quarters[1].maxX == visible.maxX && quarters[1].maxY == visible.maxY)
            precondition(quarters[2].minX == visible.minX && quarters[2].minY == visible.minY)
            precondition(quarters[3].maxX == visible.maxX && quarters[3].minY == visible.minY)

            let left = zones.first { $0.kind == .leftHalf }!.targetFrame
            let right = zones.first { $0.kind == .rightHalf }!.targetFrame
            precondition(left.union(right) == visible && left.maxX == right.minX)
            precondition(left.height == visible.height && right.height == visible.height)
            precondition(zones.first { $0.kind == .maximized }!.targetFrame == visible)

            let debug = zones.last!
            precondition(debug.kind == .debug1080)
            precondition(debug.targetFrame.width == min(1920, visible.width))
            precondition(debug.targetFrame.height == min(1080, visible.height))
            precondition(debug.targetFrame.minX == visible.minX && debug.targetFrame.maxY == visible.maxY)
            let interior = CGPoint(x: debug.targetFrame.minX + debug.targetFrame.width / 4,
                                   y: debug.targetFrame.midY)
            precondition(zones.first { $0.triggerFrame.contains(interior) }?.kind == .debug1080)
            let outside = CGPoint(x: screen.maxX + 1, y: screen.maxY + 1)
            precondition(!zones.contains { $0.triggerFrame.contains(outside) })

            func select(_ point: CGPoint, modifier: Bool = false, moved: Bool = true,
                        distance: CGFloat = 40, preferences: LayoutPreferences = LayoutPreferences()) -> LayoutZone? {
                LayoutZone.selectedZone(at: point, screenFrame: screen, visibleFrame: visible,
                                        modifierPressed: modifier, windowMoved: moved,
                                        dragDistance: distance, preferences: preferences)
            }
            for zone in zones where zone.kind != .debug1080 {
                var point = CGPoint(x: zone.triggerFrame.midX, y: zone.triggerFrame.midY)
                switch zone.kind {
                case .topLeft, .bottomLeft, .leftHalf: point.x = screen.minX
                case .topRight, .bottomRight, .rightHalf: point.x = screen.maxX
                case .maximized: point.y = screen.maxY
                case .debug1080: break
                }
                precondition(select(point)?.kind == zone.kind, "Edge must work without a modifier: \(zone.name)")
                precondition(select(point, modifier: true)?.kind == zone.kind, "Edge must take priority over debug")
                precondition(select(point, moved: false) == nil, "Text selection must not trigger an edge")
                precondition(select(point, distance: 2) == nil, "Tiny movements must not trigger")
                var disabled = LayoutPreferences()
                disabled.enabledZones.remove(zone.kind)
                precondition(select(point, preferences: disabled) == nil)
                disabled = LayoutPreferences()
                disabled.enabled = false
                precondition(select(point, preferences: disabled) == nil)
                disabled = LayoutPreferences()
                disabled.requireWindowMovement = false
                precondition(select(point, moved: false, preferences: disabled) == nil,
                             "Disabling debug movement guard must not disable edge movement guard")
                let insideTrigger = CGPoint(x: zone.triggerFrame.midX, y: zone.triggerFrame.midY)
                if [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(zone.kind) {
                    precondition(select(insideTrigger) == nil, "Legacy corners must still touch an edge")
                } else {
                    precondition(select(insideTrigger)?.kind == zone.kind, "Edge strips must match their trigger frames")
                }
            }
            precondition(select(interior) == nil, "Debug must never trigger on an ordinary drag")
            precondition(select(interior, modifier: true)?.kind == .debug1080)
            precondition(select(interior, modifier: true, moved: false) == nil)
            precondition(select(outside, modifier: true) == nil)
            let leftPoint = CGPoint(x: screen.minX + 8, y: screen.midY)
            precondition(select(leftPoint)?.kind == .leftHalf)
            precondition(select(CGPoint(x: screen.minX + 9, y: screen.midY)) == nil)
            var debugOnly = LayoutPreferences()
            debugOnly.enabledZones = [.debug1080]
            debugOnly.requireWindowMovement = false
            precondition(select(interior, modifier: true, moved: false, preferences: debugOnly)?.kind == .debug1080)
            precondition(select(interior, moved: false, preferences: debugOnly) == nil)
        }
        var custom = LayoutPreferences()
        custom.enabledZones = [.leftHalf, .debug1080]
        custom.triggerSize = 64
        custom.debugWidth = 1280
        custom.debugHeight = 720
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let zones = LayoutZone.zones(screenFrame: screen, visibleFrame: screen, preferences: custom)
        precondition(zones.count == 2)
        precondition(zones[0].triggerFrame.width == 8 && zones[0].triggerFrame.height == 96)
        precondition(zones[1].targetFrame == CGRect(x: 0, y: 360, width: 1280, height: 720))
        precondition(zones[1].name == "1280×720 调试")
        let leftMiddle = CGPoint(x: 4, y: 540)
        precondition(zones.first { $0.triggerFrame.contains(leftMiddle) }?.kind == .leftHalf)
        let disabledCorner = CGPoint(x: 1910, y: 1070)
        precondition(!zones.contains { $0.triggerFrame.contains(disabledCorner) })
        checkCustomDimensions()
        print("Layout geometry and modifier-free edge/debug trigger checks passed for \(screens.count) screen configurations and custom layouts.")
    }

    static func checkCustomDimensions() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let visible = screen.insetBy(dx: 0, dy: 24)
        let defaults = LayoutZone.zones(screenFrame: screen, visibleFrame: visible)
        var preferences = LayoutPreferences()
        preferences.setTriggerDimensions(LayoutTriggerSize(width: 20, height: 800), for: .leftHalf)
        preferences.setTriggerDimensions(LayoutTriggerSize(width: 12, height: 700), for: .rightHalf)
        preferences.setTriggerDimensions(LayoutTriggerSize(width: 1200, height: 16), for: .maximized)
        preferences.setTriggerDimensions(LayoutTriggerSize(width: 120, height: 20), for: .topLeft)
        let zones = LayoutZone.zones(screenFrame: screen, visibleFrame: visible, preferences: preferences)
        func zone(_ kind: LayoutZone.Kind) -> LayoutZone { zones.first { $0.kind == kind }! }
        func select(_ point: CGPoint, moved: Bool = true) -> LayoutZone? {
            LayoutZone.selectedZone(at: point, screenFrame: screen, visibleFrame: visible,
                                    modifierPressed: false, windowMoved: moved, dragDistance: 40, preferences: preferences)
        }
        precondition(zone(.leftHalf).triggerFrame == CGRect(x: screen.minX, y: screen.midY - 400, width: 20, height: 800))
        precondition(zone(.rightHalf).triggerFrame == CGRect(x: screen.maxX - 12, y: screen.midY - 350, width: 12, height: 700))
        precondition(zone(.maximized).triggerFrame == CGRect(x: screen.midX - 600, y: screen.maxY - 16, width: 1200, height: 16))
        precondition(zone(.topLeft).triggerFrame.size == CGSize(width: 120, height: 20))
        precondition(select(CGPoint(x: screen.minX + 19, y: screen.midY + 300))?.kind == .leftHalf)
        precondition(select(CGPoint(x: screen.minX + 21, y: screen.midY + 300)) == nil)
        precondition(select(CGPoint(x: screen.maxX - 11, y: screen.midY - 250))?.kind == .rightHalf)
        precondition(select(CGPoint(x: screen.maxX - 13, y: screen.midY - 250)) == nil)
        precondition(select(CGPoint(x: screen.midX + 500, y: screen.maxY - 15))?.kind == .maximized)
        precondition(select(CGPoint(x: screen.midX + 500, y: screen.maxY - 17)) == nil)
        precondition(select(CGPoint(x: screen.minX + 19, y: screen.midY + 300), moved: false) == nil)
        for zone in zones {
            precondition(zone.targetFrame == defaults.first { $0.kind == zone.kind }!.targetFrame,
                         "Trigger dimensions must not change window layout or debug dimensions")
        }
        for kind in LayoutZone.Kind.allCases where kind != .debug1080 {
            preferences.setTriggerDimensions(LayoutTriggerSize(width: 7680, height: 4320), for: kind)
        }
        let small = CGRect(x: 400, y: 1080, width: 320, height: 400)
        for zone in LayoutZone.zones(screenFrame: small, visibleFrame: small, preferences: preferences) {
            precondition(small.contains(zone.triggerFrame), "Large trigger must be clipped to its screen")
        }
        precondition(LayoutZone.selectedZone(at: CGPoint(x: small.minX, y: small.maxY), screenFrame: small,
                                            visibleFrame: small, modifierPressed: false, windowMoved: true,
                                            dragDistance: 40, preferences: preferences)?.kind == .topLeft,
                     "Corners must keep priority when enlarged edge strips overlap")
    }
}
