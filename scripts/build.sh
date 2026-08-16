#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Lark M2 Status.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter \
  -arch arm64 -mmacosx-version-min=13.0 \
  -I"$ROOT/ThirdParty/hidapi/hidapi" \
  -framework AppKit -framework ServiceManagement -framework IOKit -framework CoreFoundation \
  "$ROOT/Sources/AppDelegate.m" "$ROOT/ThirdParty/hidapi/mac/hid.c" \
  -o "$APP/Contents/MacOS/LarkM2Status"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
