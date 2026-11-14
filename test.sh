#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
PKG="cn.tydic.ethiopay.hack"
APK="FreeBirr.apk"
log(){ echo "$@"; }

log "===== 0) SANITY ====="
ls -la "$APK"; sha256sum "$APK"
log "=== device storage ==="
adb shell df -h 2>/dev/null | head -6 | tee df.txt
log "=== NDK translation engine present? ==="
adb shell "echo '--- engine dir (arm64) ---'; ls -la /system/lib64/ndk_translation/arm64/ 2>&1 | head; echo '--- aarch64 alt ---'; ls -d /system/lib64/ndk_translation 2>&1; echo '--- libndk_translation.so ---'; ls -la /system/lib64/libndk_translation.so 2>&1; echo '--- ndk prop ---'; getprop 2>/dev/null | grep -i ndk" | tee ndk.txt

log "===== 1) INSTALL (clear logcat first, verbose) ====="
adb logcat -c
adb install -r -t -d "$APK" 2>&1 | tee install.log
log "install exit=$?"
adb logcat -d -v brief 2>/dev/null | grep -iE "INSTALL|native|extract|pkg|ndk|translation|abi|Failed to|FATAL|PackageManager" | tail -60 > install_trace.log
cat install_trace.log

log "===== 1b) RETRY install from pushed path ====="
adb push "$APK" /data/local/tmp/app.apk 2>&1 | tail -1
adb shell "pm install -r -t -d /data/local/tmp/app.apk" 2>&1 | tee install2.log

log "===== 2) PACKAGE CHECK ====="
adb shell pm list packages | grep -i "tydic\|hack" > pkg.list 2>&1 || echo "NOT_IN_LIST" > pkg.list
cat pkg.list

VERDICT="INSTALL_FAIL"
if adb shell pm list packages 2>/dev/null | grep -qi "$PKG"; then VERDICT="INSTALL_OK"; log "INSTALL_OK"; else log "INSTALL_FAIL"; fi

if [ "$VERDICT" = "INSTALL_OK" ]; then
  log "===== 3) LAUNCH ====="
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 2>&1 | tee launch.log
  log "===== 4) WAIT 30s ====="; sleep 30
  log "===== 5) FOCUS ====="
  adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus|mFocusedApp" > focus.txt 2>&1; cat focus.txt
  if grep -qi "$PKG" focus.txt; then echo "FOCUS_OK"; else echo "FOCUS_NO"; fi
  log "===== 6) PROC ====="
  adb shell ps -A 2>/dev/null | grep -iE "hack|tydic" > proc.txt 2>&1 || echo "NO_PROC" > proc.txt; cat proc.txt
  log "===== 7) CRASH ====="; adb logcat -d -b crash 2>/dev/null | tail -100 > crash.log 2>&1
  log "===== 8) MAIN LOGCAT ====="
  adb logcat -d 2>/dev/null | grep -iE "$PKG|hack|tydic|FreeBirr|AndroidRuntime|FATAL|Exception|huawei|offline" | tail -150 > main.log 2>&1
fi

log "===== VERDICT ====="; echo "$VERDICT" > verdict.txt; cat verdict.txt
exit 0
