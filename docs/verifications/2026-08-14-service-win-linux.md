# 検証 2026-08-14 — Windows/Linux でのサービス動作（x64）

## 目的

SEAバイナリが Windows/Linux で「サービスとして動く（スリープ・再起動をまたいで動き続ける）」かを確認する。
そのために常駐する簡単なプログラム（ハートビート）を追加した。

## 方針（この検証の前提）

- **テスト環境**: MacのDockerでLinux版を実際に実行して実証。Windowsはバイナリ＋サービス登録手順を用意（実機テストはユーザー側）。
- **アーキ**: x64（Intel/AMD）。
- 「再起動しても動く」の本体は**バイナリではなくOSのサービス管理**（Linux=systemd / Windows=SCM）。
  検証は ①バイナリが常駐プロセスとして動くか ②サービス管理が再起動をまたいで生かすか の2段。

## 追加したもの

- `src/service.js` … 常駐ハートビート。一定間隔でタイムスタンプ付き行をログ追記、SIGTERM/INTで綺麗に停止。
  環境変数で挙動を制御（`SEA_SVC_LOG` / `SEA_SVC_INTERVAL_MS` / `SEA_SVC_MAX`）。lodash/dayjsも使用。
- `build-cross.sh` … Linux(x64)/Windows(x64) 向けクロスビルド（blobは共通、土台nodeだけ差し替えて注入）。
- `deploy/linux/`（systemd unit + 手順）, `deploy/windows/`（WinSW設定 + 手順）。

## クロスビルド結果

| ターゲット | 成果物                     | file判定             | サイズ  |
| ---------- | -------------------------- | -------------------- | ------- |
| linux-x64  | `dist/linux-x64/sea-svc`   | ELF 64-bit x86-64    | 約119MB |
| win-x64    | `dist/win-x64/sea-svc.exe` | PE32+ console x86-64 | 約83MB  |

- postjectの警告は無害：Linuxの `.note` 系はセクション注記、Windowsの `signature seems corrupted!` は
  公式node.exeのAuthenticode署名が注入で無効化されただけ（実行可）。詳細は [pitfalls P4/P5](../pitfalls.md)。

## Linux 実行検証（Mac Docker / linux/amd64）— ✅

**① 単体実行・SEA動作・パッケージ動作**

```
$ docker run --rm --platform linux/amd64 -v .../dist/linux-x64:/app:ro -v .../rundata:/data \
    -e SEA_SVC_LOG=/data/sea-svc.log -e SEA_SVC_INTERVAL_MS=500 -e SEA_SVC_MAX=3 \
    debian:stable-slim /app/sea-svc
2026-08-14 08:48:03 [pid 1] START sea=true node=v22.23.2 platform=linux/x64 host=da8c277958cb ...
2026-08-14 08:48:03 [pid 1] heartbeat #1 uptime=1s
... heartbeat #2, #3 ...
```

→ `sea=true`、`platform=linux/x64`、ハートビートがログに永続化。封入パッケージも内部で動作。

**② 停止→再起動の継続性**（別コンテナで2回起動＝再起動相当）

```
START ... host=4831ca609300   ← 1回目
heartbeat #1, #2, DONE
START ... host=622a984702f1   ← 2回目（host が変わる＝別プロセス）
heartbeat #1, #2, DONE
```

→ 同じログに追記で継続。起動回数=2。「止めて立ち上げ直しても復帰し、記録が続く」ことを確認。

**③ 常駐デーモン＋自動再起動ポリシー**

```
$ docker run -d --restart always ... /app/sea-svc
STATUS=Up  RestartPolicy=always  Running=true  PID(host)=91419
```

→ 無限常駐プロセスとして稼働。`--restart always`（サービス管理の代役）で管理下に置ける。

## Windows（手順のみ・実機はユーザー側）

- `dist/win-x64/sea-svc.exe` を実機へ転送し、**WinSW か NSSM でサービス化**（[deploy/windows/README](../../deploy/windows/README.md)）。
- 生exeはSCM非対応のため `sc create` 直指定は不可 → ラッパー必須（[pitfalls P5](../pitfalls.md)）。
- `startmode=Automatic` で再起動後も自動起動。再起動テスト手順もREADMEに記載。

## 結論

- **Linux**: MacのDockerで、SEA単体バイナリが常駐サービスとして動作し、再起動をまたぐ継続性（ログ追記＋自動再起動ポリシー）を確認。実運用は systemd unit（`enable`で自動起動）で成立。✅
- **Windows**: x64バイナリのビルドまで完了。実機での再起動テストは WinSW/NSSM 手順に沿ってユーザー側で実施予定。⏳

## 次にやると良いこと（メモ）

- 実Linuxホスト(またはsystemd有効コンテナ)で `reboot` をまたぐ本番相当テスト。
- Windows実機で WinSW 登録 → `Restart-Computer` 後の自動起動確認。
- スリープ(suspend/resume)復帰後のプロセス生存確認（両OS）。
