# 検証の回し方（Runbook）

1回の検証で叩く手順。詰まったら [pitfalls.md](pitfalls.md)、判断の根拠は [decisions.md](decisions.md)。

## 前提（初回のみ）

```bash
# 公式node(fuse入り)を vendor/ に取得し、SHA-256を照合してから展開
VER=v22.23.2; T=node-${VER}-darwin-arm64.tar.gz
mkdir -p vendor && cd vendor && curl -fsSL -O https://nodejs.org/dist/${VER}/${T}
E=$(curl -fsSL https://nodejs.org/dist/${VER}/SHASUMS256.txt | grep "  ${T}\$" | awk '{print $1}')
[ "$E" = "$(shasum -a 256 ${T}|awk '{print $1}')" ] && tar -xzf ${T} && echo OK || echo MISMATCH
cd ..

# 依存インストール（node@22系のnpmで）
PATH="$PWD/vendor/node-${VER}-darwin-arm64/bin:$PATH" npm install
```

## ビルド〜実行（毎回）

```bash
./build.sh          # bundle(esbuild)→blob生成→node複製+chmod→注入(postject)→ad-hoc署名
./dist/sea-poc      # 生成された単体バイナリを実行
```

`build.sh` は `vendor/` の公式nodeを**フルパス参照**する（既定の `node` は使わない）。

## 成功の確認ポイント

| 見るところ | 期待値 |
|---|---|
| `file dist/sea-poc` | `Mach-O 64-bit executable arm64` |
| 実行時 `running inside SEA` | `true` |
| lodash/dayjs の出力 | 正しい値が出る（封入パッケージが動いた証拠） |
| プロジェクト外へコピーして実行 | 同一出力（node非依存の証拠） |

## 成果物

- `dist/sea-poc`（約107MB）＝ 配布・実行する単体バイナリ。**これ1個で動く**。
- `dist/bundle.js` / `dist/sea-prep.blob` は中間物（再生成可）。
