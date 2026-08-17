# 検証 2026-08-17 — Windows実機でのサービス動作（x64・ネイティブビルド）

前回 [2026-08-14 Win/Linuxのサービス動作](2026-08-14-service-win-linux.md) で「⏳（手順のみ・実機未検証）」
として残していた **Windows実機テスト**を実施した。あわせて、Mac経由のクロスビルドではなく
**Windows単体でのネイティブビルド**が成立するかも確認した。

## 目的

1. Windows実機で SEA 単一実行バイナリを**ビルドできる**か（Macなしで完結するか）
2. そのバイナリが **Windowsサービスとして登録・起動できる**か
3. サービスとして **止められ・自動復帰し・再起動をまたいで動く**か

## 検証環境

| 項目 | 値 |
|---|---|
| OS | Windows 11 Enterprise 10.0.26100 (x64) |
| ホスト名 | DESKTOP-CC3AVOD |
| 初期状態 | **node 未インストール**（`node` / `npm` / `npx` いずれもPATHに無し） |
| セッション権限 | 非管理者（UACフィルタ済みトークン）。ただしユーザーは Administrators グループのメンバー |
| Node（土台/ツール） | `vendor/node-v22.23.2-win-x64`（nodejs.org公式・システム未インストール） |
| サービスラッパー | WinSW v2.12.0 (`WinSW-x64.exe`, 約17.4MB) |
| 作業ディレクトリ | ビルド `C:\sea-poc\sea-poc` / 配置 `C:\sea-svc` |
| 電源設定 | スリープは **S0 Modern Standby**（S1〜S3非対応）。休止状態・高速スタートアップ有効 |

## 実施したこと

### 0. 追加した資材

- **`build-win.ps1`（新規）** … `build-cross.sh` の Windows 版。
  bundle(esbuild) → blob生成 → `node.exe` 複製 → postject注入 を PowerShell で完結させる。
  ツール実行も `vendor/` の公式nodeを使うため、**システムに node を入れない／PATHも汚さない**
  という既存方針（[decisions D2](../decisions.md)）をそのまま踏襲している。

### 1. 公式node の取得と検証

```
node-v22.23.2-win-x64.zip  34MB
SHA-256 expected: 1177b4137ba5adaa56354ae40f1080c7450e8ae09cecb47da459d1c52ac99f97
SHA-256 actual  : 1177b4137ba5adaa56354ae40f1080c7450e8ae09cecb47da459d1c52ac99f97   → OK
```

展開した `node.exe` に注入用センチネルが含まれることも実測で確認した
（`NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2` を **offset 40290728** に検出）。
→ [decisions D2](../decisions.md) / [pitfalls P3](../pitfalls.md) の前提が Windows 公式バイナリでも成立。

### 2. ネイティブビルド — ✅

```
>> [1/4] bundle service (esbuild)     dist\service.bundle.js  233.6kb
>> [2/4] generate blob                Wrote single executable preparation blob to dist/service.blob
>> [3/4] copy official node.exe
>> [4/4] inject blob (postject)
    warning: The signature seems corrupted!
    💉 Injection done!

dist\win-x64\sea-svc.exe   83.3 MB (87,363,072 bytes)
```

- `signature seems corrupted!` は既知の無害警告（[pitfalls P4](../pitfalls.md)）。実行に支障なし。
- サイズは 2026-08-14 のクロスビルド成果物（約83MB）と一致。
  **Mac経由でも Windows 単体でも同等の成果物が得られる**ことを確認。

### 3. exe単体での常駐動作 — ✅

`SEA_SVC_INTERVAL_MS=500` / `SEA_SVC_MAX=3` で実行:

```
2026-08-17 10:50:49 [pid 9636] START sea=true node=v22.23.2 platform=win32/x64 host=DESKTOP-CC3AVOD ...
2026-08-17 10:50:50 [pid 9636] heartbeat #1 uptime=1s
2026-08-17 10:50:50 [pid 9636] heartbeat #2 uptime=1s
2026-08-17 10:50:51 [pid 9636] heartbeat #3 uptime=2s
2026-08-17 10:50:51 [pid 9636] DONE reached max 3 beats
```

