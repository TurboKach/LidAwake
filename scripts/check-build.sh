#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BINARY="LidAwake.app/Contents/MacOS/LidAwake"
plutil -lint LidAwake.app/Contents/Info.plist
codesign --verify --strict LidAwake.app
if [ "${1:-}" = universal ]; then
    lipo "$BINARY" -verify_arch arm64
    lipo "$BINARY" -verify_arch x86_64
fi
MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)
for arch in $(lipo -archs "$BINARY"); do
    ACTUAL=$(xcrun vtool -arch "$arch" -show-build "$BINARY" | awk '$1 == "minos" { print $2 }')
    if [ "$ACTUAL" != "$MINIMUM" ]; then
        echo "$arch requires macOS $ACTUAL; expected $MINIMUM" >&2
        exit 1
    fi
done
echo "Bundle, signature, and deployment targets verified."
