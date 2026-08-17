# 検証 2026-08-17 — Mac実機の再起動をまたぐ自動復帰（Docker / --restart always）

## 目的

MacのDockerで常駐させたSEAサービスが、**Mac本体を実際に再起動しても自動で復活して動き続けるか**を確認する。
（2026-08-14 の検証③は「2回起動」による擬似再起動だったが、今回は本物のOS再起動でテスト。）

## 前提・構成

- コンテナ `seademo` を常駐起動（`-d --restart always`、`SEA_SVC_INTERVAL_MS=1000`）。
- ログは `dist/rundata/daemon.log`（コンテナ内 `/data/daemon.log`、bindマウントでMac側に永続）。
- 復帰には **Docker Desktop が起動後に立ち上がること**が前提（ログイン時自動起動、または手動起動）。

## 手順

1. 再起動前に稼働とログ最終行を確認（`docker ps` / `tail daemon.log`）。
2.  メニュー →「再起動」で Mac を実際に再起動。
3. 復帰・ログイン後、`docker ps` とログを確認。

## 結果 — ✅ 成功（実機再起動をまたいで自動復活）

ログに決定的な3点が残った。

**① 再起動時にSIGTERMで綺麗に停止**
```
2026-08-17 01:30:36 [pid 1] STOP (SIGTERM) after 315 beats
```
→ シャットダウン時、Dockerがコンテナへ送ったSIGTERMをサービスが受けて正常停止（サービスとして正しい挙動）。

**② 電源OFF中は空白（約2分半）**
`01:30:36`（停止）→ `01:33:02`（次の起動）の空白 = Mac が落ちていた時間。

**③ 再起動後に自動復活**
```
2026-08-17 01:33:02 [pid 1] START sea=true node=v22.23.2 platform=linux/x64 host=bd34f423846c interval=1000ms
2026-08-17 01:33:03 [pid 1] heartbeat #1 uptime=1s
```
→ Docker Desktop 復帰後、`--restart always` によりコンテナが自動再始動。heartbeatは `#1` から再開。

**現在の状態**
```
docker ps → bd34f423846c ... Up 4 minutes ... seademo
```
- コンテナIDが再起動前と同一（`bd34f423846c`）＝ 新規作成ではなく**既存コンテナの再始動**。
- `Up` 時間が短くリセット＝「一度落ちて起動後に立ち上げ直された」証拠。

## 結論

- **Mac実機の再起動をまたいで、SEAサービスが自動復帰して動作継続する**ことを確認。狙い（再起動をまたぐサービス動作）の本命を実証。
- あわせて **SIGTERM での正常停止**（graceful shutdown）も確認できた。
- これは Docker 層（Docker Desktop 自動起動 + `--restart always`）による復帰。実Linuxサーバでは systemd の `enable` が同じ役割（[deploy/linux](../../deploy/linux/README.md)）。

## 残（未確認）

- **Windows実機**での再起動後 自動起動（WinSW/NSSM、[deploy/windows](../../deploy/windows/README.md)）。
- **スリープ(suspend/resume)** 復帰後のプロセス生存（電源OFFではなくスリープの挙動）。
