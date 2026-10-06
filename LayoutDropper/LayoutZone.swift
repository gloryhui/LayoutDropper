import Cocoa

struct LayoutZone {
    enum Kind: String, Codable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        case leftHalf, rightHalf, maximized, debug1080

        var title: String {
            switch self {
            case .topLeft: return "左上四分屏"
            case .topRight: return "右上四分屏"
            case .bottomLeft: return "左下四分屏"
            case .bottomRight: return "右下四分屏"
            case .leftHalf: return "左半屏"
            case .rightHalf: return "右半屏"
            case .maximized: return "顶部全屏"
            case .debug1080: return "调试区域"
            }
        }
    }

    let kind: Kind
    let name: String
    let triggerFrame: CGRect
    let previewFrame: CGRect
    let targetFrame: CGRect

    static func selectedZone(at point: CGPoint, screenFrame: CGRect, visibleFrame: CGRect,
                             modifierPressed: Bool, windowMoved: Bool, dragDistance: CGFloat,
                             preferences: LayoutPreferences) -> LayoutZone? {
        guard preferences.enabled, dragDistance >= CGFloat(preferences.activationDistance),
              contains(point, in: screenFrame) else { return nil }
        let zones = zones(screenFrame: screenFrame, visibleFrame: visibleFrame, preferences: preferences)
        if windowMoved, let edge = zones.first(where: {
            $0.kind != .debug1080 && contains(point, in: $0.triggerFrame) &&
                (preferences.triggerSizes?[$0.kind] != nil || touchesEdge(point, kind: $0.kind, screen: screenFrame))
        }) {
            return edge
        }
        guard modifierPressed, windowMoved || !preferences.requireWindowMovement else { return nil }
        return zones.first { $0.kind == .debug1080 && contains(point, in: $0.triggerFrame) }
    }

    static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func touchesEdge(_ point: CGPoint, kind: Kind, screen: CGRect) -> Bool {
        // 触发范围决定沿边的位置；只有贴近屏幕边界才算撞边。
        let inset: CGFloat = 8
        let left = point.x - screen.minX <= inset
        let right = screen.maxX - point.x <= inset
        let top = screen.maxY - point.y <= inset
        let bottom = point.y - screen.minY <= inset
        switch kind {
        case .topLeft: return left || top
        case .topRight: return right || top
        case .bottomLeft: return left || bottom
        case .bottomRight: return right || bottom
        case .leftHalf: return left
        case .rightHalf: return right
        case .maximized: return top
        case .debug1080: return false
        }
    }

    static func zones(for screen: NSScreen, preferences: LayoutPreferences = LayoutPreferences()) -> [LayoutZone] {
        zones(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, preferences: preferences)
    }

    static func zones(screenFrame: CGRect, visibleFrame vf: CGRect,
                      preferences: LayoutPreferences = LayoutPreferences()) -> [LayoutZone] {
        let splitX = floor(vf.midX)
        let splitY = floor(vf.midY)
        let leftWidth = splitX - vf.minX
        let rightWidth = vf.maxX - splitX
        let bottomHeight = splitY - vf.minY
        let topHeight = vf.maxY - splitY

        func triggerSize(_ kind: Kind) -> CGSize {
            let size = preferences.triggerDimensions(for: kind)
            if preferences.triggerSizes?[kind] != nil {
                return CGSize(width: min(CGFloat(size.width), screenFrame.width),
                              height: min(CGFloat(size.height), screenFrame.height))
            }
            // Preserve the legacy corner extents and edge positions until customized.
            switch kind {
            case .leftHalf, .rightHalf:
                return CGSize(width: CGFloat(size.width), height: min(CGFloat(size.height), screenFrame.height / 4))
            case .maximized:
                return CGSize(width: min(CGFloat(size.width), screenFrame.width / 4), height: CGFloat(size.height))
            default:
                let side = min(CGFloat(size.width), min(screenFrame.width, screenFrame.height) / 4)
                return CGSize(width: side, height: side)
            }
        }
        let topLeft = triggerSize(.topLeft)
        let topRight = triggerSize(.topRight)
        let bottomLeft = triggerSize(.bottomLeft)
        let bottomRight = triggerSize(.bottomRight)
        let left = triggerSize(.leftHalf)
        let right = triggerSize(.rightHalf)
        let top = triggerSize(.maximized)

        let width: CGFloat = min(CGFloat(preferences.debugWidth), vf.width)
        let height: CGFloat = min(CGFloat(preferences.debugHeight), vf.height)
        let debugName = preferences.debugWidth == 1920 && preferences.debugHeight == 1080
            ? "1080P 调试" : "\(preferences.debugWidth)×\(preferences.debugHeight) 调试"

        let debugFrame = CGRect(
            x: vf.minX,
            y: vf.maxY - height,
            width: width,
            height: height
        ).integral

        func zone(_ kind: Kind, _ name: String, trigger: CGRect, target: CGRect) -> LayoutZone {
            LayoutZone(kind: kind, name: name, triggerFrame: trigger,
                       previewFrame: target, targetFrame: target)
        }

        // 边角优先于 1080P 遮罩；触发块覆盖屏幕边缘，窗口布局避开菜单栏和 Dock。
        return [
            zone(.topLeft, "左上 1/4",
                 trigger: CGRect(x: screenFrame.minX, y: screenFrame.maxY - topLeft.height,
                                 width: topLeft.width, height: topLeft.height),
                 target: CGRect(x: vf.minX, y: splitY, width: leftWidth, height: topHeight)),
            zone(.topRight, "右上 1/4",
                 trigger: CGRect(x: screenFrame.maxX - topRight.width, y: screenFrame.maxY - topRight.height,
                                 width: topRight.width, height: topRight.height),
                 target: CGRect(x: splitX, y: splitY, width: rightWidth, height: topHeight)),
            zone(.bottomLeft, "左下 1/4",
                 trigger: CGRect(x: screenFrame.minX, y: screenFrame.minY,
                                 width: bottomLeft.width, height: bottomLeft.height),
                 target: CGRect(x: vf.minX, y: vf.minY, width: leftWidth, height: bottomHeight)),
            zone(.bottomRight, "右下 1/4",
                 trigger: CGRect(x: screenFrame.maxX - bottomRight.width, y: screenFrame.minY,
                                 width: bottomRight.width, height: bottomRight.height),
                 target: CGRect(x: splitX, y: vf.minY, width: rightWidth, height: bottomHeight)),
            zone(.leftHalf, "左半屏",
                 trigger: CGRect(x: screenFrame.minX, y: screenFrame.midY - left.height / 2,
                                 width: left.width, height: left.height),
                 target: CGRect(x: vf.minX, y: vf.minY, width: leftWidth, height: vf.height)),
            zone(.rightHalf, "右半屏",
                 trigger: CGRect(x: screenFrame.maxX - right.width, y: screenFrame.midY - right.height / 2,
                                 width: right.width, height: right.height),
                 target: CGRect(x: splitX, y: vf.minY, width: rightWidth, height: vf.height)),
            zone(.maximized, "全屏",
                 trigger: CGRect(x: screenFrame.midX - top.width / 2, y: screenFrame.maxY - top.height,
                                 width: top.width, height: top.height),
                 target: vf),
            zone(.debug1080, debugName, trigger: debugFrame, target: debugFrame)
        ].filter { preferences.enabledZones.contains($0.kind) }
    }
}
