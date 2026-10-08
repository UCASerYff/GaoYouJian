#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -gt 0 ]]; then
  [[ $# == 1 && "$1" == '--defer-cleanup' ]] || { print -u2 '用法：install.sh [--defer-cleanup]'; exit 1; }
fi
APP_VERSION="$(tr -d '\n' < "$PROJECT_DIR/VERSION")"
[[ "$APP_VERSION" =~ '^[0-9]+\.[0-9]{2}$' ]] || { print -u2 '无效的版本号'; exit 1; }
PACKAGE="$PROJECT_DIR/Release/GaoYouJian-$APP_VERSION.dmg"
DESTINATION='/Applications/搞邮件.app'
NEW_APP="/Applications/.GaoYouJian-install-$$.app"
OLD_APP="/Applications/.GaoYouJian-previous-$$.app"
IDENTIFIER='com.gaoseries.GaoYouJian'
EXECUTABLE="$DESTINATION/Contents/MacOS/GaoYouJian"
INSTALL_WORK="$(mktemp -d /private/tmp/gaoyoujian-install.XXXXXX)"
MOUNT="$INSTALL_WORK/mount"
mkdir -p "$MOUNT"
MOUNTED=false
REPLACED=false
COMMITTED=false
validate() {
  [[ -d "$1" && ! -L "$1" ]] || { print -u2 "不是普通应用目录：$1"; return 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" == "$IDENTIFIER" ]] || { print -u2 "应用标识不符：$1"; return 1; }
  codesign --verify --strict "$1"
}
request_quit() {
  swift -module-cache-path "$INSTALL_WORK/cache" "$PROJECT_DIR/Scripts/QuitApp.swift" "$DESTINATION"
}
wait_until_stopped() {
  for ATTEMPT in {1..50}; do
    pgrep -f "^$EXECUTABLE([[:space:]]|$)" >/dev/null || return 0
    sleep 0.2
  done
  return 1
}
cleanup() {
  local RESULT=$?
  if ! $COMMITTED; then
    if $REPLACED && [[ -e "$DESTINATION" ]] && validate "$DESTINATION"; then
      request_quit || true
      if wait_until_stopped; then
        rm -rf "$DESTINATION"
      else
        print -u2 "新版仍在处理任务，保留应用及上一版备份：$OLD_APP"
      fi
    fi
    if [[ -e "$OLD_APP" && ! -e "$DESTINATION" ]] && validate "$OLD_APP"; then
      mv "$OLD_APP" "$DESTINATION"
      open "$DESTINATION" 2>/dev/null || true
      print -u2 '安装未完成，已恢复上一版。'
    fi
    if [[ -e "$NEW_APP" ]] && validate "$NEW_APP"; then rm -rf "$NEW_APP"; fi
  fi
  if $MOUNTED; then hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; fi
  rm -rf "$INSTALL_WORK/cache"
  rmdir "$MOUNT" 2>/dev/null || true
  rmdir "$INSTALL_WORK" 2>/dev/null || true
  return "$RESULT"
}
trap cleanup EXIT
[[ -f "$PACKAGE" && ! -L "$PROJECT_DIR/Release" ]] || { print -u2 '缺少当前版本安装包，请先构建'; exit 1; }
[[ ! -e "$NEW_APP" && ! -L "$NEW_APP" && ! -e "$OLD_APP" && ! -L "$OLD_APP" ]] || { print -u2 '临时安装目录已存在，请检查后重试'; exit 1; }
(cd "$PROJECT_DIR/Release" && shasum -a 256 -c "GaoYouJian-$APP_VERSION.dmg.sha256")
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$PACKAGE"
MOUNTED=true
SOURCE="$MOUNT/搞邮件.app"
validate "$SOURCE"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE/Contents/Info.plist")" == "$APP_VERSION" ]] || { print -u2 '安装包内版本号不符'; exit 1; }
if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then validate "$DESTINATION"; fi
ditto "$SOURCE" "$NEW_APP"
validate "$NEW_APP"
# Respect the app's send/draft guards; never force termination during an update.
request_quit
if ! wait_until_stopped; then print -u2 '旧程序尚未退出，已中止安装并保留原应用；请完成发送或保存后重试。'; exit 1; fi
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$OLD_APP"; fi
mv "$NEW_APP" "$DESTINATION"
REPLACED=true
validate "$DESTINATION"
open "$DESTINATION"
sleep 3
if ! pgrep -f "^$EXECUTABLE([[:space:]]|$)" >/dev/null; then print -u2 '新版未正常启动'; exit 1; fi
COMMITTED=true
# A successful launch alone is not business/data acceptance. Retain rollback files until that review.
print "已安装并启动搞邮件 V$APP_VERSION；保留上一版程序和安装包，等待业务及数据验收。"
if [[ -e "$OLD_APP" ]]; then print "ROLLBACK_APP=$OLD_APP"; fi
print '验收通过后再精确清理上述旧程序及本项目旧安装包，保留安全数据备份。'
