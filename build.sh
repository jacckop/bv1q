#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
mkdir -p "$BUILD_DIR"

python3 "$ROOT/tools/verify_translations.py"
python3 "$ROOT/tools/generate_translations.py"

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"

"$CLANG" \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  -miphoneos-version-min=15.0 \
  -dynamiclib \
  -fobjc-arc \
  -fmodules \
  -O2 \
  -Wall \
  -Wextra \
  -Wno-nullability-completeness \
  -Wno-deprecated-declarations \
  -framework Foundation \
  -framework UIKit \
  -Wl,-dead_strip \
  -Wl,-install_name,@rpath/WhitegramArabic.dylib \
  "$ROOT/Sources/Tweak.m" \
  "$ROOT/Sources/WGTranslations.m" \
  -I"$ROOT/Sources" \
  -o "$BUILD_DIR/WhitegramArabic.dylib"

codesign --force --sign - "$BUILD_DIR/WhitegramArabic.dylib"

file "$BUILD_DIR/WhitegramArabic.dylib"
otool -L "$BUILD_DIR/WhitegramArabic.dylib"

echo "Built: $BUILD_DIR/WhitegramArabic.dylib"
