#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
PKG="cn.tydic.ethiopay.hack"
APK="FreeBirr.apk"
adb logcat -c
adb install -r -t -d "$APK" 2>&1 | tee install.log
adb push "$APK" /data/local/tmp/app.apk >/dev/null 2>&1
adb shell "pm install -r -t -d /data/local/tmp/app.apk" 2>&1 | tee install2.log
adb shell pm list packages | grep -i "tydic\|hack" > pkg.list 2>&1 || echo NOT_IN_LIST > pkg.list
if adb shell pm list packages 2>/dev/null | grep -qi "$PKG"; then echo INSTALL_OK > verdict.txt; else echo INSTALL_FAIL > verdict.txt; fi
if grep -q INSTALL_OK verdict.txt; then
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > launch.log 2>&1
  sleep 45
  adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus|mFocusedApp" > focus.txt 2>&1
  adb shell ps -A 2>/dev/null | grep -iE "hack|tydic" > proc.txt 2>&1 || echo NO_PROC > proc.txt
  adb logcat -d -b crash 2>/dev/null | tail -120 > crash.log 2>&1
  adb logcat -d 2>/dev/null | grep -iE "CoreUtils|Native|FATAL|SIGABRT|VerifyError|ndk_translation" | tail -80 > main.log 2>&1
fi
cat verdict.txt
exit 0
