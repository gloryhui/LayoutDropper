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
        let cornerSize = min(CGFloat(preferences.triggerSize), min(screenFrame.width, screenFrame.height) / 4)
        let sideHeight = min(CGFloat(preferences.triggerSize) * 1.5, screenFrame.height / 4)
        let topWidth = min(CGFloat(preferences.triggerSize) * 5 / 3, screenFrame.width / 4)

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
                 trigger: CGRect(x: screenFrame.minX, y: screenFrame.maxY - cornerSize,
                                 width: cornerSize, height: cornerSize),
                 target: CGRect(x: vf.minX, y: splitY, width: leftWidth, height: topHeight)),
            zone(.topRight, "右上 1/4",
                 trigger: CGRect(x: screenFrame.maxX - cornerSize, y: screenFrame.maxY - cornerSize,
                                 width: cornerSize, height: cornerSize),
                 target: CGRect(x: splitX, y: splitY, width: rightWidth, height: topHeight)),
            zone(.bottomLeft, "左下 1/4",
                 trigger: CGRect(x: screenFrame.minX, y: screenFrame.minY,
                                 width: cornerSize, height: cornerSize),
                 target: CGRect(x: vf.minX, y: vf.minY, width: leftWidth, height: bottomHeight)),
            zone(.bottomRight, "右下 1/4",
                 trigger: CGRect(x: screenFrame.maxX - cornerSize, y: screenFrame.minY,
                                 width: cornerSize, height: cornerSize),
                 target: CGRect(x: splitX, y: vf.minY, width: rightWidth, height: bottomHeight)),
            zone(.leftHalf, "左半屏",
                 trigger: CGRect(x: screenFrame.minX, y: screenFrame.midY - sideHeight / 2,
                                 width: cornerSize, height: sideHeight),
                 target: CGRect(x: vf.minX, y: vf.minY, width: leftWidth, height: vf.height)),
            zone(.rightHalf, "右半屏",
                 trigger: CGRect(x: screenFrame.maxX - cornerSize, y: screenFrame.midY - sideHeight / 2,
                                 width: cornerSize, height: sideHeight),
                 target: CGRect(x: splitX, y: vf.minY, width: rightWidth, height: vf.height)),
            zone(.maximized, "全屏",
                 trigger: CGRect(x: screenFrame.midX - topWidth / 2, y: screenFrame.maxY - cornerSize,
                                 width: topWidth, height: cornerSize),
                 target: vf),
            zone(.debug1080, debugName, trigger: debugFrame, target: debugFrame)
        ].filter { preferences.enabledZones.contains($0.kind) }
    }
}
