# SEA サービスバイナリを Windows(x64) 上でネイティブビルドする。
#
# build-cross.sh の Windows 版。macOS を経由せず、Windows 実機だけで
# bundle → blob生成 → node.exe複製 → postject注入 まで完結させる。
# ホストツール(esbuild/postject)も vendor/ の公式node で実行するため、
# システムに node をインストールする必要はない（PATHも汚さない）。
#
# 使い方:
#   powershell -ExecutionPolicy Bypass -File .\build-win.ps1

$ErrorActionPreference = 'Stop'

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$NodeVer = if ($env:NODE_VER) { $env:NODE_VER } else { 'v22.23.2' }
$Fuse    = 'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2'

$NodeDir = Join-Path $Root "vendor\node-$NodeVer-win-x64"
$NodeExe = Join-Path $NodeDir 'node.exe'
$NpxCmd  = Join-Path $NodeDir 'npx.cmd'

if (-not (Test-Path $NodeExe)) {
  Write-Error "公式node が無い: $NodeExe`n先に vendor/ へ node-$NodeVer-win-x64.zip を展開してください。"
}

Set-Location $Root
$env:PATH = "$NodeDir;$env:PATH"
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'dist') | Out-Null

Write-Host '>> [1/4] bundle service (esbuild)'
& $NpxCmd --yes esbuild src/service.js --bundle --platform=node --target=node22 --outfile=dist/service.bundle.js
if ($LASTEXITCODE -ne 0) { Write-Error 'esbuild failed' }

Write-Host '>> [2/4] generate blob'
& $NodeExe --experimental-sea-config sea-config.service.json
if ($LASTEXITCODE -ne 0) { Write-Error 'sea-config failed' }

Write-Host '>> [3/4] copy official node.exe'
$OutDir = Join-Path $Root 'dist\win-x64'
$OutExe = Join-Path $OutDir 'sea-svc.exe'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $NodeExe $OutExe -Force
Set-ItemProperty -Path $OutExe -Name IsReadOnly -Value $false

Write-Host '>> [4/4] inject blob (postject)'
# 注: postject は Windows の Authenticode 署名を壊すため
#     "signature seems corrupted!" と警告するが、実行は可能（pitfalls P5 参照）。
& $NpxCmd --yes postject $OutExe NODE_SEA_BLOB dist/service.blob --sentinel-fuse $Fuse
if ($LASTEXITCODE -ne 0) { Write-Error 'postject failed' }

Write-Host ''
Write-Host 'DONE'
Get-Item $OutExe | Select-Object FullName, @{n='SizeMB';e={[math]::Round($_.Length/1MB,1)}}
