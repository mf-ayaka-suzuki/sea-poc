# Linux(x64) でサービスとして動かす（systemd）

前提: `dist/linux-x64/sea-svc`（クロスビルド済み）を対象Linuxホストへ転送しておく。

## インストール

```bash
sudo mkdir -p /opt/sea-svc
sudo cp sea-svc /opt/sea-svc/sea-svc
sudo chmod +x /opt/sea-svc/sea-svc

sudo cp sea-svc.service /etc/systemd/system/sea-svc.service
sudo systemctl daemon-reload
sudo systemctl enable --now sea-svc      # 今すぐ起動 + 起動時自動開始を有効化
```

## 動作確認

```bash
systemctl status sea-svc                 # active (running) か
sudo tail -f /var/log/sea-svc.log        # heartbeat が増え続けるか
```

## 「再起動しても動く」の検証手順

1. ログの現在の最終行を控える（`tail -n1 /var/log/sea-svc.log`）。
2. `sudo reboot` で再起動。
3. 復帰後にログを見る:
   ```bash
   tail -n 20 /var/log/sea-svc.log
   ```
   - 再起動時刻の後に **新しい START 行（新しい pid）** が出て heartbeat が再開していれば、
     「サービスが起動時に自動で立ち上がった＝再起動をまたいで動いている」証拠。
4. スリープ(suspend)の場合: `systemctl suspend` → 復帰後もプロセスは生きたまま heartbeat が続く
   （スリープ中は時刻が飛ぶが、プロセスは終了していない）。

## 補足

- `Restart=always` によりプロセスが落ちても自動復帰。`enable` により**再起動後も自動開始**。
- サーバ用途では通常サスペンドしないが、する場合も systemd はレジューム後にサービスを維持する。
