# Windows単体での回し方（Runbook / Windows）

Mac を経由せず **Windows実機だけ**で ビルド → サービス登録 → 確認 まで回す手順。
Mac起点の手順は [runbook.md](runbook.md)、詰まったら [pitfalls.md](pitfalls.md)。

前提: PowerShell が使えること。**node のインストールは不要**（`vendor/` に公式nodeを置いて使う）。
サービス登録の段だけ管理者権限が要る。

## 前提（初回のみ）

```powershell
$root = 'C:\sea-poc\sea-poc'; $ver = 'v22.23.2'; $tar = "node-$ver-win-x64.zip"
New-Item -ItemType Directory -Force -Path "$root\vendor" | Out-Null

# 公式node(fuse入り)を取得
Invoke-WebRequest "https://nodejs.org/dist/$ver/$tar" -OutFile "$root\vendor\$tar" -UseBasicParsing

# SHA-256 照合（必ずやる）
$sums = (Invoke-WebRequest "https://nodejs.org/dist/$ver/SHASUMS256.txt" -UseBasicParsing).Content
$exp  = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($tar) + '\s*$' }) -split '\s+' | Select-Object -First 1
$act  = (Get-FileHash "$root\vendor\$tar" -Algorithm SHA256).Hash.ToLower()
if ($exp -eq $act) { 'OK' } else { 'MISMATCH'; return }

Expand-Archive "$root\vendor\$tar" -DestinationPath "$root\vendor" -Force

# 依存インストール（vendor の npm を使う。PATHは汚さない）
Set-Location $root
& "$root\vendor\node-$ver-win-x64\npm.cmd" install --no-audit --no-fund
```

## ビルド〜単体実行（毎回）

```powershell
powershell -ExecutionPolicy Bypass -File C:\sea-poc\sea-poc\build-win.ps1
# → dist\win-x64\sea-svc.exe （約83MB）

# 単体で常駐動作を確認（3回ハートビートして終了）
$env:SEA_SVC_LOG   = "$env:TEMP\sea-svc.log"
$env:SEA_SVC_INTERVAL_MS = '500'
$env:SEA_SVC_MAX   = '3'
& C:\sea-poc\sea-poc\dist\win-x64\sea-svc.exe
```

`build-win.ps1` は `vendor/` の公式nodeを**フルパス参照**する（システムの `node` は使わない／不要）。

> 注: PowerShellスクリプトを新規に足すときは **UTF-8 BOM付き**で保存する（→[pitfalls P6](pitfalls.md)）。

## サービス登録（管理者PowerShell）

```powershell
# 1) 配置
New-Item -ItemType Directory -Force -Path C:\sea-svc | Out-Null
Copy-Item C:\sea-poc\sea-poc\dist\win-x64\sea-svc.exe C:\sea-svc\ -Force
Copy-Item C:\sea-poc\sea-poc\deploy\windows\sea-svc.xml C:\sea-svc\sea-svc-wrapper.xml -Force
Invoke-WebRequest 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe' `
  -OutFile C:\sea-svc\sea-svc-wrapper.exe -UseBasicParsing

# 2) 登録・起動（← ここから管理者権限が必要）
Set-Location C:\sea-svc
.\sea-svc-wrapper.exe install
.\sea-svc-wrapper.exe start
```

WinSW は「**自分と同名の .xml**」を設定として読む。exe と xml の名前を必ず揃える。

## 成功の確認ポイント

| 見るところ | 期待値 |
|---|---|
| `sc.exe qc sea-svc` | `START_TYPE : 2 AUTO_START`（再起動後の自動起動） |
| `Get-Service sea-svc` | `Status: Running` |
| `sc.exe qfailure sea-svc` | `FAILURE_ACTIONS : RESTART`（異常終了時の自動復帰） |
| `C:\sea-svc\sea-svc.log` | `sea=true` / `platform=win32/x64` の START 行＋heartbeatが増え続ける |
| プロセス | `sea-svc-wrapper.exe`（SCM窓口）と `sea-svc.exe`（実体）の2つ |

## 継続性テスト

```powershell
# 停止→起動（グレースフル停止の確認：ログに STOP (SIGINT) が出る）
Restart-Service sea-svc

# 異常終了からの復帰（管理者）: 子プロセスを強制終了 → 数秒で新pidのSTARTが出る
Stop-Process -Id (Get-Process sea-svc).Id -Force

# 再起動をまたぐか
Get-Content C:\sea-svc\sea-svc.log -Tail 5    # 再起動前の最終行を控える
Restart-Computer
Get-Content C:\sea-svc\sea-svc.log -Tail 20   # 復帰後に新pidのSTART行があれば成功
```

## 後片付け

```powershell
# 管理者PowerShell
Set-Location C:\sea-svc
.\sea-svc-wrapper.exe stop
.\sea-svc-wrapper.exe uninstall
```

## 成果物

- `dist\win-x64\sea-svc.exe`（約83MB）＝ 配布・実行する単体バイナリ。**これ1個で動く**。
- `dist\service.bundle.js` / `dist\service.blob` は中間物（再生成可）。
- サービス化にはこれに加えて **WinSW本体 + XML** が要る（＝配布物は実質3ファイル）。
