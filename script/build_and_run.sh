#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIUM_BUILD_DIR="${AIUM_MAC_DERIVED_DATA:-$ROOT_DIR/build/macos}"
AIUM_BUILD_CONFIGURATION="${AIUM_MAC_CONFIGURATION:-Debug}"
AIUM_SIGNING_ALLOWED="${AIUM_MAC_CODE_SIGNING_ALLOWED:-YES}"
APP_BUNDLE="$AIUM_BUILD_DIR/Build/Products/$AIUM_BUILD_CONFIGURATION/AIUM.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/AIUM"
MODE=run
DEMO_MODE=false

for argument in "$@"; do
    case "$argument" in
        --verify|--debug|--logs|--telemetry) MODE="$argument" ;;
        --demo) DEMO_MODE=true ;;
        *)
            echo "Usage: $0 [--verify|--debug|--logs|--telemetry] [--demo]" >&2
            exit 2
            ;;
    esac
done

mac_app_pids() {
    local candidate
    local executable
    while read -r candidate; do
        [[ -n "$candidate" ]] || continue
        executable="$(ps -p "$candidate" -o comm= 2>/dev/null || true)"
        if [[ "$executable" == "$APP_BINARY" ]]; then
            echo "$candidate"
        fi
    done < <(pgrep -x AIUM || true)
}

open_app() {
    if [[ "$DEMO_MODE" == true ]]; then
        /usr/bin/open -n "$APP_BUNDLE" --args -demo_mode_enabled YES
    else
        /usr/bin/open -n "$APP_BUNDLE"
    fi
}

# Only stop this build's Mac app; iOS Simulator processes have the same name.
while read -r app_pid; do
    [[ -z "$app_pid" ]] || kill "$app_pid"
done < <(mac_app_pids)

cd "$ROOT_DIR"
xcodegen generate
xcodebuild -quiet \
    -project AIUM.xcodeproj \
    -scheme AIUMMac \
    -configuration "$AIUM_BUILD_CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$AIUM_BUILD_DIR" \
    CODE_SIGNING_ALLOWED="$AIUM_SIGNING_ALLOWED" \
    build

case "$MODE" in
    --debug)
        if [[ "$DEMO_MODE" == true ]]; then
            lldb -- "$APP_BINARY" -demo_mode_enabled YES
        else
            lldb -- "$APP_BINARY"
        fi
        ;;
    --logs|--telemetry)
        open_app
        /usr/bin/log stream --info --style compact \
            --predicate 'subsystem == "com.studiofreesia.aium"'
        ;;
    --verify)
        open_app
        for attempt in 1 2 3 4 5; do
            if [[ -n "$(mac_app_pids)" ]]; then
                echo "AIUM is running: $APP_BUNDLE"
                exit 0
            fi
            sleep 1
        done
        echo "AIUM did not remain running after launch." >&2
        exit 1
        ;;
    run)
        open_app
        ;;
esac
