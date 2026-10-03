#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
derived_data="$project_dir/build/DerivedData"

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
