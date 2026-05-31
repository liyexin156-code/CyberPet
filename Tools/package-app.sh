#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
PRODUCT_NAME="${PRODUCT_NAME:-PetTaskBuddy}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-PetTaskBuddy}"
BUNDLE_IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:-com.liyexin.PetTaskBuddy}"
DEVELOPMENT_LANGUAGE="${DEVELOPMENT_LANGUAGE:-zh-Hans}"
BUILD_DIR="$ROOT_DIR/.build/apple/Products/$CONFIGURATION"
APP_DIR="$ROOT_DIR/.build/app/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

swift build -c "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build/apple"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build/apple" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"
cp -R "$ROOT_DIR/Assets/pet" "$RESOURCES_DIR/pet"

sed \
  -e "s|\$(PRODUCT_NAME)|$PRODUCT_NAME|g" \
  -e "s|\$(EXECUTABLE_NAME)|$EXECUTABLE_NAME|g" \
  -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$BUNDLE_IDENTIFIER|g" \
  -e "s|\$(DEVELOPMENT_LANGUAGE)|$DEVELOPMENT_LANGUAGE|g" \
  "$INFO_PLIST_TEMPLATE" > "$CONTENTS_DIR/Info.plist"

codesign --force --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
