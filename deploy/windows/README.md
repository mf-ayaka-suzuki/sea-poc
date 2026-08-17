# Windows(x64) でサービスとして動かす

前提: `dist/win-x64/sea-svc.exe` を対象Windowsへ用意しておく。
Mac からのクロスビルド（`build-cross.sh`）でも、Windows実機でのネイティブビルド（`build-win.ps1`,
→[runbook-windows](../../docs/runbook-windows.md)）でも同じ成果物が得られる。

> **実機検証済み（2026-08-17）**: 本手順の方法A（WinSW v2.12.0）で Windows 11 x64 上での
> 登録・起動・停止・異常終了からの自動復帰まで確認した。詳細は
> [検証記録](../../docs/verifications/2026-08-17-windows-service-real.md)。

## 重要: 生のexeは直接サービスにできない

`sea-svc.exe` は普通のコンソールアプリで、Windowsサービス管理(SCM)の制御に応答しない。
そのため `sc.exe create` でこのexeを直接指定しても「起動要求に応答しない」と判定されて失敗する。
**サービス化にはラッパー**（WinSW / NSSM など）を使う。ラッパーがSCMとの橋渡しをしてくれる。

---

## 方法A: WinSW（XML設定・推奨）

1. WinSW の実行ファイル（`WinSW-x64.exe`）を入手し、`sea-svc.exe` と同じフォルダに置く。
   その際 **`sea-svc.xml` と同じ名前**にリネームする（例: `WinSW-x64.exe` → `sea-svc-wrapper.exe`、
   XMLも `sea-svc-wrapper.xml` に合わせる。WinSWは「自分と同名の.xml」を設定として読む）。
   - フォルダ構成例:
     ```
     C:\sea-svc\
       sea-svc.exe            ← 本体（クロスビルド成果物）
       sea-svc-wrapper.exe    ← WinSW本体をリネーム
       sea-svc-wrapper.xml    ← 本リポジトリの sea-svc.xml をリネーム
     ```
2. 管理者PowerShellで:
   ```powershell
   cd C:\sea-svc
   .\sea-svc-wrapper.exe install
   .\sea-svc-wrapper.exe start
   ```
3. `startmode=Automatic` なので、**再起動後も自動起動**する。

## 方法B: NSSM（対話GUIでも可）

```powershell
# 管理者PowerShell
nssm install sea-svc C:\sea-svc\sea-svc.exe
nssm set   sea-svc AppEnvironmentExtra SEA_SVC_LOG=C:\sea-svc\sea-svc.log SEA_SVC_INTERVAL_MS=5000
nssm set   sea-svc Start SERVICE_AUTO_START
nssm start sea-svc
```

---

## 「再起動しても動く」の検証手順

1. サービスが動作中か確認:
   ```powershell
   Get-Service sea-svc
   Get-Content C:\sea-svc\sea-svc.log -Tail 10 -Wait
   ```
2. ログの最終行を控えて、`Restart-Computer` で再起動。
3. 復帰後にログを見る:
   ```powershell
   Get-Content C:\sea-svc\sea-svc.log -Tail 20
   ```
   - 再起動時刻の後に **新しい START 行（新しい pid）** が出て heartbeat が再開していれば、
     「サービスが起動時に自動で立ち上がった＝再起動をまたいで動いている」証拠。
4. スリープ(スタンバイ)の場合: 復帰後もサービスプロセスは生存し heartbeat が継続する
   （スリープ中は時刻が飛ぶが終了はしない）。

## 補足（署名について）

- postject で blob を注入すると、公式 `node.exe` の Authenticode 署名は無効になる（実行は可能）。
  SmartScreen の警告が出る場合は、配布時に自前のコード署名を付けるのが実運用の作法。
