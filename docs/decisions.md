# 裁定記録（なぜこの構成か）

検証を繰り返す上で「毎回蒸し返さない」ための、確定済みの判断と根拠。
新しい検証で前提が変わったら、ここに追記/更新する。

各項目は「背景 / 決定 / 根拠」。

---

## D1. Node 20+ をどう用意するか → `brew install node@22`(keg-only)

- **背景**: 既定 `node` は v18 でSEA非対応。既存の node@18 を壊したくない。
- **決定**: `node@22` を keg-only で導入し、既定の `node` は変えない。
- **根拠**: keg-onlyは自動でPATHリンクされず、`node`(18)の実体を変えない。
  nvmはシェルrc/PATHを書き換えて影響が広く、「競合させない」方針に反する。

## D2. 注入の土台にするnodeの入手元 → nodejs.org 公式バイナリ

- **背景**: Homebrew版nodeはstripされ `NODE_SEA_FUSE` センチネルを含まず、postject注入が失敗する。
- **決定**: 公式プレビルドバイナリ（fuseあり）を `vendor/` に同梱して土台に使う。
- **根拠**: 公式版はセンチネルを含む（`strings|grep -c` = 1 で実測）。システムには入れないため
  既存nodeに影響せずPATHも変えない。**入手時はSHA-256を公式`SHASUMS256.txt`と照合**する。
  - 実測: `node-v22.23.2-darwin-arm64` / `61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6`

## D3. npmパッケージの取り込み方 → esbuildで単一JSにバンドル

- **背景**: SEAは基本的に単一JSしか埋め込めず、`node_modules` をそのまま持てない。
- **決定**: `esbuild --bundle --platform=node --target=node22` でアプリ+依存を1ファイル化。
- **根拠**: 単一JS化が必須。esbuildは高速・最小設定でCJS依存を素直に束ねられる。

## D4. 検証用パッケージ → `lodash` / `dayjs`

- **決定**: この2つを封入対象にする。
- **根拠**: 広く使われCJSで素直にバンドルでき、出力が目視で確認しやすい
  （封入したパッケージが実際に動いた証拠を出しやすい）。

## D5. sea-config の方針 → 最適化は無効で確実性優先

- **決定**: `useSnapshot:false` / `useCodeCache:false` / `disableExperimentalSEAWarning:true`。
- **根拠**: スナップショット/コードキャッシュはesbuildバンドルと相性問題が出うる。
  最小構成では無効化して確実に通す。

## D6. vendor/ と dist/ はソース管理外

- **決定**: `vendor/`(DL物) と `dist/`(生成物) はバージョン管理に含めない。
- **根拠**: どちらも再取得・再生成でき、サイズも大きい（node本体は100MB超）。
  再現手段（[runbook.md](runbook.md)）さえ残せば十分。

## D7. Win/Linux へのクロスビルド → blob共通・土台nodeだけ差し替え

- **背景**: SEAはOS/アーキごとに別バイナリ。Mac上でWin/Linux向けも作りたい。
- **決定**: blob（埋め込むアプリ）は**プラットフォーム非依存**なので1回生成し、
  土台nodeを各OS/アーキの**公式(fuse入り)**に差し替えて postject 注入する（`build-cross.sh`）。
- **根拠**: postjectはバイナリにバイトを埋め込むだけでホストOSに依存しない。土台さえ差し替えれば
  Macから linux-x64 / win-x64 のSEAを生成できる（ただし**実行・テストは各OSが必要**）。
- **補足**: macOSのみ `--macho-segment-name` と `codesign` が要る。Linux/Windowsは不要。

## D8. 「サービス化」はOSのサービス管理に委ねる（バイナリは常駐プロセスに徹する）

- **背景**: 「スリープ・再起動しても動く」を実現したい。
- **決定**: バイナリ側は**行儀の良い常駐プロセス**（無限ループ＋SIGTERMで綺麗に停止＋ログ追記）に徹し、
  再起動をまたぐ生存は **Linux=systemd（`enable`）/ Windows=WinSW等のラッパー（Automatic起動）** に任せる。
- **根拠**: 再起動後の自動起動やスリープ復帰の面倒はOSのサービス管理の責務。SEAバイナリ自体は
  「単体で起動でき、シグナルに従う長寿命プロセス」であればよい。
- **Windows特記**: 生exeはSCM非対応のため `sc create` 直指定では正しく起動しない → ラッパー必須（→[pitfalls P5](pitfalls.md)）。
