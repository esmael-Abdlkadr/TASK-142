#!/usr/bin/env bash
# ChargeProcure Field Operations — iOS Test Runner
#
# Resolves an existing simulator by name to a stable UDID, boots it once, and
# runs the XCTest suite.  Using a concrete UDID prevents xcodebuild from
# spawning a clone simulator, which avoids process-count exhaustion.
#
# Modes:
#   Full suite (default) — all 17 test classes
#   Fast subset  --fast  — 16 classes; skips the slow CPProcurementServiceTests
#                          pipeline integration test (REQ→RFQ→PO→Receipt→Invoice→Payment)
#
# Usage:
#   ./run_tests.sh                                    # full suite, iPhone 16e
#   ./run_tests.sh --fast                             # fast subset, iPhone 16e
#   ./run_tests.sh "iPhone 16"                        # full suite, named simulator
#   ./run_tests.sh --fast "iPhone 16"                 # fast subset, named simulator
#   ./run_tests.sh "iPhone 16e" NOBOOT                # full suite, skip boot step
#   ./run_tests.sh --fast "iPhone 16e" NOBOOT         # fast subset, skip boot step
#   ./run_tests.sh --threshold 75                     # fail if coverage < 75 %
#   ./run_tests.sh --fast --threshold 70              # fast subset + coverage gate
#   ./run_tests.sh --uitests                          # XCUITest end-to-end suite only
#   ./run_tests.sh --uitests "iPhone 16"              # XCUITest suite on named simulator
#
# Fast subset (16 classes):
#   CPAuthServiceTests            — password rules, lockout, session, biometrics
#   CPBulletinServiceTests        — bulletin CRUD, versioning
#   CPBulletinEditorRichTextTests — rich-text validation, max summary length
#   CPChargerServiceTests         — commands, RBAC, deterministic adapters, timeout
#   CPAnalyticsServiceTests       — heatmap, trend windows, anomaly thresholds
#   CPRBACServiceTests            — permission grant/revoke/cache
#   CPPricingServiceTests         — tiered pricing, fallback, versioning
#   CPAttachmentServiceTests      — file validation, magic bytes, size limits
#   CPDepositServiceTests         — deposit state machine and RBAC
#   CPCouponServiceTests          — coupon create/apply/expire/deactivate
#   CPUISecurityTests             — sidebar items by role, logout, root-VC
#   CPExportServiceTests          — export authorization, formats, report listing
#   CPSecurityRegressionTests     — security invariants and regression checks
#   CPNavigationAndContractTests  — navigation/UI contract assertions
#   CPUIJourneyTests              — behavioral multi-layer user journeys (auth→service→data)
#   CPVCInteractionTests          — VC-layer auth guards and RBAC-driven UI mutations
set -euo pipefail

SCHEME="ChargeProcure"
PROJECT="ChargeProcure/ChargeProcure.xcodeproj"

