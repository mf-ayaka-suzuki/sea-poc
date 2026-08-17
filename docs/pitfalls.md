# ハマりどころ（再発時の早見表）

検証を回すと再発しやすい壁。症状で引けるようにしておく。新しい壁に当たったら追記する。

| # | 症状（エラー） | 原因 | 対処 |
|---|---|---|---|
| P1 | `node: bad option: --experimental-sea-config` | node18等、SEA未対応のnodeを使っている | Node 20+ を使う（→[decisions D1](decisions.md)） |
| P2 | postject `Can't read and write to target executable` | コピーしたnodeが `0555`（書込不可） | 複製直後に `chmod u+w` |
| P3 | postject `Could not find the sentinel NODE_SEA_FUSE...` | Homebrew版nodeはstripされfuse無し | nodejs.org公式バイナリを土台にする（→[decisions D2](decisions.md)） |
| P4 | クロスビルド時の警告：Linux `Can't find string offset for section name '.note...'` / Windows `The signature seems corrupted!` | Linux=ELFセクション注記の警告、Windows=注入で公式署名が無効化されただけ | **いずれも無害**。注入は成功する（`💉 Injection done!`）。Windowsは必要なら自前署名 |
| P5 | Windowsで `sc create` 直指定したサービスが `StartService FAILED 1053`（起動要求に応答しない）で失敗 | 生exeはSCM制御に応答しない（サービスアウェアでない）。**登録自体は成功するので気づきにくい** | WinSW / NSSM 等の**ラッパー**でサービス化（→[deploy/windows](../deploy/windows/README.md)）。2026-08-17に実機で再現確認済 |
| P6 | 日本語コメント入りの `.ps1` が `Unexpected token` / `The string is missing the terminator` で落ちる | Windows PowerShell 5.1 は **BOM無しの .ps1 をANSIとして読む**ため、UTF-8の日本語が文字化けしてクォートが壊れる | `.ps1` は **UTF-8 BOM付き**で保存する（→下記コマンド） |
| P7 | WinSW の `install` / `start` が権限エラーになる、または `Get-Service` はあるのに操作できない | サービス登録・操作には管理者権限が必要。Administratorsグループ所属でもUACで**フィルタ済みトークン**になっている | 管理者PowerShellで実行（`Start-Process powershell -Verb RunAs`）。`whoami /groups` で `BUILTIN\Administrators` が `Group used for deny only` なら未昇格 |
| P8 | スリープをまたぐと「定期処理の実行回数」が実経過時間と合わない（例: 5秒間隔なのに148秒の空白で1回しか進まない） | **スリープ中は `setInterval` が停止**し、復帰後もまとめ発火（キャッチアップ）しない。プロセスは生きたままなので気づきにくい | 時間に依存する判断は必ず**実時計**（`Date` / `process.uptime()`）で行う。発火回数を時間の代用にしない。2026-08-17に Windows(S0)/Linux(freeze)/mac実機 の3プラットフォームで実測 |

## 確認コマンド

```bash
# 使うnodeがSEA対応か（20+か）
<node> -v

# 土台nodeに注入用センチネルがあるか（1なら注入可能、0だと P3）
strings -a <node-binary> | grep -c NODE_SEA_FUSE

# 複製バイナリが書込可能か（NOT writable だと P2）
test -w dist/sea-poc && echo writable || echo "NOT writable"
```

Windows（PowerShell）:

```powershell
# 土台node.exe にセンチネルがあるか（見つからなければ P3）
$b = [IO.File]::ReadAllBytes('vendor\node-v22.23.2-win-x64\node.exe')
$s = [Text.Encoding]::ASCII.GetString($b)
if ($s.Contains('NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2')) { 'sentinel OK' } else { 'NO sentinel' }

# .ps1 に BOM があるか（239,187,191 でなければ P6）
[IO.File]::ReadAllBytes('build-win.ps1')[0..2] -join ','

# BOM を付け直す
$p = 'build-win.ps1'
$t = [IO.File]::ReadAllText($p, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($true))

# 昇格しているか（False だと P7）
(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
```

## 補足

- P2/P3 は「Homebrewのnodeをそのまま土台にした」ときに続けて出やすい。
  最初から `vendor/` の公式nodeをフルパスで使えば両方回避できる。
