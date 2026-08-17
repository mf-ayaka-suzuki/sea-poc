# docs インデックス

Node.js SEA 技術検証のドキュメント。**変わらない知識**と**検証ごとの記録**を分けて管理する。

## 使い方

- 検証を回すときは [runbook.md](runbook.md) の手順で。詰まったら [pitfalls.md](pitfalls.md)。
- **検証を1回やるごとに** `verifications/` に日付ファイルを1つ追加する（既存は編集しない）。
- 前提や判断が変わったら [decisions.md](decisions.md) を更新する。

## 変わらない知識

| ファイル                     | 内容                                                                 |
| ---------------------------- | -------------------------------------------------------------------- |
| [decisions.md](decisions.md) | 裁定記録：なぜこの構成か（node入手、バンドル、設定などの判断と根拠） |
| [pitfalls.md](pitfalls.md)   | ハマりどころの早見表（症状→原因→対処）                               |
| [runbook.md](runbook.md)     | 検証の回し方（セットアップ〜ビルド〜確認）                           |
| [runbook-windows.md](runbook-windows.md) | Windows単体での回し方（ビルド〜サービス登録〜確認）      |
| [../deploy/linux/](../deploy/linux/README.md) | Linuxでのサービス化（systemd unit + 再起動テスト手順） |
| [../deploy/windows/](../deploy/windows/README.md) | Windowsでのサービス化（WinSW/NSSM + 再起動テスト手順） |

## 検証ごとの記録（増えていく）

| 日付       | 記録                                                            | 結果    |
| ---------- | --------------------------------------------------------------- | ------- |
| 2026-08-14 | [初回・最小構成の立ち上げ](verifications/2026-08-14-initial.md) | ✅ 成功 |
| 2026-08-14 | [Win/Linuxのサービス動作（x64）](verifications/2026-08-14-service-win-linux.md) | Linux✅ / Win⏳(手順) |
| 2026-08-17 | [Windows実機でのサービス動作（ネイティブビルド）](verifications/2026-08-17-windows-service-real.md) | ✅ 成功（再起動・スリープまたぎも実測） |

## その他

- [SURVEY.md](SURVEY.md) — 検証のガイド（編集不可・常時読込）
