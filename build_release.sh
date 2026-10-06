#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
derived_data="$project_dir/build/DerivedData"
make_pkg=false
if [[ "${1:-}" == "--pkg" && $# -eq 1 ]]; then
  make_pkg=true
elif [[ $# -ne 0 ]]; then
  printf 'Usage: bash build_release.sh [--pkg]\n' >&2
  exit 2
fi

xcodebuild -quiet -project "$project_dir/LayoutDropper.xcodeproj" \
  -scheme LayoutDropper \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual

ditto "$derived_data/Build/Products/Release/LayoutDropper.app" "$project_dir/build/LayoutDropper.app"
codesign --verify --deep --strict "$project_dir/build/LayoutDropper.app"
ditto -c -k --keepParent "$project_dir/build/LayoutDropper.app" "$project_dir/build/LayoutDropper.zip"

if [[ "$make_pkg" == true ]]; then
  package_dir="$(mktemp -d "${TMPDIR:-/tmp}/LayoutDropperInstaller.XXXXXX")"
  trap 'rm -rf "$package_dir"' EXIT
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/build/LayoutDropper.app/Contents/Info.plist")"
  ditto "$project_dir/build/LayoutDropper.app" "$package_dir/root/Applications/LayoutDropper.app"
  pkgbuild --analyze --root "$package_dir/root" "$package_dir/components.plist"
  plutil -replace 0.BundleIsRelocatable -bool NO "$package_dir/components.plist"
  pkgbuild --root "$package_dir/root" --component-plist "$package_dir/components.plist" \
    --identifier com.glory.layoutdropper.installer --version "$version" --install-location / \
    "$project_dir/build/LayoutDropper-$version-macos-universal.pkg"
fi
