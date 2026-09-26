#!/bin/bash
# 第一次拿到源码时跑一次：拉取并编译 mediaremote-adapter（读系统「正在播放」用的适配器）。
# 需要 Xcode Command Line Tools 和 cmake（brew install cmake）。
set -e
cd "$(dirname "$0")/.."
UPSTREAM=https://github.com/ungive/mediaremote-adapter.git
COMMIT=3ac3d4b
if ! command -v cmake >/dev/null; then echo "缺 cmake：brew install cmake" >&2; exit 1; fi
if [ ! -d mediaremote-adapter/.git ]; then
  git clone "$UPSTREAM" mediaremote-adapter
fi
(cd mediaremote-adapter && git fetch -q && git checkout -q "$COMMIT")
mkdir -p mediaremote-adapter/build
(cd mediaremote-adapter/build && cmake .. >/dev/null && cmake --build . >/dev/null)
[ -d mediaremote-adapter/build/MediaRemoteAdapter.framework ] && echo "mediaremote-adapter 就绪（$COMMIT）" || { echo "编译失败" >&2; exit 1; }
if ! security find-identity -p codesigning 2>/dev/null | grep -q "${REVERIE_SIGN_IDENTITY:-Reverie Local}"; then
  echo "提示：还没有签名证书，运行 scripts/make-cert.sh 建一个（否则 build.sh 会用临时签名，每次重编都要重新给辅助功能授权）"
fi
