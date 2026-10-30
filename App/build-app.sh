#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
MODE="${1:-preview}"
if [[ "$MODE" != preview && "$MODE" != store ]]; then
    echo 'Usage: ./build-app.sh [preview|store]' >&2
    exit 2
fi
if [[ "$MODE" == store ]]; then
    if [[ -z "${FOLIANCE_TEAM_ID:-}" ]]; then
        FOLIANCE_TEAM_ID="$(python3 -c 'import json; from pathlib import Path; p=Path("AppStore/Submission.local.json"); print(json.loads(p.read_text()).get("teamID", "") if p.exists() else "")')"
        export FOLIANCE_TEAM_ID
    fi
    python3 scripts/preflight-store.py
fi
ARCH_ARGS=(--arch arm64)
if [[ "$MODE" == store || "${FOLIANCE_UNIVERSAL:-0}" == 1 ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi
APP_DIR="$PROJECT_DIR/dist/$MODE/Foliance.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
# Release artifacts use stable compiler paths, so the author's home/workspace
# cannot be recovered from file macros or debug references in shipped code.
swift build -c release "${ARCH_ARGS[@]}" \
    -Xswiftc -file-prefix-map -Xswiftc "$PROJECT_DIR=/Foliance" \
    -Xcc "-ffile-prefix-map=$PROJECT_DIR=/Foliance"
BIN_DIR="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)"
cp "$BIN_DIR/Foliance" "$APP_DIR/Contents/MacOS/Foliance.next"
chmod +x "$APP_DIR/Contents/MacOS/Foliance.next"
mv -f "$APP_DIR/Contents/MacOS/Foliance.next" "$APP_DIR/Contents/MacOS/Foliance"
strip -S "$APP_DIR/Contents/MacOS/Foliance"
cp Config/Info.plist "$APP_DIR/Contents/Info.plist"
cp Config/PrivacyInfo.xcprivacy "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
cp AppStore/Privacy.md "$APP_DIR/Contents/Resources/Privacy.md"
mkdir -p "$APP_DIR/Contents/Resources/ThirdPartyLicenses"
cp ThirdPartyLicenses/* "$APP_DIR/Contents/Resources/ThirdPartyLicenses/"
cp LICENSE "$APP_DIR/Contents/Resources/ThirdPartyLicenses/Foliance-MIT.txt"
if [[ ! -f Assets/Foliance.png ]]; then swift scripts/generate-icon.swift; fi
ICONSET="$PROJECT_DIR/.build/Foliance.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/Foliance.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Assets/Foliance.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/Foliance.icns"
# Native macOS icon asset catalog, including the 1024-pixel App Store icon.
mkdir -p "$PROJECT_DIR/.build/Assets.xcassets/AppIcon.appiconset"
cp "$ICONSET"/*.png "$PROJECT_DIR/.build/Assets.xcassets/AppIcon.appiconset/"
python3 scripts/icon-catalog.py "$PROJECT_DIR/.build/Assets.xcassets/AppIcon.appiconset"
xcrun actool --compile "$APP_DIR/Contents/Resources" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$PROJECT_DIR/.build/icon-info.plist" "$PROJECT_DIR/.build/Assets.xcassets" >/dev/null
python3 - "$APP_DIR/Contents/Info.plist" "$PROJECT_DIR/.build/icon-info.plist" <<'PY'
import sys,plistlib
with open(sys.argv[1],'rb') as f: main=plistlib.load(f)
with open(sys.argv[2],'rb') as f: main.update(plistlib.load(f))
with open(sys.argv[1],'wb') as f: plistlib.dump(main,f)
PY
plutil -lint "$APP_DIR/Contents/Info.plist" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ "$MODE" == store ]]; then
    : "${FOLIANCE_APP_SIGN_IDENTITY:?Set your Mac App Distribution signing identity in the environment.}"
    : "${FOLIANCE_INSTALLER_SIGN_IDENTITY:?Set your Mac Installer Distribution signing identity in the environment.}"
    : "${FOLIANCE_TEAM_ID:?Set your Apple Developer Team ID in the environment.}"
    : "${FOLIANCE_PROVISION_PROFILE:?Set a path to the Mac App Store distribution provisioning profile.}"
    python3 scripts/store-entitlements.py "$FOLIANCE_PROVISION_PROFILE" "$FOLIANCE_TEAM_ID" "$PROJECT_DIR/.build/Store.entitlements"
    cp "$FOLIANCE_PROVISION_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
    codesign --force --options runtime --timestamp --sign "$FOLIANCE_APP_SIGN_IDENTITY" \
        --entitlements "$PROJECT_DIR/.build/Store.entitlements" "$APP_DIR"
else
    codesign --force --sign - --entitlements Config/Foliance.entitlements "$APP_DIR"
fi
codesign --verify --strict "$APP_DIR"
python3 scripts/audit-release.py "$APP_DIR"
if [[ "$MODE" == store ]]; then
    productbuild --component "$APP_DIR" /Applications \
        --sign "$FOLIANCE_INSTALLER_SIGN_IDENTITY" "$PROJECT_DIR/dist/Foliance-1.0.0.pkg"
    pkgutil --check-signature "$PROJECT_DIR/dist/Foliance-1.0.0.pkg"
fi
printf '\nBuilt %s: %s\n' "$MODE" "$APP_DIR"