→ `sea=true` / `platform=win32/x64`。封入した lodash・dayjs も内部で動作
（`_.trim` によるSTART行整形、`dayjs().format()` によるタイムスタンプ）。

### 4. 「生exeは直接サービス化できない」の実証 — ✅（想定どおり失敗）

[pitfalls P5](../pitfalls.md) の主張を実際に叩いて確認した。

```powershell
sc.exe create sea-svc-raw binPath= "C:\sea-svc\sea-svc.exe" start= demand
# [SC] CreateService SUCCESS   ← 登録自体は通る
sc.exe start sea-svc-raw
# [SC] StartService FAILED 1053:
# そのサービスは指定時間内に開始要求または制御要求に応答しませんでした。
```

→ **登録は成功するが起動で 1053 になる**。SCMハンドシェイクに応答しないため。ラッパー必須が裏取りできた。
（テスト後 `sc.exe delete sea-svc-raw` で削除済み）

### 5. WinSW でのサービス化 — ✅

`deploy/windows/README.md` の方法A（WinSW）どおりに配置:

```
C:\sea-svc\
  sea-svc.exe            ← ビルド成果物
  sea-svc-wrapper.exe    ← WinSW-x64.exe (v2.12.0) をリネーム
  sea-svc-wrapper.xml    ← deploy/windows/sea-svc.xml をリネーム
```

管理者PowerShell（UAC昇格）で:

```
> .\sea-svc-wrapper.exe install
  Service 'SEA Heartbeat Service (PoC) (sea-svc)' was installed successfully.
> .\sea-svc-wrapper.exe start
  Service 'SEA Heartbeat Service (PoC) (sea-svc)' started successfully.
```

登録結果:

```
SERVICE_NAME: sea-svc
        TYPE               : 10  WIN32_OWN_PROCESS
        START_TYPE         : 2   AUTO_START            ← 再起動後の自動起動
        BINARY_PATH_NAME   : "C:\sea-svc\sea-svc-wrapper.exe"
        SERVICE_START_NAME : LocalSystem
FAILURE_ACTIONS            : RESTART -- 遅延 = 2000 ミリ秒です。   ← onfailure が反映済み
Status: Running / StartType: Automatic
```

サービス配下でハートビートが継続:

```
2026-08-17 10:53:12 [pid 2580] START sea=true node=v22.23.2 platform=win32/x64 host=DESKTOP-CC3AVOD log=C:\sea-svc\sea-svc.log interval=5000ms
2026-08-17 10:53:17 [pid 2580] heartbeat #1 uptime=5s
... （5秒間隔で継続）
```

プロセス構成は **`sea-svc-wrapper.exe`（SCM窓口）→ `sea-svc.exe`（実体）の親子2プロセス**。

### 6. SCM からの停止／起動 — ✅

```
child pid before: 2580
Stop-Service sea-svc -Force
  status after stop: Stopped
  sea-svc process alive after stop: False     ← 子プロセスも確実に落ちる
Start-Service sea-svc
  status after start: Running   child pid after: 13896
```

ログ側:

```
2026-08-17 10:54:04 [pid 2580] STOP (SIGINT) after 10 beats     ← 綺麗に停止
2026-08-17 10:54:08 [pid 13896] START sea=true ...              ← 別pidで再開
```

**重要な確認**: WinSW は停止時に子プロセスへ Ctrl+C を送り、`src/service.js` の
`SIGINT` ハンドラがそれを捕捉して `STOP` を記録してから終了している。
つまり Windows でも**グレースフルシャットダウンが成立**している
（Unix系の SIGTERM 前提の実装が、そのまま Windows でも機能した）。

### 7. プロセス強制終了からの自動復帰 — ✅

```
killing pid 13896        （Stop-Process -Force ＝ 異常終了を模擬）
… 15秒待機 …
status: Running   pid now: 8796   (restarted: True)
```

