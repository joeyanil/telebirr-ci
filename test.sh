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

log "===== 1c) DEXOPT / DEX2OAT CHECK (our classes) ====="
adb logcat -c
adb shell "cmd package compile -m verify --uninstall-existing -f $PKG 2>&1" 2>/dev/null | tail -40 > dexopt.log || true
adb logcat -d 2>/dev/null | grep -iE "dex2oat|dexopt|Rejected|Verif|cn.tydic" | tail -80 >> dexopt.log 2>&1
cat dexopt.log || echo "no dexopt log"

log "===== 2) PACKAGE CHECK ====="
adb shell pm list packages | grep -i "tydic\|hack" > pkg.list 2>&1 || echo "NOT_IN_LIST" > pkg.list
cat pkg.list
log "===== 2b) DUMPSYS PACKAGE ====="
adb shell "dumpsys package $PKG" 2>/dev/null | grep -iE "versionName|codePath|firstInstallTime|signatures|Sealed|legacyNative" | head -30 > pkg_dump.txt 2>&1
adb shell "dumpsys package $PKG" 2>/dev/null > pkg_dump_full.txt
cat pkg_dump.txt 2>/dev/null || true

VERDICT="INSTALL_FAIL"
if adb shell pm list packages 2>/dev/null | grep -qi "$PKG"; then VERDICT="INSTALL_OK"; log "INSTALL_OK"; else log "INSTALL_FAIL"; fi

if [ "$VERDICT" = "INSTALL_OK" ]; then
  log "===== 3) LAUNCH ====="
  adb logcat -c
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 2>&1 | tee launch.log
  log "===== 4) WAIT 90s (let background threads run) ====="; sleep 90
  log "===== 5) FOCUS ====="
  adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus|mFocusedApp" > focus.txt 2>&1; cat focus.txt
  if grep -qi "$PKG" focus.txt; then echo "FOCUS_OK"; else echo "FOCUS_NO"; fi
  log "===== 6) PROC ====="
  adb shell ps -A 2>/dev/null | grep -iE "hack|tydic" > proc.txt 2>&1 || echo "NO_PROC" > proc.txt; cat proc.txt
  log "===== 6b) PROC AGAIN (+30s) ====="
  sleep 30
  adb shell ps -A 2>/dev/null | grep -iE "hack|tydic" > proc2.txt 2>&1 || echo "NO_PROC" > proc2.txt; cat proc2.txt
  log "===== 7) CRASH ====="; adb logcat -d -b crash 2>/dev/null | tail -200 > crash.log 2>&1
  log "===== 8) MAIN LOGCAT (wide net) ====="
  adb logcat -d 2>/dev/null | grep -iE "$PKG|hack|tydic|FreeBirr|AndroidRuntime|FATAL|Exception|huawei|offline|aegis|SecureDetect|SIGABRT|SIGSEGV" | tail -300 > main.log 2>&1
  log "===== 8b) OUR CLASS MARKERS (did our code run?) ====="
  adb logcat -d 2>/dev/null | grep -iE "OfflineInterceptor|FakeData|FakeState|BalanceEditor|com.huawei.offline|J2\.c|tb_offline|check sign" > our.log 2>&1
  wc -l our.log 2>/dev/null; tail -20 our.log 2>/dev/null
fi

log "===== VERDICT ====="; echo "$VERDICT" > verdict.txt; cat verdict.txt
exit 0
