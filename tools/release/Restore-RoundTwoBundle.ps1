[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BackupManifest,
    [Parameter(Mandatory)][string]$Profile,
    [switch]$StopServer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'RoundTwoRelease.Common.ps1')

$manifestPath = Resolve-RoundTwoPath $BackupManifest
$profilePath = Resolve-RoundTwoPath $Profile
$deployment = Read-RoundTwoJson $profilePath
Assert-RoundTwoProfile $deployment
$manifest = Read-RoundTwoJson $manifestPath
$backupRoot = Split-Path -Parent $manifestPath
if ($manifest.schemaVersion -ne 1) { throw "Unsupported backup manifest" }
if ((Get-RoundTwoSha256 $profilePath) -ne [string]$manifest.profileSha256) { throw "Deployment profile changed since installation" }
foreach ($entry in $manifest.entries) {
    $target = Resolve-RoundTwoPath -Path ([string]$entry.target) -AllowMissing
    if ($entry.existed) {
        $backup = Join-Path $backupRoot ([string]$entry.backupRelativePath)
        Assert-RoundTwoWithin -Path $backup -Root $backupRoot
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-RoundTwoSha256 $backup) -ne [string]$entry.originalSha256) { throw "Backup file hash mismatch: $backup" }
    }
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        if ((Get-RoundTwoSha256 $target) -ne [string]$entry.installedSha256) { throw "Installed target changed after deployment: $target" }
    }
    elseif ($entry.existed) { throw "Installed target disappeared: $target" }
}
if ($StopServer) { Invoke-RoundTwoServerControl -Profile $deployment -Action Stop }
foreach ($entry in @($manifest.entries | Sort-Object order -Descending)) {
    $target = [string]$entry.target
    if ($entry.existed) {
        Copy-Item -LiteralPath (Join-Path $backupRoot ([string]$entry.backupRelativePath)) -Destination $target -Force
        if ((Get-RoundTwoSha256 $target) -ne [string]$entry.originalSha256) { throw "Restored target hash mismatch: $target" }
    }
    elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}
if ($StopServer) { Invoke-RoundTwoServerControl -Profile $deployment -Action Start }
Write-Host "restored_bundle=$($manifest.bundleId)"
Write-Host "restored_file_count=$(@($manifest.entries).Count)"
Write-Host "required_smoke_matrix=PREVIEW,281,24,4,8,status"
