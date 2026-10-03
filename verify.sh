#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/LayoutDropperTests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cd "$project_dir"

xcrun swiftc LayoutDropper/SettingsStore.swift LayoutDropper/LayoutZone.swift \
  Tests/LayoutZoneTests.swift -o "$test_dir/zones"
"$test_dir/zones"
xcrun swiftc LayoutDropper/SettingsStore.swift LayoutDropper/LayoutZone.swift \
  Tests/SettingsStoreTests.swift -o "$test_dir/settings"
"$test_dir/settings"
xcrun swiftc LayoutDropper/SettingsStore.swift LayoutDropper/SettingsWindowController.swift \
  LayoutDropper/EventController.swift LayoutDropper/LayoutZone.swift \
  LayoutDropper/OverlayManager.swift LayoutDropper/OverlayWindow.swift \
  LayoutDropper/WindowManager.swift Tests/SettingsWindowTests.swift -o "$test_dir/window"
"$test_dir/window"
