import Cocoa

enum LayoutModifier: String, Codable, CaseIterable {
    case shift, option, control, controlOption

    var title: String {
        switch self {
        case .shift: return "Shift"
        case .option: return "Option"
        case .control: return "Control"
        case .controlOption: return "Control + Option"
        }
    }

    func matches(_ flags: CGEventFlags) -> Bool {
        let mask: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand, .maskSecondaryFn]
        let required: CGEventFlags
        switch self {
        case .shift: required = .maskShift
        case .option: required = .maskAlternate
        case .control: required = .maskControl
        case .controlOption: required = [.maskControl, .maskAlternate]
        }
        return flags.intersection(mask) == required
    }
}

struct LayoutTriggerSize: Codable, Equatable {
    var width: Int
    var height: Int

    mutating func sanitize() {
        width = min(7680, max(4, width))
        height = min(4320, max(4, height))
    }
}

struct LayoutPreferences: Codable, Equatable {
    var enabled = true
    var modifier: LayoutModifier = .shift
    var activationDistance = 18
    var titleBarHeight = 88
    var requireWindowMovement = true
    var triggerSize = 96
    // Optional so saved 1.1/1.2 preferences remain decodable without losing settings.
    var triggerSizes: [LayoutZone.Kind: LayoutTriggerSize]?
    var previewOpacity = 0.12
    var debugWidth = 1920
    var debugHeight = 1080
    var enabledZones = Set(LayoutZone.Kind.allCases)

    func triggerDimensions(for kind: LayoutZone.Kind) -> LayoutTriggerSize {
        if let size = triggerSizes?[kind] { return size }
        switch kind {
        case .leftHalf, .rightHalf: return LayoutTriggerSize(width: 8, height: triggerSize * 3 / 2)
        case .maximized: return LayoutTriggerSize(width: triggerSize * 5 / 3, height: 8)
        case .debug1080: return LayoutTriggerSize(width: debugWidth, height: debugHeight)
        default: return LayoutTriggerSize(width: triggerSize, height: triggerSize)
        }
    }

    mutating func setTriggerDimensions(_ size: LayoutTriggerSize, for kind: LayoutZone.Kind) {
        guard kind != .debug1080 else { return }
        if triggerSizes == nil { triggerSizes = [:] }
        triggerSizes?[kind] = size
    }

    mutating func sanitize() {
        activationDistance = min(200, max(4, activationDistance))
        titleBarHeight = min(160, max(24, titleBarHeight))
        triggerSize = min(180, max(32, triggerSize))
        if let sizes = triggerSizes {
            triggerSizes = sizes.filter { $0.key != .debug1080 }.mapValues {
                var size = $0
                size.sanitize()
                return size
            }
        }
        previewOpacity = previewOpacity.isFinite ? min(0.45, max(0.05, previewOpacity)) : 0.12
        debugWidth = min(7680, max(320, debugWidth))
        debugHeight = min(4320, max(200, debugHeight))
    }
}

final class SettingsStore {
    static let didChange = Notification.Name("LayoutDropperSettingsDidChange")
    private let defaults: UserDefaults
    private let key = "layoutPreferences.v1"
    private(set) var preferences: LayoutPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(LayoutPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = LayoutPreferences()
        }
        preferences.sanitize()
    }

    func update(_ edit: (inout LayoutPreferences) -> Void) {
        var next = preferences
        edit(&next)
        next.sanitize()
        guard next != preferences else { return }
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key)
        preferences = next
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func reset() {
        update { $0 = LayoutPreferences() }
    }
}
