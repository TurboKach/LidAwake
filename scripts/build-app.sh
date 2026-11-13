#!/bin/bash
# Compile and bundle only. Shared by local builds, releases, and CI.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-native}"
case "$MODE" in
    native) ARCH_ARGS=() ;;
    universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    *) echo "Usage: $0 [native|universal]" >&2; exit 2 ;;
esac

BUILD_ARGS=(--disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --scratch-path ".build/$MODE" --configuration release)
# Package.swift defines macOS 12 for both architectures.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build "${BUILD_ARGS[@]}" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)

APP="LidAwake.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LidAwake" "$APP/Contents/MacOS/LidAwake"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xcrun xcstringstool compile Localization/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
