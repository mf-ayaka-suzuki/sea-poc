#!/usr/bin/env bash
#
# Node.js SEA (Single Executable Application) build script  — macOS 版
#
# 既存の node@18 と競合させないため、Node 22 はフルパスで参照する（keg-only, PATH非依存）。
set -euo pipefail

# --- 同梱した公式 Node 22 (darwin-arm64) を使う ----------------------------
# 重要: Homebrew版の node は strip されており SEA の fuse センチネルを含まないため
#       SEA 注入には使えない。nodejs.org 公式のバイナリ（vendor/ に同梱）を使う。
NODE_VER="${NODE_VER:-v22.23.2}"
VENDOR_NODE_DIR="$(cd "$(dirname "$0")" && pwd)/vendor/node-${NODE_VER}-darwin-arm64"
NODE_BIN="${NODE_BIN:-$VENDOR_NODE_DIR/bin/node}"
NPX_BIN="${NPX_BIN:-$VENDOR_NODE_DIR/bin/npx}"

if [ ! -x "$NODE_BIN" ]; then
  echo "ERROR: 同梱の公式node が見つかりません: $NODE_BIN" >&2
  echo "  README の手順で vendor/ に公式バイナリを取得してください。" >&2
  exit 1
fi

echo ">> using node : $NODE_BIN ($("$NODE_BIN" -v))"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="sea-poc"
OUT="dist"
BIN="$OUT/$APP_NAME"

rm -rf "$OUT"
mkdir -p "$OUT"

# --- 1) npmパッケージを含めて単一JSにバンドル -------------------------------
echo ">> [1/5] bundling with esbuild"
"$NPX_BIN" --yes esbuild src/index.js \
  --bundle --platform=node --target=node22 \
  --outfile="$OUT/bundle.js"

# --- 2) SEA準備blobを生成 ---------------------------------------------------
echo ">> [2/5] generating SEA blob"
"$NODE_BIN" --experimental-sea-config sea-config.json

# --- 3) node バイナリをコピー ----------------------------------------------
echo ">> [3/5] copying node binary -> $BIN"
cp "$NODE_BIN" "$BIN"
# Homebrewのnodeは読み取り専用(0555)。postjectが書き込めるよう書込権限を付与する。
chmod u+w "$BIN"

# macOS: 既存署名を外してから注入する
codesign --remove-signature "$BIN" 2>/dev/null || true

# --- 4) blob を postject で注入 --------------------------------------------
echo ">> [4/5] injecting blob with postject"
"$NPX_BIN" --yes postject "$BIN" NODE_SEA_BLOB "$OUT/sea-prep.blob" \
  --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 \
  --macho-segment-name NODE_SEA

# --- 5) macOS: アドホック再署名 --------------------------------------------
echo ">> [5/5] ad-hoc codesign"
codesign --sign - "$BIN"

echo ""
echo "DONE -> $BIN"
ls -lh "$BIN"
