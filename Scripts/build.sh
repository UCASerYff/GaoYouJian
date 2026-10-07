#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_VERSION="$(tr -d '\n' < "$PROJECT_DIR/VERSION")"
if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]{2}$' ]]; then print -u2 'VERSION 必须为 1.00 格式'; exit 1; fi
BUILD_NUMBER="${APP_VERSION//./}"
APP_ONLY=false
if [[ $# -gt 0 ]]; then
  [[ $# == 2 && "$1" == '--app-only' ]] || { print -u2 '用法：build.sh [--app-only /绝对路径/搞邮件.app]'; exit 1; }
  [[ "$2" == /* && "$2" == *.app && ! -e "$2" && ! -L "$2" ]] || { print -u2 '测试应用目标必须是不存在的绝对 .app 路径'; exit 1; }
  APP_ONLY=true
fi
STAGING="$(mktemp -d /private/tmp/gaoyoujian-build.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/搞邮件.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$STAGING/cache"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
EXTRA_FLAGS=()
if $APP_ONLY; then EXTRA_FLAGS=(-D DEBUG_TESTING); fi
NATIVE_OBJECTS=()
NATIVE_FLAGS=()
if [[ -f "$PROJECT_DIR/Sources/MailNative.c" && -f "$PROJECT_DIR/Sources/MailNative.h" ]]; then
  clang -O2 -arch arm64 -mmacosx-version-min=14.0 -isysroot "$SDK" \
    -c "$PROJECT_DIR/Sources/MailNative.c" -o "$STAGING/MailNative.o"
  NATIVE_OBJECTS=("$STAGING/MailNative.o")
  NATIVE_FLAGS=(-import-objc-header "$PROJECT_DIR/Sources/MailNative.h" -lcurl)
fi
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -sdk "$SDK" -module-cache-path "$STAGING/cache" \
  "${EXTRA_FLAGS[@]}" "${NATIVE_FLAGS[@]}" "$PROJECT_DIR"/Sources/*.swift "${NATIVE_OBJECTS[@]}" \
  -framework AppKit -framework SwiftUI -framework WebKit -framework Security \
  -framework Network -framework AuthenticationServices -framework UserNotifications \
  -lsqlite3 -o "$APP/Contents/MacOS/GaoYouJian"
[[ -f "$PROJECT_DIR/Assets/AppIcon.png" ]] || { print -u2 '缺少正式图标 Assets/AppIcon.png'; exit 1; }
if [[ ! -f "$PROJECT_DIR/Assets/AppIcon.icns" || "$PROJECT_DIR/Assets/AppIcon.png" -nt "$PROJECT_DIR/Assets/AppIcon.icns" ]]; then
  swift -module-cache-path "$STAGING/cache" "$PROJECT_DIR/Scripts/MakeIcon.swift" "$PROJECT_DIR/Assets/AppIcon.png" "$PROJECT_DIR/Assets/AppIcon.icns"
fi
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Assets/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
[[ -f "$PROJECT_DIR/Docs/OAuthSetup.txt" ]] || { print -u2 '缺少 Docs/OAuthSetup.txt 授权配置说明'; exit 1; }
mkdir -p "$APP/Contents/Resources/Docs"
cp "$PROJECT_DIR/Docs/OAuthSetup.txt" "$APP/Contents/Resources/Docs/OAuthSetup.txt"
if [[ -f "$PROJECT_DIR/使用说明.txt" ]]; then cp "$PROJECT_DIR/使用说明.txt" "$APP/Contents/Resources/使用说明.txt"; fi
if [[ -f "$PROJECT_DIR/THIRD-PARTY-NOTICES.txt" ]]; then cp "$PROJECT_DIR/THIRD-PARTY-NOTICES.txt" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"; fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gaoseries.GaoYouJian</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleName</key><string>搞邮件</string>
<key>CFBundleDisplayName</key><string>搞邮件</string>
<key>CFBundleExecutable</key><string>GaoYouJian</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>搞系列 · 搞邮件</string>
<key>NSSupportsAutomaticTermination</key><false/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
xattr -cr "$APP"
codesign --force --sign - --identifier com.gaoseries.GaoYouJian "$APP"
codesign --verify --strict "$APP"
if $APP_ONLY; then
  ditto "$APP" "$2"
  print "APP=$2"
  exit 0
fi
[[ ! -L "$PROJECT_DIR/Release" ]] || { print -u2 'Release 不能是符号链接'; exit 1; }
mkdir -p "$STAGING/disk" "$PROJECT_DIR/Release"
ditto "$APP" "$STAGING/disk/搞邮件.app"
ln -s /Applications "$STAGING/disk/Applications"
if [[ -f "$PROJECT_DIR/使用说明.txt" ]]; then cp "$PROJECT_DIR/使用说明.txt" "$STAGING/disk/使用说明.txt"; fi
hdiutil create -quiet -volname "搞邮件 V$APP_VERSION" -srcfolder "$STAGING/disk" -format UDZO "$STAGING/GaoYouJian-$APP_VERSION.dmg"
hdiutil verify -quiet "$STAGING/GaoYouJian-$APP_VERSION.dmg"
mv "$STAGING/GaoYouJian-$APP_VERSION.dmg" "$PROJECT_DIR/Release/GaoYouJian-$APP_VERSION.dmg"
(cd "$PROJECT_DIR/Release" && shasum -a 256 "GaoYouJian-$APP_VERSION.dmg" > "GaoYouJian-$APP_VERSION.dmg.sha256")
print "构建完成：$PROJECT_DIR/Release/GaoYouJian-$APP_VERSION.dmg"
print '临时构建已自动清理。旧安装包将在新版安装验证成功后清理。'
