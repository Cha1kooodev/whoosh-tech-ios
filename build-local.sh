#!/bin/zsh
# Локальная сборка неподписанного .ipa.
# Требуется Xcode (полный, не Command Line Tools).

set -euo pipefail
cd "$(dirname "$0")"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode не найден. Установи Xcode из App Store либо собери"
  echo "через GitHub Actions (см. README.md)."
  exit 1
fi

echo "→ сборка"
xcodebuild \
  -project WHOOSHTech.xcodeproj \
  -scheme WHOOSHTech \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  CONFIGURATION_BUILD_DIR="$PWD/build/out" \
  build

APP="build/out/WHOOSHTech.app"
test -d "$APP" || { echo "не найден $APP"; exit 1; }

echo "→ упаковка"
rm -rf Payload WHOOSHTech.ipa
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry WHOOSHTech.ipa Payload
rm -rf Payload

ls -lh WHOOSHTech.ipa
shasum -a 256 WHOOSHTech.ipa
