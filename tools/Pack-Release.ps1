#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = '0.3.2',
    [string]$ClientRoot = 'D:\Games\wow335\World of Warcraft11'
)

$ErrorActionPreference = 'Stop'
$Platform = Split-Path -Parent $PSScriptRoot
$OutRoot = Join-Path $Platform "dist\v$Version"
if (Test-Path -LiteralPath $OutRoot) {
    Remove-Item -LiteralPath $OutRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$InstallDoc = Join-Path $Platform 'docs\RELEASE.zh-CN.md'

function Compress-Folder([string]$Source, [string]$Zip) {
    if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
    Compress-Archive -Path (Join-Path $Source '*') -DestinationPath $Zip -CompressionLevel Optimal
}

function New-Stage([string]$Name) {
    $stage = Join-Path $OutRoot ("_stage-" + $Name)
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    return $stage
}

$addonSrc = Join-Path $Platform 'SoloCollections\addon\SoloCollections'
$addonStage = New-Stage 'addon'
$addonDest = Join-Path $addonStage 'SoloCollections'
New-Item -ItemType Directory -Force -Path $addonDest | Out-Null
& robocopy $addonSrc $addonDest /E /NFL /NDL /NJH /NJS /NC /NS /XD .git /XF *.ttf *.ttc | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy addon failed: $LASTEXITCODE" }
Copy-Item $InstallDoc (Join-Path $addonStage 'INSTALL.zh-CN.md')
Compress-Folder $addonStage (Join-Path $OutRoot "SoloCollections-v$Version-addon.zip")

$sqlSrc = Join-Path $Platform 'mod-solo-collections\data\sql'
$sqlStage = New-Stage 'sql'
Copy-Item $sqlSrc (Join-Path $sqlStage 'sql') -Recurse
Copy-Item $InstallDoc (Join-Path $sqlStage 'INSTALL.zh-CN.md')
Compress-Folder $sqlStage (Join-Path $OutRoot "SoloCollections-v$Version-sql.zip")

$modSrc = Join-Path $Platform 'mod-solo-collections'
$modStage = New-Stage 'module'
$modDest = Join-Path $modStage 'mod-solo-collections'
New-Item -ItemType Directory -Force -Path $modDest | Out-Null
& robocopy $modSrc $modDest /E /NFL /NDL /NJH /NJS /NC /NS /XD .git build build-* .vs /XF SoloCollectionsBuildInfo.inc | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy module failed: $LASTEXITCODE" }
Copy-Item $InstallDoc (Join-Path $modStage 'INSTALL.zh-CN.md')
Compress-Folder $modStage (Join-Path $OutRoot "SoloCollections-v$Version-module-source.zip")

$mpqStage = New-Stage 'mpq'
$dataStage = Join-Path $mpqStage 'Data'
$zhStage = Join-Path $dataStage 'zhCN'
New-Item -ItemType Directory -Force -Path $zhStage | Out-Null
$patchW = Join-Path $ClientRoot 'Data\Patch-W.MPQ'
$patchZh = Join-Path $ClientRoot 'Data\zhCN\patch-zhCN-6.MPQ'
if (-not (Test-Path -LiteralPath $patchW)) { throw "missing Patch-W.MPQ" }
if (-not (Test-Path -LiteralPath $patchZh)) { throw "missing patch-zhCN-6.MPQ" }
Copy-Item -LiteralPath $patchW -Destination (Join-Path $dataStage 'Patch-W.MPQ')
Copy-Item -LiteralPath $patchZh -Destination (Join-Path $zhStage 'patch-zhCN-6.MPQ')
Copy-Item $InstallDoc (Join-Path $mpqStage 'INSTALL.zh-CN.md')
Compress-Folder $mpqStage (Join-Path $OutRoot "SoloCollections-v$Version-mpq.zip")

$dll = Join-Path $ClientRoot 'SoloCam.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw "missing SoloCam.dll" }
$dllStage = New-Stage 'solocam'
Copy-Item -LiteralPath $dll -Destination (Join-Path $dllStage 'SoloCam.dll')
Copy-Item (Join-Path $Platform 'SoloCollections\client-extension\SoloCam\README.md') (Join-Path $dllStage 'README.md')
Copy-Item $InstallDoc (Join-Path $dllStage 'INSTALL.zh-CN.md')
Compress-Folder $dllStage (Join-Path $OutRoot "SoloCollections-v$Version-solocam.zip")

$rtStage = New-Stage 'runtime'
New-Item -ItemType Directory -Force -Path (Join-Path $rtStage 'Interface\AddOns'), (Join-Path $rtStage 'Data\zhCN') | Out-Null
Copy-Item $addonDest (Join-Path $rtStage 'Interface\AddOns\SoloCollections') -Recurse
Copy-Item (Join-Path $dataStage 'Patch-W.MPQ') (Join-Path $rtStage 'Data\Patch-W.MPQ')
Copy-Item (Join-Path $zhStage 'patch-zhCN-6.MPQ') (Join-Path $rtStage 'Data\zhCN\patch-zhCN-6.MPQ')
Copy-Item -LiteralPath $dll -Destination (Join-Path $rtStage 'SoloCam.dll')
Copy-Item $InstallDoc (Join-Path $rtStage 'INSTALL.zh-CN.md')
Compress-Folder $rtStage (Join-Path $OutRoot "SoloCollections-v$Version-client-runtime.zip")

Get-ChildItem -LiteralPath $OutRoot -Directory -Filter '_stage-*' | Remove-Item -Recurse -Force

$sums = foreach ($file in Get-ChildItem -LiteralPath $OutRoot -File | Sort-Object Name) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
    "{0}  {1}" -f $hash, $file.Name
}
$sums -join "`n" | Set-Content -LiteralPath (Join-Path $OutRoot 'SHA256SUMS.txt') -Encoding ASCII
Copy-Item $InstallDoc (Join-Path $OutRoot 'README.zh-CN.md')

Write-Host "packed $OutRoot"
Get-ChildItem -LiteralPath $OutRoot | ForEach-Object { "{0,12}  {1}" -f $_.Length, $_.Name }
