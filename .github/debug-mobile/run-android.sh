#!/bin/bash
# Installs the unit tests in the emulator, runs them and prints what they log
set -u
package=org.openfl.lime.tests
apk=$(find tests/unit/Export -name "*.apk" | grep -i debug | head -1)
[ -n "$apk" ] || apk=$(find tests/unit/Export -name "*.apk" | head -1)
echo "Installing $apk"
adb install -r "$apk" || exit 1
adb logcat -c
adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1
started=0
for i in $(seq 1 900); do
	adb logcat -d > logcat.txt
	grep -q "results:" logcat.txt && break
	if adb shell pidof "$package" > /dev/null; then started=1; elif [ $started = 1 ] || [ $i -gt 60 ]; then echo "The app is not running"; break; fi
	sleep 1
done
sleep 3
adb logcat -d > logcat.txt
grep -E "Running |results:|assertations|successes|errors:|failures|FAILURE|ERROR| OK |With reason|line:|missed async|AndroidRuntime|DEBUG|libc|SIGSEGV|SIGABRT|Abort" logcat.txt | tail -600
grep -q "ALL TESTS OK" logcat.txt
