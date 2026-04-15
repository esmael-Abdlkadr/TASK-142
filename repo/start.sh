#!/usr/bin/env bash
# start.sh — Builds and launches the ChargeProcure iOS app in the simulator.
#
# Usage:
#   ./start.sh                  # uses default simulator (iPhone 17)
#   ./start.sh "iPhone 16e"     # use a specific simulator name
#
# Requirements: macOS, Xcode
# No Docker or backend server is required — the app is fully offline.

set -euo pipefail

SCHEME="ChargeProcure"
BUNDLE_ID="com.chargeprocure.fieldops"
SIMULATOR_NAME="${1:-iPhone 17}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCPROJECT="$PROJECT_DIR/ChargeProcure/ChargeProcure.xcodeproj"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "$(date '+%H:%M:%S') [start] $*"; }
die()  { echo "$(date '+%H:%M:%S') [error] $*" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' not found — is $2 installed?"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require xcodebuild "Xcode"
require xcrun      "Xcode"

# ---------------------------------------------------------------------------
# 1. Boot the iOS Simulator
# ---------------------------------------------------------------------------
log "Locating simulator: '$SIMULATOR_NAME'…"
SIM_UDID=$(xcrun simctl list devices available -j \
    | python3 -c "
import sys, json
devs = json.load(sys.stdin)['devices']
for runtime, devices in devs.items():
    for d in devices:
        if d.get('name') == '$SIMULATOR_NAME' and d.get('isAvailable', False):
            print(d['udid'])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null) || die "Simulator '$SIMULATOR_NAME' not found. Run 'xcrun simctl list devices available' to see options."

log "Simulator UDID: $SIM_UDID"

STATE=$(xcrun simctl list devices -j \
    | python3 -c "
import sys, json
devs = json.load(sys.stdin)['devices']
for devices in devs.values():
    for d in devices:
        if d['udid'] == '$SIM_UDID':
            print(d['state'])
            sys.exit(0)
")

if [ "$STATE" != "Booted" ]; then
    log "Booting simulator…"
    xcrun simctl boot "$SIM_UDID"
fi

log "Opening Simulator app…"
open -a Simulator

# Give Simulator a moment to finish booting its UI
log "Waiting for simulator to finish booting…"
xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 2. Build the iOS app
# ---------------------------------------------------------------------------
log "Building $SCHEME (this may take a minute)…"
BUILD_DIR="$PROJECT_DIR/.build/ios"
mkdir -p "$BUILD_DIR"

xcodebuild build \
    -project "$XCPROJECT" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -configuration Debug \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    -quiet \
    | grep -E "error:|warning:|Build succeeded|Build failed" || true

# Confirm the .app exists
APP_PATH=$(find "$BUILD_DIR" -maxdepth 1 -name "*.app" | head -1)
[ -n "$APP_PATH" ] || die "Build failed — .app not found in $BUILD_DIR"
log "Built: $APP_PATH"

# ---------------------------------------------------------------------------
# 3. Install and launch
# ---------------------------------------------------------------------------
log "Installing app on simulator…"
xcrun simctl install "$SIM_UDID" "$APP_PATH"

log "Launching ${BUNDLE_ID}..."
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

# ---------------------------------------------------------------------------
log ""
log "Done."
log "  iOS app : running in '$SIMULATOR_NAME' simulator"
log ""
log "To stop the sim: xcrun simctl shutdown $SIM_UDID"
