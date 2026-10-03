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
        store.update { $0.enabledZones = [] }
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        precondition(LayoutZone.zones(screenFrame: frame, visibleFrame: frame, preferences: store.preferences).isEmpty)
        store.reset()
        precondition(store.preferences == LayoutPreferences())
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
        print("Settings persistence, notifications, validation, reset and modifier checks passed.")
    }
}