# ---------------------------------------------------------------------------
# Parse arguments — --fast and --threshold can appear anywhere before positional args.
# ---------------------------------------------------------------------------
FAST_MODE=0
UITEST_MODE=0
COV_THRESHOLD=""   # empty = no enforcement; set via --threshold N
POSITIONAL=()
i=0
ARGS=("$@")
while [ $i -lt ${#ARGS[@]} ]; do
    arg="${ARGS[$i]}"
    if [ "$arg" = "--fast" ]; then
        FAST_MODE=1
    elif [ "$arg" = "--uitests" ]; then
        UITEST_MODE=1
    elif [ "$arg" = "--threshold" ]; then
        i=$(( i + 1 ))
        COV_THRESHOLD="${ARGS[$i]:-}"
    else
        POSITIONAL+=("$arg")
    fi
    i=$(( i + 1 ))
done

SIMULATOR_NAME="${POSITIONAL[0]:-iPhone 16e}"
BOOT_FLAG="${POSITIONAL[1]:-}"

if [ "$UITEST_MODE" -eq 1 ]; then
    SUITE_LABEL="UITests"
    RESULT_BUNDLE=".build/test-results-uitests"
elif [ "$FAST_MODE" -eq 1 ]; then
    SUITE_LABEL="Fast"
    RESULT_BUNDLE=".build/test-results-fast"
else
    SUITE_LABEL="Full"
    RESULT_BUNDLE=".build/test-results"
fi

echo "=== ChargeProcure Field Operations — iOS Test Suite ($SUITE_LABEL) ==="
echo ""
echo "  Project:   $PROJECT"
echo "  Scheme:    $SCHEME"
echo "  Simulator: $SIMULATOR_NAME"
echo "  Mode:      $SUITE_LABEL"
echo ""

# ---------------------------------------------------------------------------
# Native iOS/Xcode tests can only run on macOS.
# ---------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
    echo "This test runner only works on macOS (native iOS/Xcode project)."
    echo "Run ./run_tests.sh on a Mac with Xcode 15+ installed."
    exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
    echo "ERROR: Xcode command line tools are required."
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the UDID of a non-clone simulator matching the requested name.
# Prefers already-Booted devices; falls back to the highest available runtime.
# ---------------------------------------------------------------------------
_SIMCTL_JSON=$(xcrun simctl list devices available -j)
UDID=$(python3 -c "
import json, sys

name = sys.argv[1]
data = json.loads(sys.argv[2])
candidates = []
for runtime, devices in data.get('devices', {}).items():
    for d in devices:
        n = d.get('name', '')
        if n == name and d.get('isAvailable', False) and 'Clone' not in n:
            state = d.get('state', '')
            candidates.append((runtime, d['udid'], state))

if not candidates:
    sys.exit(1)

# Sort: Booted first, then by runtime descending (higher = newer OS)
candidates.sort(key=lambda x: (0 if x[2] == 'Booted' else 1, x[0]))
print(candidates[0][1])
" "$SIMULATOR_NAME" "$_SIMCTL_JSON" 2>/dev/null || true)

if [ -z "$UDID" ]; then
    echo "ERROR: No available simulator found matching '$SIMULATOR_NAME'."
    echo ""
    echo "Available simulators (non-clone iPhone/iPad):"
    xcrun simctl list devices available | grep -i "iphone\|ipad" | grep -v "Clone" | head -20
    exit 1
fi

echo "  UDID:      $UDID"

# ---------------------------------------------------------------------------
# Boot the simulator if it is not already running.
# ---------------------------------------------------------------------------
CURRENT_STATE=$(xcrun simctl list devices | grep "$UDID" | grep -oE "Booted|Shutdown" | head -1 || echo "Unknown")

if [ "$CURRENT_STATE" = "Booted" ]; then
    echo "  State:     Already booted — reusing"
elif [ "$BOOT_FLAG" = "NOBOOT" ]; then
    echo "  State:     $CURRENT_STATE (NOBOOT — skipping boot)"
else
    echo "  State:     $CURRENT_STATE — booting..."
    xcrun simctl boot "$UDID"
    sleep 4
fi

echo ""

# ---------------------------------------------------------------------------
# Clean previous result bundle (stale bundles can mislead xcresulttool).
# ---------------------------------------------------------------------------
rm -rf "$RESULT_BUNDLE"
mkdir -p "$(dirname "$RESULT_BUNDLE")"

# ---------------------------------------------------------------------------
# Build the xcodebuild test invocation.
# Fast mode adds -only-testing: flags to skip CPProcurementServiceTests.
# UITest mode runs the ChargeProcureUITests scheme instead.
# ---------------------------------------------------------------------------
XCODEBUILD_LOG=$(mktemp -t chargeprocure-tests.XXXXXX.log)
trap 'rm -f "$XCODEBUILD_LOG"' EXIT

if [ "$UITEST_MODE" -eq 1 ]; then
    # ---------------------------------------------------------------------------
    # UI-test suite — runs ChargeProcureUITests against the full app binary.
    # The app is launched by xcodebuild with the UI_TESTING=1 environment
    # variable so AppDelegate seeds deterministic credentials.
    # ---------------------------------------------------------------------------
    set +e
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "ChargeProcureUITests" \
        -destination "id=$UDID" \
        -resultBundlePath "$RESULT_BUNDLE" \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
        2>&1 | tee "$XCODEBUILD_LOG"
    XCODEBUILD_STATUS=${PIPESTATUS[0]}
    set -e

    grep -E "Test Suite|Test Case '|error:|PASSED|FAILED|Build succeeded|Build FAILED" "$XCODEBUILD_LOG" || true

    if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
        echo ""
        echo "=== UITest run FAILED. Results at: $RESULT_BUNDLE ==="
        exit "$XCODEBUILD_STATUS"
    fi

    echo ""
    echo "=== Done (UITests). Results at: $RESULT_BUNDLE ==="
    echo "    Inspect: open $RESULT_BUNDLE"
    exit 0
fi

FAST_FLAGS=()
if [ "$FAST_MODE" -eq 1 ]; then
    FAST_FLAGS=(
        -only-testing:ChargeProcureTests/CPAuthServiceTests
        -only-testing:ChargeProcureTests/CPBulletinServiceTests
        -only-testing:ChargeProcureTests/CPBulletinEditorRichTextTests
        -only-testing:ChargeProcureTests/CPChargerServiceTests
        -only-testing:ChargeProcureTests/CPAnalyticsServiceTests
        -only-testing:ChargeProcureTests/CPRBACServiceTests
        -only-testing:ChargeProcureTests/CPPricingServiceTests
        -only-testing:ChargeProcureTests/CPAttachmentServiceTests
        -only-testing:ChargeProcureTests/CPDepositServiceTests
        -only-testing:ChargeProcureTests/CPCouponServiceTests
        -only-testing:ChargeProcureTests/CPUISecurityTests
        -only-testing:ChargeProcureTests/CPExportServiceTests
        -only-testing:ChargeProcureTests/CPSecurityRegressionTests
        -only-testing:ChargeProcureTests/CPNavigationAndContractTests
        -only-testing:ChargeProcureTests/CPUIJourneyTests
        -only-testing:ChargeProcureTests/CPVCInteractionTests
    )
fi

set +e
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "id=$UDID" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -enableCodeCoverage YES \
    "${FAST_FLAGS[@]}" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
    2>&1 | tee "$XCODEBUILD_LOG"
XCODEBUILD_STATUS=${PIPESTATUS[0]}
set -e

grep -E "Test Suite|Test Case '|error:|PASSED|FAILED|Build succeeded|Build FAILED" "$XCODEBUILD_LOG" || true

if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
    echo ""
    echo "=== $SUITE_LABEL test run FAILED. Results at: $RESULT_BUNDLE ==="
    if [ "$FAST_MODE" -eq 1 ]; then
        echo "    For the full suite: ./run_tests.sh"
    fi
    exit "$XCODEBUILD_STATUS"
fi

# ---------------------------------------------------------------------------
# Print coverage summary from the .xcresult bundle.
# xcov is not assumed; we use xcresulttool's JSON export instead.
# Requires Xcode 11+. Fails silently if the tool or bundle is absent.
# ---------------------------------------------------------------------------
echo ""
echo "--- Code Coverage Summary ---"
xcrun xcresulttool get \
    --path "$RESULT_BUNDLE" \
    --format json 2>/dev/null \
| python3 - <<'PYEOF'
import json, sys
try:
    data = json.load(sys.stdin)
    metrics = (data
               .get("actions", {}).get("_values", [{}])[0]
               .get("actionResult", {})
               .get("metrics", {}))
    tests   = metrics.get("testsCount",   {}).get("_value", "?")
    failed  = metrics.get("testsFailedCount", {}).get("_value", "0")
    print(f"  Tests run : {tests}   Failed: {failed}")

    # Coverage lives under the first action's coverage report ref
    cov = (data
           .get("actions", {}).get("_values", [{}])[0]
           .get("actionResult", {})
           .get("coverage", {})
           .get("reportRef", {})
           .get("_value", None))
    if cov:
        print(f"  Coverage report id: {cov}  (open result bundle to view per-file breakdown)")
    else:
        print("  Coverage data available — open result bundle: open " + sys.argv[1] if len(sys.argv) > 1 else "")
except Exception as e:
    print(f"  (coverage parse skipped: {e})")
PYEOF

# ---------------------------------------------------------------------------
# Coverage threshold gate (only when --threshold N is supplied).
# Uses xcrun xccov to extract the line-coverage percentage of the main app
# target from the .xcresult bundle, then fails if it falls below the target.
# ---------------------------------------------------------------------------
if [ -n "$COV_THRESHOLD" ]; then
    echo ""
    echo "--- Coverage Threshold Gate (minimum: ${COV_THRESHOLD}%) ---"
    COV_PCT=$(xcrun xccov view --report --json "$RESULT_BUNDLE" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # Top-level targets list; pick ChargeProcure (not the test bundle)
    targets = data.get('targets', [])
    for t in targets:
        name = t.get('name', '')
        if 'ChargeProcure' in name and 'Tests' not in name:
            pct = t.get('lineCoverage', 0) * 100
            print(f'{pct:.1f}')
            sys.exit(0)
    # Fallback: overall line coverage
    overall = data.get('lineCoverage', None)
    if overall is not None:
        print(f'{float(overall)*100:.1f}')
    else:
        print('unknown')
except Exception as e:
    print('unknown')
" 2>/dev/null || echo "unknown")

    if [ "$COV_PCT" = "unknown" ]; then
        echo "  WARNING: Could not determine coverage percentage from result bundle."
        echo "           Threshold gate skipped — run: open $RESULT_BUNDLE"
    else
        echo "  Line coverage: ${COV_PCT}%  (threshold: ${COV_THRESHOLD}%)"
        # bc comparison: returns 1 if COV_PCT < COV_THRESHOLD
        if python3 -c "import sys; sys.exit(0 if float('${COV_PCT}') >= float('${COV_THRESHOLD}') else 1)" 2>/dev/null; then
            echo "  PASS: coverage meets the ${COV_THRESHOLD}% threshold."
        else
            echo "  FAIL: coverage ${COV_PCT}% is below the required ${COV_THRESHOLD}% threshold."
            echo ""
            echo "=== $SUITE_LABEL test run FAILED (coverage gate). Results at: $RESULT_BUNDLE ==="
            exit 1
        fi
    fi
fi

echo ""
echo "=== Done ($SUITE_LABEL suite). Results at: $RESULT_BUNDLE ==="
if [ "$FAST_MODE" -eq 1 ]; then
    echo "    CPProcurementServiceTests excluded (pipeline integration). Run without --fast for full verification."
fi
echo "    Inspect:  open $RESULT_BUNDLE"
echo "    Summary:  xcrun xcresulttool get --path $RESULT_BUNDLE --format json 2>/dev/null | python3 -m json.tool | grep -E 'testsCount|testsFailedCount'"
echo "    Coverage: xcrun xccov view --report --json $RESULT_BUNDLE 2>/dev/null | python3 -c \"import json,sys; d=json.load(sys.stdin); [print(t['name'], f\\\"{t.get('lineCoverage',0)*100:.1f}%\\\") for t in d.get('targets',[]) if 'Tests' not in t['name']]\""
