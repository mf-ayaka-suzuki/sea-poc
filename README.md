# sea-poc — Node.js SEA 最小PoC

Node.js の **SEA (Single Executable Applications)** で、npmパッケージを封入した単一実行バイナリを作る最小構成のPoCです。
アプリ独自ロジックはほぼ無く、「npmパッケージ（`lodash` / `dayjs`）がバイナリに封入されて動く」ことの確認が目的です。

## 成果物

```
dist/sea-poc   # 単一実行バイナリ (Mach-O arm64, 約107MB, node不要で動く)
```

実行例:

```
$ ./dist/sea-poc
=== Node.js SEA PoC ===
running inside SEA : true
node version       : v22.23.2
lodash _.chunk     : [["a","b"],["c","d"],["e"]]
dayjs now          : 2026-08-13 10:09:14
lodash _.capitalize: Hello from bundled npm package
```

## 前提と重要な注意

- **SEA には Node 20 以降が必要**（`--experimental-sea-config`）。このマシンの `node`(v18) では作れません。
- **Homebrew版の node は使えない**: strip されており、SEA注入に必須の `NODE_SEA_FUSE` センチネルを含まないため
  postject が `Could not find the sentinel ...` で失敗します。
  → **nodejs.org 公式のプレビルドバイナリ**を `vendor/` に同梱して使います（システムには入れず、PATHも変更しない）。
- 既存の `node@18` / `node@22`(Homebrew) とは競合しません。ビルドは同梱の公式nodeをフルパスで参照します。

## セットアップ（vendor/ に公式nodeを取得）

```bash
VER=v22.23.2
TARBALL=node-${VER}-darwin-arm64.tar.gz
mkdir -p vendor && cd vendor
curl -fsSL -O https://nodejs.org/dist/${VER}/${TARBALL}
# チェックサム検証（任意だが推奨）
EXPECTED=$(curl -fsSL https://nodejs.org/dist/${VER}/SHASUMS256.txt | grep "  ${TARBALL}\$" | awk '{print $1}')
[ "$EXPECTED" = "$(shasum -a 256 ${TARBALL} | awk '{print $1}')" ] && echo OK || echo MISMATCH
tar -xzf ${TARBALL}
cd ..
```

## 依存インストール & ビルド

```bash
# 依存は node@22 系のnpmで入れる（node18のnpmでも可）
PATH="$PWD/vendor/node-v22.23.2-darwin-arm64/bin:$PATH" npm install

# ビルド（bundle → blob生成 → nodeコピー → postject注入 → ad-hoc署名）
./build.sh
```

## ビルドの流れ（build.sh）

1. **esbuild** で `src/index.js` と npm依存を単一JS `dist/bundle.js` にバンドル
2. `node --experimental-sea-config sea-config.json` で SEA準備blob `dist/sea-prep.blob` を生成
3. 公式 node バイナリを `dist/sea-poc` にコピー（読み取り専用なので `chmod u+w` を付与）
4. **postject** で blob を `NODE_SEA_BLOB` セグメントに注入（macOSは `--macho-segment-name NODE_SEA`）
5. macOS の **ad-hoc 署名** (`codesign --sign -`) を付与

## ハマりどころ（このPoCで実際に遭遇したもの）

| 症状 | 原因 | 対処 |
|---|---|---|
| `node: bad option: --experimental-sea-config` | node18 はSEA未対応 | Node 20+ を使う |
| postject `Can't read and write to target executable` | コピーしたnodeが 0555（書込不可） | `chmod u+w` を付与 |
| postject `Could not find the sentinel NODE_SEA_FUSE...` | Homebrew版nodeはstripされfuse無し | nodejs.org 公式バイナリを使う |

## 構成

```
sea-poc/
├── src/index.js        # 最小のエントリ（lodash/dayjsを使うだけ）
├── sea-config.json     # SEA設定
├── build.sh            # ビルドスクリプト（macOS/arm64）
├── package.json
├── vendor/             # 公式node同梱（.gitignore対象）
└── dist/               # 生成物（.gitignore対象）
```

> 注: 別プラットフォーム（Linux/Windows、Intel Mac）向けに作る場合は、対応する公式nodeバイナリを使い、
> postject の macOS 専用オプション（`--macho-segment-name`）や `codesign` の要否を調整してください。
