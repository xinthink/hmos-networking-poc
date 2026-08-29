#!/usr/bin/env bash
# 构建 cangjie_stdx (git submodule) for OHOS aarch64，并复制运行时 .so 到 app libs。
# 其他机器 checkout 仓库后运行本脚本即可复现（依赖见下方环境变量）。
#
# 用法：./scripts/build-stdx.sh
# 环境变量（可选覆盖）：
#   CANGJIE_SDK_HOME     cangjie SDK 根（默认 ~/.cangjie-sdk/6.1/cangjie）
#   DEVECO_OH_NATIVE_HOME DevEco OpenHarmony native SDK 根
#   OPENSSL_INCLUDE      OpenSSL 头文件目录（默认自动探测 brew /usr/include）
#
# 产物：vendor/cangjie_stdx/target/linux_ohos_aarch64_cjnative/{dynamic,static}/stdx
#       entry/libs/arm64-v8a/*.so（打包进 hap 的运行时库）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STDX_DIR="$PROJECT_ROOT/vendor/cangjie_stdx"

CANGJIE_SDK_HOME="${CANGJIE_SDK_HOME:-$HOME/.cangjie-sdk/6.1/cangjie}"
DEVECO_OH_NATIVE_HOME="${DEVECO_OH_NATIVE_HOME:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"

# --- OpenSSL 头文件（stdx 编译需要 openssl/ssl.h；运行时走 dlopen 系统库）---
if [ -z "${OPENSSL_INCLUDE:-}" ]; then
  for p in /opt/homebrew/opt/openssl@3/include /usr/local/opt/openssl@3/include /usr/include; do
    if [ -f "$p/openssl/ssl.h" ]; then OPENSSL_INCLUDE="$p"; break; fi
  done
fi
if [ -z "${OPENSSL_INCLUDE:-}" ] || [ ! -f "$OPENSSL_INCLUDE/openssl/ssl.h" ]; then
  echo "ERROR: OpenSSL headers not found. Set OPENSSL_INCLUDE=<dir containing openssl/ssl.h>" >&2
  exit 1
fi
OPENSSL_LIB="$(dirname "$OPENSSL_INCLUDE")/lib"
[ -d "$OPENSSL_LIB" ] || OPENSSL_LIB="$(dirname "$OPENSSL_INCLUDE")"

[ -d "$CANGJIE_SDK_HOME/build-tools" ] || { echo "ERROR: Cangjie SDK not found at $CANGJIE_SDK_HOME"; exit 1; }
[ -d "$DEVECO_OH_NATIVE_HOME/llvm/bin" ] || { echo "ERROR: DevEco OH native SDK not found at $DEVECO_OH_NATIVE_HOME"; exit 1; }
[ -d "$STDX_DIR" ] || { echo "ERROR: stdx submodule missing. Run: git submodule update --init --recursive"; exit 1; }

# --- 构造 CANGJIE_HOME（cjc 1.1.3 期望 <root>/modules|runtime|lib|third_party 布局，
#     而 6.1 SDK 的库分散在 build-tools/ 下）---
CJOHOS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cjohos.XXXXXX")"
trap 'rm -rf "$CJOHOS_ROOT"' EXIT
mkdir -p "$CJOHOS_ROOT/modules"
ln -s "$CANGJIE_SDK_HOME/build-tools/modules/linux_ohos_aarch64_cjnative" "$CJOHOS_ROOT/modules/linux_ohos_aarch64_cjnative"
ln -s "$CANGJIE_SDK_HOME/build-tools/runtime" "$CJOHOS_ROOT/runtime"
ln -s "$CANGJIE_SDK_HOME/build-tools/lib" "$CJOHOS_ROOT/lib"
ln -s "$CANGJIE_SDK_HOME/build-tools/third_party" "$CJOHOS_ROOT/third_party"

export PATH="$CANGJIE_SDK_HOME/build-tools/bin:$PATH"
export CANGJIE_HOME="$CJOHOS_ROOT"

cd "$STDX_DIR"
echo "==> stdx @ $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"

python3 build.py clean
python3 build.py build -t release --target ohos-aarch64 \
  --target-toolchain "$DEVECO_OH_NATIVE_HOME/llvm/bin" \
  --target-sysroot "$DEVECO_OH_NATIVE_HOME/sysroot" \
  --include "$OPENSSL_INCLUDE" \
  --target-lib "$OPENSSL_LIB"
python3 build.py install

# cjpm bin-dependencies 要求 path-option 目录内含 package.json
cp target/linux_ohos_aarch64_cjnative/package.json target/linux_ohos_aarch64_cjnative/dynamic/stdx/package.json

# 复制运行时 .so 到 app libs（打包进 hap）
mkdir -p "$PROJECT_ROOT/entry/libs/arm64-v8a"
cp target/linux_ohos_aarch64_cjnative/dynamic/stdx/*.so "$PROJECT_ROOT/entry/libs/arm64-v8a/"

echo "==> stdx build OK; $(ls "$PROJECT_ROOT/entry/libs/arm64-v8a/" | wc -l) .so copied to entry/libs/arm64-v8a/"