ログ側:

```
2026-08-17 10:54:14 [pid 8796] START sea=true ...
2026-08-17 10:54:19 [pid 8796] heartbeat #1 uptime=5s
2026-08-17 10:54:24 [pid 8796] heartbeat #2 uptime=10s
```

→ `sea-svc.xml` の `<onfailure action="restart" delay="2 sec"/>` が SCM の
FAILURE_ACTIONS として効き、**約6秒で新pidに復帰**。同じログファイルに追記で継続。

### 8. OS再起動をまたぐ自動起動 — ✅

`Restart-Computer` による実再起動をはさんで確認した。

**タイムライン**（`sea-svc.log` と `sea-svc-wrapper.wrapper.log` の突き合わせ）:

```
10:59:45  [pid 8796] STOP (SIGINT) after 66 beats   ← OSシャットダウン時にグレースフル停止
11:00:10  ── OS起動（Win32_OperatingSystem.LastBootUpTime）──
11:00:32  wrapper: Starting WinSW in service mode    ← ログオン前に起動（LocalSystem）
11:00:34  wrapper: Started process 2060
11:00:35  [pid 2060] START sea=true node=v22.23.2 platform=win32/x64 host=DESKTOP-CC3AVOD
11:00:40  [pid 2060] heartbeat #1 uptime=5s
   …
11:45:30  [pid 2060] heartbeat #541 uptime=2705s     ← 約45分間、無停止で継続
```

判定:

| 確認点 | 結果 |
|---|---|
| 再起動後 `Get-Service sea-svc` | `Running` |
| 再起動時刻(11:00:10)より後の新しいSTART行 | ✅ 11:00:35 / **pid 2060**（再起動前の 8796 とは別プロセス） |
| 起動までの所要 | OS起動から **約25秒**、ユーザーのログオン操作を待たずに開始 |
| heartbeat の連続性 | ✅ `#1`〜`#541` が欠番なし（5秒間隔・約45分） |
| ログの継続性 | ✅ 同一ファイルに追記。再起動をまたいで1本の記録として読める |

**副次的に判明したこと — シャットダウンもグレースフルだった**

再起動前の最後の行が `STOP (SIGINT) after 66 beats` になっている。つまり Windows のシャットダウン時にも
SCM → WinSW → 子プロセスへ Ctrl+C という経路が働き、`src/service.js` の SIGINT ハンドラが
**後片付けを実行してから終了している**（プロセスを問答無用でkillされたわけではない）。

これは項6（SCMからの停止）と同じ経路が OS 停止時にも通ることを意味し、
「終了時にフラッシュ・クローズ処理が必要な実サービス」でも設計が成立することを示す。

### 9. スリープ（S0 Modern Standby）をまたぐ生存 — ✅

**この機体のスリープは S0（低電力アイドル）**であることを先に確認した。S1〜S3 は
ファームウェアが非対応で、従来型の「メモリ以外は電源断」とは別物として読む必要がある。

```
> powercfg /a
利用可能: スタンバイ (S0 低電力アイドル) ネットワークに接続されています / 休止状態 / 高速スタートアップ
利用不可: スタンバイ (S1) (S2) (S3) / ハイブリッド スリープ
```

`Application.SetSuspendState(Suspend)` でスリープさせ、手動で復帰させた。

**イベントログによる裏取り**（Microsoft-Windows-Power-Troubleshooter）:

```
Sleep Time: 2026-08-17T03:13:05Z (JST 12:13:05)
Wake  Time: 2026-08-17T03:15:35Z (JST 12:15:35)   ← 149.6秒間スリープ
```

**サービスのログ**:

```
2026-08-17 12:13:02 [pid 2060] heartbeat #868 uptime=4348s
2026-08-17 12:13:07 [pid 2060] heartbeat #869 uptime=4353s   ← スリープ突入直後の最後の1発
        ── 約148秒の空白（スリープ中）──
2026-08-17 12:15:35 [pid 2060] heartbeat #870 uptime=4505s   ← 復帰と同時に自力で再開
2026-08-17 12:15:40 [pid 2060] heartbeat #871 uptime=4510s
```

