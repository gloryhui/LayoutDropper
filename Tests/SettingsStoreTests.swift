import Cocoa

@main
enum SettingsStoreTests {
    static func main() {
        let suite = "LayoutDropperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        precondition(store.preferences == LayoutPreferences())
        var changes = 0
        let observer = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: store,
                                                               queue: nil) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.update {
            $0.enabled = false
            $0.modifier = .controlOption
            $0.activationDistance = 64
            $0.debugWidth = 1440
            $0.debugHeight = 900
            $0.enabledZones = [.leftHalf, .debug1080]
        }
        precondition(changes == 1, "Settings notification was not delivered")
        precondition(SettingsStore(defaults: defaults).preferences == store.preferences, "Settings not persisted")
        store.update { $0.activationDistance = 64 }
        precondition(changes == 1, "Unchanged settings should not restart the runtime")
        store.update {
            $0.activationDistance = -1
            $0.titleBarHeight = 500
            $0.triggerSize = 1
            $0.debugWidth = 99999
            $0.debugHeight = -50
            $0.previewOpacity = .nan
        }
        let safe = store.preferences
        precondition(safe.activationDistance == 4 && safe.titleBarHeight == 160 && safe.triggerSize == 32)
        precondition(safe.debugWidth == 7680 && safe.debugHeight == 200 && safe.previewOpacity == 0.12)
        store.update {
            $0.setTriggerDimensions(LayoutTriggerSize(width: 16, height: 800), for: .leftHalf)
            $0.setTriggerDimensions(LayoutTriggerSize(width: 24, height: 600), for: .rightHalf)
            $0.setTriggerDimensions(LayoutTriggerSize(width: 1200, height: 12), for: .maximized)
            $0.setTriggerDimensions(LayoutTriggerSize(width: -1, height: 99999), for: .topLeft)
        }
        precondition(store.preferences.triggerDimensions(for: .leftHalf) == LayoutTriggerSize(width: 16, height: 800))
        precondition(store.preferences.triggerDimensions(for: .rightHalf) == LayoutTriggerSize(width: 24, height: 600))
        precondition(store.preferences.triggerDimensions(for: .maximized) == LayoutTriggerSize(width: 1200, height: 12))
        precondition(store.preferences.triggerDimensions(for: .topLeft) == LayoutTriggerSize(width: 4, height: 4320))
        precondition(SettingsStore(defaults: defaults).preferences == store.preferences)
        store.update { $0.enabledZones = [] }
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        precondition(LayoutZone.zones(screenFrame: frame, visibleFrame: frame, preferences: store.preferences).isEmpty)
        store.reset()
        precondition(store.preferences == LayoutPreferences())

        var legacy = LayoutPreferences()
        legacy.modifier = .option
        legacy.activationDistance = 64
        legacy.triggerSize = 128
        legacy.enabledZones = [.leftHalf, .maximized]
        legacy.debugWidth = 1440
        let encoded = try! JSONEncoder().encode(legacy)
        var json = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "triggerSizes")
        defaults.set(try! JSONSerialization.data(withJSONObject: json), forKey: "layoutPreferences.v1")
        let migrated = SettingsStore(defaults: defaults).preferences
        precondition(migrated == legacy, "Adding trigger dimensions must preserve every legacy preference")
        precondition(migrated.triggerDimensions(for: .leftHalf) == LayoutTriggerSize(width: 8, height: 192))
        precondition(migrated.triggerDimensions(for: .maximized) == LayoutTriggerSize(width: 213, height: 8))
        defaults.set(Data("invalid".utf8), forKey: "layoutPreferences.v1")
        precondition(SettingsStore(defaults: defaults).preferences == LayoutPreferences())

        for modifier in LayoutModifier.allCases {
            let required: CGEventFlags
            switch modifier {
            case .shift: required = .maskShift
            case .option: required = .maskAlternate
            case .control: required = .maskControl
            case .controlOption: required = [.maskControl, .maskAlternate]
            }
            precondition(modifier.matches(required))
            precondition(modifier.matches(required.union(.maskAlphaShift)))
            precondition(!modifier.matches([]))
            precondition(!modifier.matches(required.union(.maskCommand)))
            precondition(!modifier.matches(required.union(.maskSecondaryFn)))
        }
        print("Settings migration, independent trigger dimensions, persistence, validation and modifier checks passed.")
    }
}
