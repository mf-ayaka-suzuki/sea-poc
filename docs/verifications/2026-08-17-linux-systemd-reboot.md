# 検証 2026-08-17 — Linux systemd 登録 → 再起動で自動起動（実測）

これまで Linux の「OSのサービス登録（systemd）→ 再起動で自動起動」は **手順のみ（未実測）** として残していた
（[deploy/linux](../../deploy/linux/README.md)）。この核心部分を、**systemdが実際に動くコンテナ**上で実測した。

## 目的

`systemctl enable` でサービス登録したら、**systemdの起動時に（`systemctl start` を打たずに）自動でサービスが立ち上がる**か
を確認する。＝ Windows で確認済みの「サービス登録→再起動で自動起動」を Linux/systemd でも実測する。

## なぜ実機（バーメタル）の再起動でやらなかったか / コマンドで代用した旨

本来もっとも確実なのは、**物理Linux機（またはフルLinux VM）を `sudo reboot`** して、電源投入から
カーネル起動 → systemd初期化 → enabledサービス自動起動、までを通すこと。今回はそれを行わず、
**コマンド（systemdコンテナ + `docker restart`）で代用**した。理由と線引きを残す。

**なぜ実機でやらなかったか（環境的制約）**
- このセッションはユーザーのMac（macOS/Apple Silicon）上で動いており、**接続された空きの物理Linux機が無い**。
- **Dockerコンテナはホストとカーネルを共有**するため、コンテナ内から本物のカーネル再起動はできない
  （`systemctl reboot` はコンテナを停止するだけ）。＝Dockerでは"実機reboot"は原理的に不可。
- フルLinux VM（multipass/lima等）なら実ゲストカーネルの reboot が可能だが、**ソフト導入・VM作成のコストを避け**、
  今回は立てない判断をした（ユーザー判断）。

**コマンドで代用したこと**
- 「サービスが再起動後に自動で戻る」の**サービス管理経路**を、**systemdコンテナ + `docker restart`** で実測
  （`systemctl enable` → systemd を boot し直す → 手動 start なしで自動起動）。これは systemd の
  「登録 → boot → 自動起動」という経路を**本物として実行**している（下記ログ参照）。
- 「落ちても戻る」の一般挙動は Docker `--restart always` でも実測済み（[別記録](2026-08-14-service-win-linux.md)）。

**この代用でカバーできない範囲（正直な未実測）**
- 物理的な電源断・ファームウェア/BIOS・カーネル起動シーケンス・デバイス再初期化。
- フルシステムブート時の systemd の起動順序（依存関係）全体。
- ＝**サービス管理の経路は実証済みだが、カーネル/ハードウェア込みの再起動は未実証**。
  実機で詰めるなら物理Linux機かフルVMで `sudo reboot`。

## 方法と線引き

- Mac の Docker 上に、**systemdをPID1で動かせるコンテナ**を用意（`jrei/systemd-ubuntu:22.04`,
  `--privileged --cgroupns=host`, `/sys/fs/cgroup` マウント, `--platform linux/amd64`）。
- そこへ SEAバイナリ（`dist/linux-x64/sea-svc`）と systemd ユニットを入れ、`systemctl enable --now`。
- **"再起動" は `docker restart`**：これは systemd(PID1) をシャットダウン→再 boot させるので、
  enabled なユニットは boot 時に自動起動する。
- **線引き**: これは systemd の「登録→シャットダウン→boot→自動起動」という経路を**本物として実行**している。
  ただし **バーメタルのカーネル/ハードウェア込みの reboot ではない**（ホストのカーネルは共有）。
  サービス管理の経路（今まで手順のみだった箇所）は実測できたが、カーネルレベルの再起動は範囲外。

## 実施ログ

### 1. サービス登録（enable）— ✅

```
systemctl enable --now sea-svc
  Created symlink /etc/systemd/system/multi-user.target.wants/sea-svc.service -> /etc/systemd/system/sea-svc.service
systemctl is-enabled sea-svc → enabled
systemctl is-active  sea-svc → active
  Main PID: 81 (sea-svc)
```
ログ: `04:09:52 [pid 81] START ...` からハートビート開始。

### 2. 再起動（docker restart = systemd を boot し直す）— ✅ 自動起動

再起動後、**`systemctl start` を打たずに**状態を確認:

```
systemctl is-system-running → running
systemctl is-enabled sea-svc → enabled
systemctl is-active  sea-svc → active
  Active: active (running) since 2026-08-17 04:10:26 UTC
  Main PID: 24 (sea-svc)          ← 再起動前の 81 とは別プロセス
journalctl -u sea-svc:
  Aug 17 04:10:26 systemd[1]: Started SEA heartbeat service (PoC / systemd real test).
```

ログ（同一ファイルに boot をまたいで新しい START）:

```
04:09:52 [pid 81] START ...        ← 初回
   … heartbeat #1〜#23 …
   ── docker restart（systemd reboot）──
04:10:26 [pid 24] START ...        ← 再起動後、systemd が enable だけで自動起動
   … heartbeat #1〜 …
```
START行の数 = 2（初回 ＋ 再起動後の自動起動）。

## 結論

- **Linux でも「systemctl enable でサービス登録 → 再起動で自動起動」を実測できた。** ✅
  手動 start なしで、systemd が boot 時に enabled ユニットを起動することを確認（journal の `Started` と
  新しい Main PID・新しい START 行で裏取り）。
- これで「再起動しても動く」を **OSのサービス登録レベルで実測できたのは Windows のみ** だった状態が解消し、
  **Windows(SCM/WinSW) と Linux(systemd) の両方で実測**になった。
- 残る未実測は **バーメタルLinuxのカーネル/ハードウェア込み reboot** と **mac の launchd 登録** のみ。
  ただしサービス管理の経路自体は実証済みで、これらも同様に動く見込み。

## 再現メモ

```bash
docker run -d --name seasystemd --privileged --cgroupns=host --platform linux/amd64 \
  --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$PWD/dist/linux-x64:/opt/app:ro" -v "$PWD/dist/rundata:/data" \
  jrei/systemd-ubuntu:22.04
# ユニット配置 → systemctl daemon-reload && systemctl enable --now sea-svc
docker restart seasystemd          # = systemd を boot し直す
docker exec seasystemd systemctl is-active sea-svc   # start なしで active なら成功
docker rm -f seasystemd
```
