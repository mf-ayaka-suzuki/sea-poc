'use strict';

// 最小構成のSEA PoC。
// アプリ独自ロジックはほぼ無し。目的は「npmパッケージがバイナリに封入され動く」ことの確認。
const _ = require('lodash');
const dayjs = require('dayjs');

// SEA実行時かどうか（node:sea は Node 20+ で利用可能）
let insideSea = false;
try {
  insideSea = require('node:sea').isSea();
} catch (_e) {
  insideSea = false;
}

const chunked = _.chunk(['a', 'b', 'c', 'd', 'e'], 2);
const now = dayjs().format('YYYY-MM-DD HH:mm:ss');

console.log('=== Node.js SEA PoC ===');
console.log('running inside SEA :', insideSea);
console.log('node version       :', process.version);
console.log('lodash _.chunk     :', JSON.stringify(chunked));
console.log('dayjs now          :', now);
console.log('lodash _.capitalize:', _.capitalize('hello from bundled npm package'));