判定:

| 確認点 | 結果 |
|---|---|
| pid | ✅ **2060 のまま変化なし**（再起動と違いプロセスは終了していない） |
| 新しい START 行 | ✅ 出ていない（＝再起動ではなく、同一プロセスが眠って起きただけ） |
| 復帰後の自動再開 | ✅ 復帰と同時刻(12:15:35)に heartbeat 再開。**人手の介入は不要** |
| `Get-Service sea-svc` | ✅ `Running` を維持 |
| ログの継続性 | ✅ 同一ファイルに追記。空白期間を挟んで1本の記録として読める |

**重要な挙動 — タイマーはスリープ中に止まり、取り戻さない**

空白は約148秒あるが、heartbeat の**連番は #869 → #870 と1つしか進んでいない**。
5秒間隔なら本来29発ぶんの時間が経過しているのに、まとめて発火（キャッチアップ）はされていない。
一方 `process.uptime()` は `4353 → 4505`（+152秒）と**実時間を刻み続けている**。

つまり Node の `setInterval` は S0スタンバイ中に停止し、復帰後は「次の1発」から普通に再開する。
**「ハートビート回数 × 間隔 ＝ 経過時間」は成立しない。**
定期実行の回数で時間を数える設計にすると、スリープをまたいだ瞬間にずれる
（→[pitfalls P8](../pitfalls.md)）。時間に依存する処理は必ず実時計（`Date` / `process.uptime()`）で判断すること。

なお **休止状態(S4)** も利用可能だが今回は未実施。S0で生存が確認できたことと、
電源断をまたぐ復帰は項8の再起動テストでカバーされているため、追加検証の優先度は低い。

## 結論

**SEA単一実行バイナリは、Windowsサービスとして実用に足る形で動く。** 当初の検証目的はすべて達成した。

- **Windows実機で SEA バイナリを Macなし・node未インストールのままビルドできる**（`build-win.ps1`）。✅
  Mac経由のクロスビルド成果物と同サイズ・同挙動。
- **WinSW ラッパー経由で正式な Windowsサービスとして動作する**。✅
  - 自動起動(`Automatic`)登録、SCMからの停止/起動、異常終了からの自動復帰、
    そして **OS再起動をまたぐ自動起動**まで実測で確認。
  - グレースフル停止（Ctrl+C → SIGINTハンドラ）が、SCM停止時だけでなく
    **OSシャットダウン時にも機能する**。Unix向けに書いた後片付けコードが無改修でそのまま効く。
  - **S0スタンバイ（スリープ）をまたいでも同一pidのまま生存**し、復帰と同時に自力で再開する。✅
- 生exeの直接サービス化が 1053 で失敗することも実証済み。**ラッパー必須**は確定事項
  （`sc create` は登録が通ってしまうため、起動するまで問題に気づけない点に注意）。

**実装側への申し送り**: スリープ中は `setInterval` が止まり、復帰後もキャッチアップしない。
定期処理の**発火回数を時間の代わりに使わない**こと（→[pitfalls P8](../pitfalls.md)）。
これはSEA固有ではなくNode/OS共通の性質だが、常駐サービスでは必ず踏む。

## 後片付け（必要なとき）

```powershell
# 管理者PowerShell
cd C:\sea-svc
.\sea-svc-wrapper.exe stop
.\sea-svc-wrapper.exe uninstall
```

## 生成物・配置

| パス | 内容 |
|---|---|
| `C:\sea-poc\sea-poc\build-win.ps1` | Windowsネイティブビルドスクリプト（新規） |
| `C:\sea-poc\sea-poc\dist\win-x64\sea-svc.exe` | SEA単一実行バイナリ（83.3MB） |
| `C:\sea-svc\` | サービス配置先（本体・WinSW・XML・ログ） |
| `C:\sea-svc\sea-svc.log` | ハートビートログ（継続性の証跡） |
