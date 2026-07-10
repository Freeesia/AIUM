#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LANGUAGE="${1:-ja}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/artifacts/app-store/screenshots/$LANGUAGE}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-/private/tmp/AIUM-app-store-screenshots}"
BUNDLE_ID="com.studiofreesia.aium"
TARGET_WIDTH=1284
TARGET_HEIGHT=2778

case "$LANGUAGE" in
    ja)
        LOCALE="ja_JP"
        ;;
    en)
        LOCALE="en_US"
        ;;
    *)
        echo "Usage: $0 [ja|en]" >&2
        exit 2
        ;;
esac

if [[ -z "${SIMULATOR_UDID:-}" ]]; then
    BOOTED_IPHONES="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone .*\(Booted\)/ { print $2 }')"
    BOOTED_COUNT="$(printf '%s\n' "$BOOTED_IPHONES" | awk 'NF { count += 1 } END { print count + 0 }')"
    if [[ "$BOOTED_COUNT" -ne 1 ]]; then
        echo "Start exactly one supported high-resolution iPhone Simulator, or set SIMULATOR_UDID." >&2
        exit 1
    fi
    SIMULATOR_UDID="$BOOTED_IPHONES"
fi

DEVICE_LINE="$(xcrun simctl list devices | awk -v udid="$SIMULATOR_UDID" 'index($0, udid) { print; exit }')"
case "$DEVICE_LINE" in
    *"iPhone Air"*|*"iPhone 17 Pro Max"*|*"iPhone 16 Pro Max"*|*"iPhone 16 Plus"*|*"iPhone 15 Pro Max"*|*"iPhone 15 Plus"*|*"iPhone 14 Pro Max"*)
        ;;
    *)
        echo "The selected Simulator is not an accepted high-resolution capture device: $DEVICE_LINE" >&2
        exit 1
        ;;
esac

mkdir -p "$OUTPUT_DIR"

cd "$ROOT_DIR"
xcodegen generate
xcodebuild -quiet \
    -project AIUM.xcodeproj \
    -scheme AIUM \
    -configuration Debug \
    -destination "id=$SIMULATOR_UDID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug-iphonesimulator/AIUM.app"
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl status_bar "$SIMULATOR_UDID" override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --operatorName "" \
    --batteryState charged \
    --batteryLevel 100

capture() {
    local filename="$1"
    shift

    xcrun simctl launch --terminate-running-process \
        "$SIMULATOR_UDID" \
        "$BUNDLE_ID" \
        -AppleLanguages "($LANGUAGE)" \
        -AppleLocale "$LOCALE" \
        -demo_mode_enabled YES \
        "$@" >/dev/null
    sleep 3
    xcrun simctl io "$SIMULATOR_UDID" screenshot --type=png "$OUTPUT_DIR/$filename"

    local width
    local height
    width="$(sips -g pixelWidth "$OUTPUT_DIR/$filename" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$OUTPUT_DIR/$filename" | awk '/pixelHeight/ { print $2 }')"
    case "${width}x${height}" in
        1242x2688|1260x2736|1284x2778|1290x2796|1320x2868)
            ;;
        *)
            echo "Unexpected screenshot size for $filename: ${width}x${height}" >&2
            exit 1
            ;;
    esac

    sips --resampleWidth "$TARGET_WIDTH" "$OUTPUT_DIR/$filename" >/dev/null
    sips --cropToHeightWidth "$TARGET_HEIGHT" "$TARGET_WIDTH" "$OUTPUT_DIR/$filename" >/dev/null

    width="$(sips -g pixelWidth "$OUTPUT_DIR/$filename" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$OUTPUT_DIR/$filename" | awk '/pixelHeight/ { print $2 }')"
    if [[ "${width}x${height}" != "${TARGET_WIDTH}x${TARGET_HEIGHT}" ]]; then
        echo "Unexpected final screenshot size for $filename: ${width}x${height}" >&2
        exit 1
    fi
}

capture "01-dashboard.png"
capture "02-settings.png" -AIUMShowSettings

printf 'Created App Store screenshots in %s\n' "$OUTPUT_DIR"
