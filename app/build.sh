#!/bin/bash
set -e
cd "$(dirname "$0")"
APP="Reverie.app"
BIN="Reverie"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Reverie</string>
  <key>CFBundleDisplayName</key><string>Reverie</string>
  <key>CFBundleIdentifier</key><string>com.local.reverie</string>
  <key>CFBundleExecutable</key><string>$BIN</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Reverie</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Reverie 需要读取和切换 Apple Music 当前歌曲的喜欢状态。</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "Compiling..."
mkdir -p .build/module-cache .build/swift-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.build/swift-module-cache"
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Sources -name '*.swift' | sort)
swiftc -O -parse-as-library \
  -framework SwiftUI -framework AppKit \
  "${SOURCES[@]}" \
  -o "$APP/Contents/MacOS/$BIN"

# Bundle the MediaRemote adapter (framework + perl script) inside the app so it's self-contained.
RES="$APP/Contents/Resources/mediaremote-adapter"
mkdir -p "$RES/bin" "$RES/build"
cp Resources/Reverie.icns "$APP/Contents/Resources/"
cp -R Resources/Fonts "$APP/Contents/Resources/"
if [ ! -f ../mediaremote-adapter/bin/mediaremote-adapter.pl ] || [ ! -d ../mediaremote-adapter/build/MediaRemoteAdapter.framework ]; then
  echo "缺少 mediaremote-adapter，先运行 scripts/setup.sh（会拉取并编译）" >&2; rm -rf "$APP"; exit 1
fi
cp ../mediaremote-adapter/bin/mediaremote-adapter.pl "$RES/bin/"
cp -R ../mediaremote-adapter/build/MediaRemoteAdapter.framework "$RES/build/"

# 签名身份：默认「Reverie Local」（scripts/make-cert.sh 可建），可用 REVERIE_SIGN_IDENTITY 改。
# 身份要稳定：换了签名，「辅助功能」等授权就会失效。找不到证书就临时签名（只适合试用，每次重编都要重新授权）。
xattr -cr "$APP" 2>/dev/null || true
IDENT="${REVERIE_SIGN_IDENTITY:-Reverie Local}"
if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENT"; then
  if [ "${REVERIE_ALLOW_ADHOC:-1}" = "1" ]; then
    echo "警告：找不到证书 $IDENT，改用临时签名；正式使用请先运行 scripts/make-cert.sh" >&2
    codesign --force --deep --sign - "$APP"
    echo "signed ad-hoc"
    echo "Built $APP (self-contained)"
    exit 0
  fi
  echo "签名失败：找不到证书 $IDENT" >&2; rm -rf "$APP"; exit 1
fi
codesign --force --deep --sign "$IDENT" "$APP" 2>/dev/null & SIGN_PID=$!
( sleep 20; kill "$SIGN_PID" 2>/dev/null ) 2>/dev/null & WATCH_PID=$!; disown "$WATCH_PID"
if ! wait "$SIGN_PID"; then
  kill "$WATCH_PID" 2>/dev/null; echo "签名失败：codesign 出错或超时" >&2; rm -rf "$APP"; exit 1
fi
kill "$WATCH_PID" 2>/dev/null || true
if ! codesign --verify --deep --strict "$APP" 2>/dev/null || ! codesign -dvv "$APP" 2>&1 | grep -q "Authority=$IDENT"; then
  echo "签名失败：校验不通过或身份不是 $IDENT" >&2; rm -rf "$APP"; exit 1
fi
echo "signed with $IDENT"
echo "Built $APP (self-contained)"
