[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot,
    [Parameter(Mandatory)][string]$Profile,
    [switch]$StopServer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'RoundTwoRelease.Common.ps1')

$bundle = Resolve-RoundTwoPath $BundleRoot
$profilePath = Resolve-RoundTwoPath $Profile
$deployment = Read-RoundTwoJson $profilePath
Assert-RoundTwoProfile $deployment
& (Join-Path $PSScriptRoot 'Test-RoundTwoBundle.ps1') -BundleRoot $bundle
$release = Read-RoundTwoJson (Join-Path $bundle 'release-manifest.json')
$backupDir = Join-Path $bundle 'backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backupManifestPath = Join-Path $backupDir 'backup-manifest.json'
if (Test-Path -LiteralPath $backupManifestPath) { throw "Bundle has already been installed: $backupManifestPath" }

$operations = New-Object System.Collections.Generic.List[object]
function Add-Operation([string]$Source, [string]$Target, [string]$Kind) {
    $sourcePath = Resolve-RoundTwoPath $Source
    $targetPath = Resolve-RoundTwoPath -Path $Target -AllowMissing
    $operations.Add([pscustomobject]@{ Source=$sourcePath; Target=$targetPath; Kind=$Kind })
}

$addonBundle = Join-Path $bundle 'addon\SoloCollections'
foreach ($file in Get-ChildItem -LiteralPath $addonBundle -Recurse -File) {
    $relative = $file.FullName.Substring($addonBundle.Length + 1)
    Add-Operation $file.FullName (Join-Path ([string]$deployment.addonRoot) $relative) 'addon'
}
Add-Operation (Join-Path $bundle 'server\worldserver.exe') ([string]$deployment.worldserverExeTarget) 'worldserver'
Add-Operation (Join-Path $bundle 'server\config\transmog.conf.dist') ([string]$deployment.runtimeModuleConfig) 'config'

$dependencyTargets = @{}
foreach ($entry in @($deployment.worldserverDependencyTargets)) { $dependencyTargets[[string]$entry.fileName.ToLowerInvariant()] = [string]$entry.target }
foreach ($dependency in @($release.dependencies | Where-Object { $_.classification -eq 'BUNDLED_NON_SYSTEM' })) {
    $key = ([string]$dependency.fileName).ToLowerInvariant()
    if (-not $dependencyTargets.ContainsKey($key)) { throw "Profile has no target for bundled dependency: $key" }
    Add-Operation (Join-Path $bundle ('server\runtime-dependencies\' + [string]$dependency.fileName)) $dependencyTargets[$key] 'dependency'
}
if ($release.capabilities.soloCam.status -eq 'VERIFIED') {
    Add-Operation (Join-Path $bundle 'client\SoloCam.dll') ([string]$deployment.soloCamDllTarget) 'solocam'
}
$assetTargets = @{}
foreach ($entry in @($deployment.assetPatchTargets)) { $assetTargets[[string]$entry.fileName.ToLowerInvariant()] = [string]$entry.target }
foreach ($asset in @($release.capabilities.assetPatches | Where-Object { $_.status -eq 'VERIFIED' })) {
    $key = ([string]$asset.fileName).ToLowerInvariant()
    if (-not $assetTargets.ContainsKey($key)) { throw "Profile has no target for asset patch: $key" }
    Add-Operation (Join-Path $bundle ('client\assets\' + [string]$asset.fileName)) $assetTargets[$key] 'asset'
}

if ($StopServer) { Invoke-RoundTwoServerControl -Profile $deployment -Action Stop }
$records = New-Object System.Collections.Generic.List[object]
try {
    $index = 0
    foreach ($operation in $operations) {
        $index++
        $parent = Split-Path -Parent $operation.Target
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $existed = Test-Path -LiteralPath $operation.Target -PathType Leaf
        $backupRelative = ''
        $originalSha = ''
        if ($existed) {
            $backupRelative = ('files\{0:D5}.bak' -f $index)
            $backupPath = Join-Path $backupDir $backupRelative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
            Copy-Item -LiteralPath $operation.Target -Destination $backupPath
            $originalSha = Get-RoundTwoSha256 $backupPath
        }
        Copy-Item -LiteralPath $operation.Source -Destination $operation.Target -Force
        $installedSha = Get-RoundTwoSha256 $operation.Target
        if ($installedSha -ne (Get-RoundTwoSha256 $operation.Source)) { throw "Post-copy hash mismatch: $($operation.Target)" }
        $records.Add([ordered]@{
            order=$index; kind=$operation.Kind; target=$operation.Target; existed=$existed;
            backupRelativePath=$backupRelative; originalSha256=$originalSha; installedSha256=$installedSha
        })
    }
    $backupManifest = [ordered]@{
        schemaVersion=1; bundleId=[string]$release.bundleId; installedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
        profileSha256=Get-RoundTwoSha256 $profilePath; entries=$records
    }
    Write-RoundTwoJson $backupManifest $backupManifestPath
}
catch {
    foreach ($record in @($records | Sort-Object order -Descending)) {
        if ($record.existed) {
            Copy-Item -LiteralPath (Join-Path $backupDir $record.backupRelativePath) -Destination $record.target -Force
        }
        elseif (Test-Path -LiteralPath $record.target -PathType Leaf) {
            Remove-Item -LiteralPath $record.target -Force
        }
    }
    throw
}
if ($StopServer) { Invoke-RoundTwoServerControl -Profile $deployment -Action Start }
Write-Host "installed_bundle=$($release.bundleId)"
Write-Host "backup_manifest=$backupManifestPath"
Write-Host "installed_file_count=$($records.Count)"
