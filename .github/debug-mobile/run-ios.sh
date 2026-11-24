#!/bin/bash
# Installs the unit tests in a simulator, runs them and prints what they write
set -u
app=$(find tests/unit/Export/ios -name "*.app" -path "*iphonesimulator*" | head -1)
echo "App: $app"
[ -n "$app" ] || exit 1
device=$(xcrun simctl list devices available | grep -E "^ +iPhone" | head -1 | grep -oE "[0-9A-F-]{36}")
echo "Device: $device"
xcrun simctl boot "$device"
xcrun simctl install "$device" "$app" || exit 1
bundle=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$app/Info.plist")
perl -e 'alarm shift; exec @ARGV' 900 xcrun simctl launch --console-pty "$device" "$bundle" > ios.txt 2>&1
grep -E "Running |results:|assertations|successes|errors:|failures|FAILURE|ERROR| OK |With reason|line:|missed async" ios.txt | tail -600
grep -q "ALL TESTS OK" ios.txt
