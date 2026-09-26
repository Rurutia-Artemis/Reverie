#!/bin/bash
# 编译并运行纯逻辑单元测试（只编不依赖 SwiftUI 的逻辑文件）。
set -e
cd "$(dirname "$0")"
mkdir -p .build/module-cache .build/swift-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$PWD/.build/swift-module-cache"
LOGIC=()
while IFS= read -r f; do LOGIC+=("$f"); done < <(grep -rl "^// reverie:logic" Sources | sort)
TESTS=()
while IFS= read -r f; do TESTS+=("$f"); done < <(find Tests -name '*.swift' | sort)
swiftc "${LOGIC[@]}" "${TESTS[@]}" -o .build/reverie-tests
.build/reverie-tests
