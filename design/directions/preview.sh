#!/bin/bash
# 编译样稿；render 出图到 out/，show 铺到 Wokyis 上（左键下一张、右键上一张、Esc 退出）。
set -e
cd "$(dirname "$0")"
mkdir -p .build/mc
export CLANG_MODULE_CACHE_PATH="$PWD/.build/mc" SWIFT_MODULE_CACHE_PATH="$PWD/.build/mc"
swiftc -O -parse-as-library -framework SwiftUI -framework AppKit Directions.swift -o .build/Directions
case "${1:-show}" in
  render) .build/Directions render out ;;
  show) .build/Directions show ;;
esac
