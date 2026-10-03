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
        }
        var custom = LayoutPreferences()
        custom.enabledZones = [.leftHalf, .debug1080]
        custom.triggerSize = 64
        custom.debugWidth = 1280
        custom.debugHeight = 720
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let zones = LayoutZone.zones(screenFrame: screen, visibleFrame: screen, preferences: custom)
        precondition(zones.count == 2)
        precondition(zones[0].triggerFrame.width == 64)
        precondition(zones[1].targetFrame == CGRect(x: 0, y: 360, width: 1280, height: 720))
        precondition(zones[1].name == "1280×720 调试")
        let leftMiddle = CGPoint(x: 10, y: 540)
        precondition(zones.first { $0.triggerFrame.contains(leftMiddle) }?.kind == .leftHalf)
        let disabledCorner = CGPoint(x: 1910, y: 1070)
        precondition(!zones.contains { $0.triggerFrame.contains(disabledCorner) })
        print("Layout zone checks passed for \(screens.count) screen configurations and custom layouts.")
    }
}
