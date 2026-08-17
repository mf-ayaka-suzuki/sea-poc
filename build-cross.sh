#!/usr/bin/env bash
#
# SEA サービスを Linux(x64) / Windows(x64) 向けにクロスビルドする。
#
# 仕組み: blob(埋め込むアプリ)はプラットフォーム非依存。土台となる node バイナリだけを
#         各OS/アーキの「公式(fuse入り)」に差し替えて postject で注入すればクロスビルドできる。
#         ホスト(mac)の node/npx でツール(esbuild/postject)を実行する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

NODE_VER="${NODE_VER:-v22.23.2}"
HOST_NODE="vendor/node-${NODE_VER}-darwin-arm64/bin/node"
HOST_NPX="vendor/node-${NODE_VER}-darwin-arm64/bin/npx"
FUSE="NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"

if [ ! -x "$HOST_NODE" ]; then
  echo "ERROR: ホストの公式node が無い: $HOST_NODE (先に build.sh の前提セットアップを実施)" >&2
  exit 1
fi

mkdir -p dist vendor

echo ">> [1/4] bundle service (esbuild)"
"$HOST_NPX" --yes esbuild src/service.js \
  --bundle --platform=node --target=node22 \
  --outfile=dist/service.bundle.js

echo ">> [2/4] generate blob (platform-agnostic)"
"$HOST_NODE" --experimental-sea-config sea-config.service.json

# 公式nodeを取得(未取得なら)。SHA-256照合つき。
fetch_node() {
  local dir="$1" tar="$2"
  local base="https://nodejs.org/dist/${NODE_VER}"
  if [ -d "vendor/${dir}" ]; then
    return 0
  fi
  echo "   - downloading ${tar}"
  (cd vendor && curl -fsSL -O "${base}/${tar}")
  local exp act
  exp=$(curl -fsSL "${base}/SHASUMS256.txt" | grep "  ${tar}\$" | awk '{print $1}')
  act=$(shasum -a 256 "vendor/${tar}" | awk '{print $1}')
  if [ "$exp" != "$act" ]; then
    echo "   ! CHECKSUM MISMATCH for ${tar}" >&2
    exit 1
  fi
  echo "   - checksum OK, extracting"
  case "$tar" in
    *.tar.xz) tar -xJf "vendor/${tar}" -C vendor ;;
    *.tar.gz) tar -xzf "vendor/${tar}" -C vendor ;;
    *.zip)    unzip -q -o "vendor/${tar}" -d vendor ;;
  esac
}

# 土台バイナリに blob を注入して単体実行ファイルを作る。
inject() {
  local base="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  cp "$base" "$out"
  chmod u+w "$out"
  "$HOST_NPX" --yes postject "$out" NODE_SEA_BLOB dist/service.blob \
    --sentinel-fuse "$FUSE"
  chmod +x "$out" 2>/dev/null || true
}

echo ">> [3/4] build linux-x64"
fetch_node "node-${NODE_VER}-linux-x64" "node-${NODE_VER}-linux-x64.tar.xz"
inject "vendor/node-${NODE_VER}-linux-x64/bin/node" "dist/linux-x64/sea-svc"

echo ">> [4/4] build win-x64"
fetch_node "node-${NODE_VER}-win-x64" "node-${NODE_VER}-win-x64.zip"
inject "vendor/node-${NODE_VER}-win-x64/node.exe" "dist/win-x64/sea-svc.exe"

echo ""
echo "DONE"
file dist/linux-x64/sea-svc dist/win-x64/sea-svc.exe 2>/dev/null || true
ls -lh dist/linux-x64/sea-svc dist/win-x64/sea-svc.exe
