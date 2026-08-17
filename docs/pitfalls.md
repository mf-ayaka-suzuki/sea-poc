# ハマりどころ（再発時の早見表）

検証を回すと再発しやすい壁。症状で引けるようにしておく。新しい壁に当たったら追記する。

| # | 症状（エラー） | 原因 | 対処 |
|---|---|---|---|
| P1 | `node: bad option: --experimental-sea-config` | node18等、SEA未対応のnodeを使っている | Node 20+ を使う（→[decisions D1](decisions.md)） |
| P2 | postject `Can't read and write to target executable` | コピーしたnodeが `0555`（書込不可） | 複製直後に `chmod u+w` |
| P3 | postject `Could not find the sentinel NODE_SEA_FUSE...` | Homebrew版nodeはstripされfuse無し | nodejs.org公式バイナリを土台にする（→[decisions D2](decisions.md)） |
| P4 | クロスビルド時の警告：Linux `Can't find string offset for section name '.note...'` / Windows `The signature seems corrupted!` | Linux=ELFセクション注記の警告、Windows=注入で公式署名が無効化されただけ | **いずれも無害**。注入は成功する（`💉 Injection done!`）。Windowsは必要なら自前署名 |
| P5 | Windowsで `sc create` 直指定したサービスが「起動要求に応答しない」で失敗 | 生exeはSCM制御に応答しない（サービスアウェアでない） | WinSW / NSSM 等の**ラッパー**でサービス化（→[deploy/windows](../deploy/windows/README.md)） |

## 確認コマンド

```bash
# 使うnodeがSEA対応か（20+か）
<node> -v

# 土台nodeに注入用センチネルがあるか（1なら注入可能、0だと P3）
strings -a <node-binary> | grep -c NODE_SEA_FUSE

# 複製バイナリが書込可能か（NOT writable だと P2）
test -w dist/sea-poc && echo writable || echo "NOT writable"
```

## 補足

- P2/P3 は「Homebrewのnodeをそのまま土台にした」ときに続けて出やすい。
  最初から `vendor/` の公式nodeをフルパスで使えば両方回避できる。
