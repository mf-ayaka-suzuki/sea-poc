# sea-poc — Node.js SEA 技術検証

Node.js の **SEA (Single Executable Applications)** の実用性を検証したPoC。
「npmパッケージを封入した単一実行バイナリ（node不要で動く）」を作れることから始め、
それを**常駐サービス**に発展させ、**mac / Linux / Windows で「再起動・スリープをまたいで動くサービス」として成立するか**を実機で確認した。

検証の詳細・経緯・裁定はすべて [docs/](docs/index.md) にある（この README はその要約）。

## 結果サマリ

| 確認項目 | macOS | Linux(x64) | Windows(x64) |
|---|---|---|---|
| SEA単一バイナリ生成（node不要で起動） | ✅ arm64 | ✅ | ✅ |
| npmパッケージ封入が動作（lodash/dayjs） | ✅ | ✅ | ✅ |
| 常駐サービスとして動作 | ✅ (Docker) | ✅ (Docker) | ✅ (WinSW実機) |
| OS再起動をまたぐ自動起動 | ✅ (Mac実機/Docker) | ⏳ systemd手順のみ | ✅ 実機 |
| 異常終了からの自動復帰 | ✅ (`--restart always`) | ✅ (同左) | ✅ (WinSW `onfailure`) |
| グレースフル停止（SIGTERM/SIGINT） | ✅ | ✅ | ✅ (Ctrl+C→SIGINT) |
| スリープ復帰後の生存 | ⏳ 未 | ⏳ 未 | ✅ (S0 Modern Standby) |

- **結論**: SEA単一バイナリは、3プラットフォームとも**OSのサービス管理下で「再起動をまたいで自動復帰する常駐サービス」として実用に足る**。
- 「再起動しても動く」の主体は**バイナリではなくOSのサービス管理**（Linux=systemd / Windows=SCM+WinSW / macOS=Docker `--restart`）。バイナリ側は行儀の良い常駐プロセスに徹する設計。
- 実機検証の全ログ・タイムラインは各 [検証記録](docs/index.md#検証ごとの記録増えていく) を参照。

## 中身は2種類のバイナリ

| 用途 | エントリ | ビルド | 対象 |
|---|---|---|---|
| 最小PoC（封入確認） | `src/index.js` | `build.sh` | macOS/arm64 |
| 常駐サービス（本命） | `src/service.js` | `build-cross.sh`（Mac→linux/win x64）/ `build-win.ps1`（Windows単体） | Linux・Windows x64 |

`src/service.js` は一定間隔でタイムスタンプ付きハートビートをログ追記し、SIGTERM/SIGINTで綺麗に停止する常駐プロセス。ログの連続性で「再起動をまたいで動いた」ことを証跡化している。

## 主要な学び（詳細は [docs/pitfalls.md](docs/pitfalls.md)）

- **SEAは Node 20+ 必須**。既定の node18 では作れない。
- **Homebrew版nodeは使えない**（stripされ `NODE_SEA_FUSE` センチネル無し）→ **nodejs.org公式バイナリ**を `vendor/` に同梱（SHA-256照合）。システムには入れずPATHも汚さない。
- **SEAはOS・CPUごとに別バイナリ**。ただし blob はプラットフォーム非依存なので、土台nodeを差し替えれば Mac から Linux/Windows 向けもクロスビルドできる。
- **生exeは直接サービス化できない**（Windows: `sc create` は登録だけ通って起動で 1053）→ WinSW/NSSM等の**ラッパー必須**。
- **スリープ中は `setInterval` が止まる**（復帰後もキャッチアップしない）→ 時間依存の判断は実時計で。

## ドキュメント地図

- **入口**: [docs/index.md](docs/index.md)
- 変わらない知識: [decisions.md](docs/decisions.md)（裁定）/ [pitfalls.md](docs/pitfalls.md)（ハマりどころ P1–P8）
- 回し方: [runbook.md](docs/runbook.md)（Mac/Docker）/ [runbook-windows.md](docs/runbook-windows.md)（Windows単体）
- サービス化: [deploy/linux/](deploy/linux/README.md)（systemd）/ [deploy/windows/](deploy/windows/README.md)（WinSW）
- 検証記録: [docs/verifications/](docs/verifications/)（1検証=1ファイルで増えていく）

## 構成

```
sea-poc/
├── src/
│   ├── index.js            # 最小PoC（lodash/dayjs封入確認）
│   └── service.js          # 常駐サービス（ハートビート）
├── build.sh                # macビルド（最小PoC）
├── build-cross.sh          # Mac→Linux/Windows(x64) クロスビルド（サービス）
├── build-win.ps1           # Windows単体ネイティブビルド（サービス）
├── sea-config.json / sea-config.service.json
├── deploy/                 # サービス登録定義（linux=systemd / windows=WinSW）
├── docs/                   # 検証ドキュメント一式（入口: docs/index.md）
├── vendor/                 # 公式node同梱（.gitignore対象）
└── dist/                   # 生成物（.gitignore対象）
```

> `vendor/`（DL物）と `dist/`（生成物）はバージョン管理に含めない。再取得・再生成できるため（[decisions D6](docs/decisions.md)）。
