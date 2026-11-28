#!/bin/bash
# Installs SceneCheck on an iPhone simulator of the newest iOS runtime, then launches it, sends it to
# the background and back twice, and opens it with a URL while it runs and from a cold start.
# Everything it logs, with screenshots and the system's log, goes to out/.

set -u
OUT="$PWD/out"
mkdir -p "$OUT"
BUNDLE=org.openfl.lime.scenecheck

step() { echo "== $1" | tee -a "$OUT/steps.txt"; }

APP=$(find Export -type d -name 'SceneCheck.app' -path '*iphonesimulator*' | head -1)
step "app: $APP"
if [ -z "$APP" ]; then exit 1; fi

# The template has no URL scheme setting, so it is added to the built app, which is then signed again
/usr/libexec/PlistBuddy \
	-c "Add :CFBundleURLTypes array" \
	-c "Add :CFBundleURLTypes:0 dict" \
	-c "Add :CFBundleURLTypes:0:CFBundleURLName string $BUNDLE" \
	-c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
	-c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string scenecheck" 	-c "Add :LSApplicationQueriesSchemes array" 	-c "Add :LSApplicationQueriesSchemes:0 string scenecheck" \
	"$APP/Info.plist"
codesign --force --sign - --timestamp=none "$APP" 2>&1 | tee -a "$OUT/steps.txt"
plutil -p "$APP/Info.plist" > "$OUT/Info.plist.txt"
otool -l "$APP/SceneCheck" | grep -A4 LC_BUILD_VERSION > "$OUT/build-version.txt" || true

RUNTIME=$(xcrun simctl list -j runtimes available | python3 -c "
import json, sys
runtimes = [r for r in json.load(sys.stdin)['runtimes'] if r['platform'] == 'iOS']
runtimes.sort(key=lambda r: [int(p) for p in r['version'].split('.')])
print(runtimes[-1]['identifier'] if runtimes else '')")
UDID=$(xcrun simctl list -j devices available | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices'].get(sys.argv[1], [])
iphones = [d for d in devices if d['name'].startswith('iPhone')]
print(iphones[0]['udid'] if iphones else '')" "$RUNTIME")
step "runtime $RUNTIME, device $UDID"
if [ -z "$UDID" ]; then exit 1; fi

xcrun simctl boot "$UDID" 2>&1 | tee -a "$OUT/steps.txt"
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$APP" 2>&1 | tee -a "$OUT/steps.txt"
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
LOG="$DATA/Documents/scenecheck.log"

shot() { xcrun simctl io "$UDID" screenshot "$OUT/$1.png" > /dev/null 2>&1 || true; }

step "launch"
xcrun simctl launch --stdout="$OUT/stdout.txt" --stderr="$OUT/stderr.txt" "$UDID" "$BUNDLE" 2>&1 | tee -a "$OUT/steps.txt"
sleep 1; shot launch-1s
sleep 9; shot launch-10s

for round in 1 2; do
	step "background $round"
	xcrun simctl launch "$UDID" com.apple.Preferences > /dev/null 2>&1
	sleep 4; shot "background-$round"
	step "foreground $round"
	xcrun simctl launch "$UDID" "$BUNDLE" 2>&1 | tee -a "$OUT/steps.txt"
	sleep 4; shot "foreground-$round"
done

# simctl openurl asks "Open in SceneCheck?", which nothing here can tap. An app that opens another
# app's URL asks no one, so SceneHelper opens SceneCheck with a URL while it isn't running
HELPER_BUNDLE=org.openfl.lime.scenehelper
HELPER=$(find ../ios-scene-helper/Export -type d -name 'SceneHelper.app' -path '*iphonesimulator*' | head -1)
step "helper: $HELPER"
/usr/libexec/PlistBuddy -c "Add :LSApplicationQueriesSchemes array" -c "Add :LSApplicationQueriesSchemes:0 string scenecheck" "$HELPER/Info.plist"
codesign --force --sign - --timestamp=none "$HELPER" 2>&1 | tee -a "$OUT/steps.txt"
xcrun simctl install "$UDID" "$HELPER" 2>&1 | tee -a "$OUT/steps.txt"

step "cold URL, from SceneHelper"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>&1 | tee -a "$OUT/steps.txt"
sleep 2
xcrun simctl launch --stdout="$OUT/helper-stdout.txt" "$UDID" "$HELPER_BUNDLE" 2>&1 | tee -a "$OUT/steps.txt"
sleep 3; shot cold-helper-3s
sleep 9; shot cold-helper-12s

cp "$LOG" "$OUT/scenecheck.log" 2>/dev/null || echo "(no log)" > "$OUT/scenecheck.log"
xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate 'process == "SceneCheck"' > "$OUT/system-log.txt" 2>&1 || true
find ~/Library/Logs/DiagnosticReports -name 'SceneCheck*' -exec cp {} "$OUT/" \; 2>/dev/null || true

echo "---- scenecheck.log"
cat "$OUT/scenecheck.log"
echo "---- steps"
cat "$OUT/steps.txt"
echo "---- last lines of the system log"
tail -40 "$OUT/system-log.txt"
