# 検証 2026-08-17 — mac / Linux スリープ（suspend/resume）をまたぐ生存

[2026-08-17 Windows実機](2026-08-17-windows-service-real.md) では S0スタンバイでの生存を確認済みだった。
残していた **mac と Linux のスリープ検証**を実施し、3プラットフォームで挙動を突き合わせた。

## 目的

常駐する SEAサービスが、**スリープ（プロセス凍結→復帰）をまたいで生き残るか**を mac / Linux で確認する。
観点は Windows と同じ：①同一プロセスが生存するか（再起動でないか）②ログに空白が出るか
③`setInterval` が復帰後にキャッチアップするか。

## 追加資材

- **mac用サービスバイナリ（新規）** `dist/mac-arm64/sea-svc`
  … プラットフォーム非依存の `dist/service.blob` を mac の公式node（`vendor/`）に postject 注入し、
  `--macho-segment-name NODE_SEA` + ad-hoc署名して生成。`platform=darwin/arm64` / `sea=true` を確認。

## 方法

| OS | スリープの与え方 | 補足 |
|---|---|---|
| Linux(x64) | `docker pause` → `docker unpause` | コンテナのプロセスを cgroup freezer で凍結＝**suspend相当**。実host suspendはコンテナ共有カーネルの都合で不可のため、プロセスが受ける挙動の忠実な代役として採用 |
| macOS(arm64) | 実機を**実際にスリープ→復帰**（ユーザー操作） | ネイティブプロセスを `nohup` で常駐させ、Mac本体をスリープ |

いずれも待機は `ping`（`sleep` 非使用）で作った。ハートビート間隔は 5秒。

## 結果 — ✅ 両OSとも生存

### Linux（docker pause 約45秒）

```
03:33:03 [pid 1] heartbeat #2 uptime=10s
   ── 約45秒 凍結（docker pause）──
03:33:52 [pid 1] heartbeat #3 uptime=59s
03:33:57 [pid 1] heartbeat #4 uptime=64s
```
- host側PID = **12113 のまま**（凍結前後で不変）／新しい START 行なし。
- 空白中はハートビート無し。復帰後は `#3` が1発だけ（本来9発ぶん）。
- `uptime` は 10s→59s（+49s）と実時間を刻む。→ `setInterval` は凍結中停止・非キャッチアップ。

### macOS（実機スリープ 約126秒）

```
12:37:27 [pid 37786] heartbeat #30 uptime=150s
   ── 約126秒 スリープ ──
12:39:33 [pid 37786] heartbeat #31 uptime=276s
```
- **pid 37786 のまま**（プロセス連続・START行=1）／新しい START 行なし。
- 空白約126秒。復帰後は `#31` が1発だけ（本来25発ぶん）。
- `uptime` は 150s→276s（+126s）。→ 同上。
- 停止時に `STOP (SIGTERM) after 52 beats` を記録＝グレースフル停止も確認。

### 追加証拠 — Linux(VM)を「実host suspend」でも実測

`docker pause` は手動凍結の代役だが、**mac実機スリープ時に、別途常駐していたLinuxコンテナ
`seademo`（Docker Desktop の Linux VM 上）も一緒にサスペンドされていた**。
そのログ `dist/rundata/daemon.log` に本物の suspend 痕跡が残っていた（JST）:

```
12:37:59 heartbeat #7463     ← スリープ突入前
   ── 約122秒の空白（Mac＝Docker Linux VM がサスペンド）──
12:40:01 heartbeat #7464     ← 復帰後
```
- **`#7463 → #7464` と連番+1のみ**（新STARTなし・`RestartCount=0`）＝同一プロセスが凍って復帰。
- `docker pause` ではなく、**macOSのハードウェアスリープが Docker の Linux VM ごと実際に suspend/resume**
  したもの。バーチャルとはいえ**実Linuxカーネルの suspend を通した本物の証拠**。

**おまけ（再起動 vs スリープの対照）**: 同じ `daemon.log` には先の Mac 再起動の痕跡も別空白として残る:
```
10:30:36 STOP     ← 再起動（シャットダウン）
   ── 146秒 ──
10:33:02 START    ← 再起動後、別プロセスで復帰
```
→ **再起動＝STOP/STARTでプロセス作り直し／スリープ＝連番のまま凍って復帰**、が1本のログで対照できる。

## 3プラットフォーム比較

| | 同一プロセス生存 | 新START | ログ空白 | setInterval |
|---|---|---|---|---|
| Windows (S0スタンバイ) | ✅ pid維持 | 無し | ✅ ~148s | 停止・非キャッチアップ |
| Linux (docker freeze) | ✅ pid 12113維持 | 無し | ✅ ~45s | 停止・非キャッチアップ |
| macOS (実機スリープ) | ✅ pid 37786維持 | 無し | ✅ ~126s | 停止・非キャッチアップ |

## 結論

- **スリープをまたいでも SEAサービスは同一プロセスのまま生存し、復帰と同時に自力で再開する**ことを
  mac / Linux で確認。Windows S0 と完全に同じ挙動で、3プラットフォーム共通の性質と言える。
- 再起動（プロセス作り直し＝新START）とは明確に異なり、**スリープは「凍って起きる」**。
- **`setInterval` はスリープ中止まり、復帰後もキャッチアップしない**（→[pitfalls P8](../pitfalls.md)）。
  これはSEA固有ではなくNode/OS共通だが、常駐サービスでは必ず踏む。時間依存の判断は実時計で行うこと。

## 注記・線引き

- Linux は2通りで確認: ①`docker pause`（手動プロセス凍結の代役）②mac実機スリープ時に Docker Linux VM
  ごと実サスペンドされた `seademo` の実測（上記「追加証拠」）。**バーチャルとはいえ実Linuxカーネルの
  suspend/resume を通している**。ただし **バーメタルLinuxの `systemctl suspend`（実デバイス電源断を伴う
  ACPI S3）は未実施**。完全に詰めるなら実Linux機かフルVMが要る。
- mac は「システムスリープ」で実施（S3/Modern Standby等の区別はしていない）。
- 休止状態(S4)相当は未実施だが、電源断をまたぐ復帰は各再起動テストでカバー済み。
