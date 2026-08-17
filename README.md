# sea-poc — Node.js SEA 技術検証

Node.js の **SEA (Single Executable Applications)** の実用性を検証したPoC。
「npmパッケージを封入した単一実行バイナリ（node不要で動く）」を作れることから始め、
それを**常駐サービス**に発展させ、**mac / Linux / Windows で「再起動・スリープをまたいで動くサービス」として成立するか**を実機で確認した。

検証の詳細・経緯・裁定はすべて [docs/](docs/index.md) にある（この README はその要約）。

## 結果サマリ

各セルは**実際に観測した証拠**つき。「実機」=物理ハードで実測 / 「VM」=Mac上のDocker Desktop Linux VMで実測（仮想化された実Linuxカーネル）/ 「手順のみ」=定義・手順のみ（未実測）。

| 確認項目 | macOS | Linux(x64) | Windows(x64) |
|---|---|---|---|
| SEA単一バイナリ生成（node不要で起動） | ✅ 実機 arm64 | ✅ VM ELF | ✅ 実機 PE(exe) |
| npmパッケージ封入が動作（lodash/dayjs） | ✅ 実機 | ✅ VM | ✅ 実機 |
| 常駐サービスとして動作 | ✅ 実機ネイティブ/VM | ✅ VM | ✅ 実機 WinSW |
| OS再起動をまたぐ自動起動 | ✅ 実機 Mac再起動→Docker復帰 | ✅ VM systemd登録→boot自動起動を実測（バーメタルrebootは未） | ✅ 実機 再起動後25秒で自動起動 |
| 異常終了からの自動復帰 | ✅ VM `--restart always` | ✅ VM 同左 | ✅ 実機 WinSW `onfailure`（約6秒で復帰） |
| グレースフル停止（SIGTERM/SIGINT） | ✅ 実機 `STOP`記録 | ✅ VM | ✅ 実機 Ctrl+C→SIGINT（OS停止時も） |
| スリープ復帰後の生存 | ✅ 実機スリープ ~126s | ✅ 実host suspend ~122s（VM・同一pid・連番+1）＋`docker pause` | ✅ 実機 S0スタンバイ ~148s |

- **結論**: SEA単一バイナリは、3プラットフォームとも**OSのサービス管理下で「再起動をまたいで自動復帰する常駐サービス」として実用に足る**。スリープは3OSとも「同一プロセスが凍って復帰・再起動ではない」を実測で確認。
- 「再起動しても動く」の主体は**バイナリではなくOSのサービス管理**（Linux=systemd / Windows=SCM+WinSW / macOS=Docker `--restart`）。バイナリ側は行儀の良い常駐プロセスに徹する設計。
- **正直な線引き**: Linux は **Docker Desktop の Linux VM（仮想化された実Linuxカーネル）まで実測**。再起動は **systemd登録→boot自動起動を実測**（systemdコンテナ）。**残る未実測はバーメタルのカーネル/ハードウェア込み reboot と mac の launchd 登録のみ**。サービス管理の経路自体は Windows(SCM) と Linux(systemd) の両方で実証済み。
- 実機検証の全ログ・タイムラインは各 [検証記録](docs/index.md#検証ごとの記録増えていく) を参照。

## 実際にやった検証（証拠つき）

時系列で、何を叩いて何が観測できたか。詳細ログは各リンク先に。

**1. 最小SEAバイナリが単体で動く**（mac / [記録](docs/verifications/2026-08-14-initial.md)）
`dist/sea-poc` を実行すると `running inside SEA: true` と出て、封入した lodash(`_.chunk`)・dayjs の結果が表示。
node 未インストールのディレクトリへコピーしても同一出力 → **node非依存で単体完結**を確認。

**2. Linux/Windows へクロスビルドできる**（Mac→x64 / [記録](docs/verifications/2026-08-14-service-win-linux.md)）
blob はプラットフォーム非依存なので、土台nodeを公式の linux-x64 / win-x64 に差し替えて注入。
Mac から `ELF x86-64`（119MB）と `PE32+ console x86-64`（83MB）を生成。Linux版は **Mac の Docker** で実行し、
`sea=true` / `platform=linux/x64` とハートビートを確認。停止→再起動でログが追記継続することも確認。

**3. Mac再起動をまたいで自動復帰**（mac実機 / [記録](docs/verifications/2026-08-17-mac-reboot-survival.md)）
`--restart always` のコンテナを常駐させ、Macを実際に再起動。ログに
`STOP (SIGTERM)`（シャットダウン時のグレースフル停止）→ 約2分半の空白 → 新しい `START`（自動復帰）が残った。

**4. Windows実機でサービスとして本格動作**（Windows 11 / [記録](docs/verifications/2026-08-17-windows-service-real.md)）
node 未インストールの実機で `build-win.ps1` により **Macなしでネイティブビルド**（同サイズ83MB）。WinSW でサービス登録し、
以下をすべて実測：
  - 生exeを `sc create` 直指定 → 起動で `1053` 失敗（**ラッパー必須**の裏取り）
  - SCMからの停止/起動、異常終了からの自動復帰（約6秒）
  - **OS再起動をまたぐ自動起動**（起動後25秒・ログオン前に開始、heartbeat `#1`〜`#541` 欠番なし）
  - グレースフル停止が **OSシャットダウン時にも**機能（Ctrl+C→SIGINT）

**5. スリープ（suspend/resume）をまたいで生存**（mac / Linux / [記録](docs/verifications/2026-08-17-mac-linux-sleep.md)）
mac は実機を約126秒スリープ、Linux は `docker pause` に加え、**mac実機スリープ時に Docker の Linux VM も実サスペンド**
された痕跡（別コンテナ `seademo` が `#7463 → #7464`、約122秒の空白）を取得。3OSとも共通の挙動：
**同一pidのまま凍って復帰・再起動ではない・`setInterval`は止まってキャッチアップしない**（時間は実時計で進む）。

**6. Linux も systemd 登録 → 再起動で自動起動**（systemdコンテナ / [記録](docs/verifications/2026-08-17-linux-systemd-reboot.md)）
systemd が動くコンテナで `systemctl enable` → **`docker restart`（systemd を boot し直す）**。
`systemctl start` を打たずに、再起動後 systemd が enabled ユニットを自動起動（新しい Main PID・新しい `START`・
journal の `Started`）。これで「サービス登録→再起動で自動起動」を **Windows(SCM) と Linux(systemd) の両方で実測**。

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
