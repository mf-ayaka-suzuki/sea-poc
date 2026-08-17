'use strict';

// 超シンプルな常駐サービス（ハートビート）。
// 目的: 「サービスとして起動し、動き続ける」ことをログで確認できるようにする。
//   - 一定間隔でタイムスタンプ付きの1行をログファイルに追記し続ける
//   - SIGTERM/SIGINT を受けたら後片付けして終了（サービス停止に対応）
//   - 再起動をまたいでも、同じログファイルに追記され続けるので継続性を目視できる
//
// 封入したnpmパッケージ(lodash/dayjs)も併せて使い、SEA内で動くことも示す。

const fs = require('fs');
const path = require('path');
const os = require('os');
const _ = require('lodash');
const dayjs = require('dayjs');

let insideSea = false;
try {
  insideSea = require('node:sea').isSea();
} catch (_e) {
  insideSea = false;
}

// 設定は環境変数で上書き可能（サービス定義から渡す）。
const logPath = process.env.SEA_SVC_LOG || path.join(process.cwd(), 'sea-svc.log');
const intervalMs = Number(process.env.SEA_SVC_INTERVAL_MS || 5000);
// テスト用: 指定回数のハートビート後に自動終了（0/未設定なら無限）。
const maxBeats = Number(process.env.SEA_SVC_MAX || 0);

function stamp() {
  return dayjs().format('YYYY-MM-DD HH:mm:ss');
}

function write(line) {
  const msg = `${stamp()} [pid ${process.pid}] ${line}\n`;
  try {
    fs.appendFileSync(logPath, msg);
  } catch (_e) {
    // ログ書き込みに失敗しても標準出力には残す
  }
  process.stdout.write(msg);
}

write(
  _.trim(
    `START sea=${insideSea} node=${process.version} ` +
      `platform=${process.platform}/${process.arch} host=${os.hostname()} ` +
      `log=${logPath} interval=${intervalMs}ms`
  )
);

let beats = 0;
const timer = setInterval(() => {
  beats += 1;
  write(`heartbeat #${beats} uptime=${Math.round(process.uptime())}s`);
  if (maxBeats > 0 && beats >= maxBeats) {
    write(`DONE reached max ${maxBeats} beats`);
    clearInterval(timer);
    process.exit(0);
  }
}, intervalMs);

function shutdown(sig) {
  write(`STOP (${sig}) after ${beats} beats`);
  clearInterval(timer);
  process.exit(0);
}

['SIGTERM', 'SIGINT', 'SIGHUP'].forEach((s) => process.on(s, () => shutdown(s)));
