[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorldserverSource,
    [ValidateSet(0, 1)][int]$PreviewEnabled = 1
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path, [string]$Label, [switch]$MustExist)
    $isDrivePath = $Path -match '^[A-Za-z]:\\'
    $isUncPath = $Path -match '^\\\\[^\\]+\\[^\\]+'
    if ([string]::IsNullOrWhiteSpace($Path) -or (-not $isDrivePath -and -not $isUncPath)) {
        throw "$Label must be an absolute path: $Path"
    }
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if ($resolved.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must not target C drive: $resolved"
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $resolved)) {
        throw "$Label does not exist: $resolved"
    }
    return $resolved
}

function Assert-WithinRoot {
    param([string]$Path, [string]$Root, [string]$Label)
    $rootPrefix = $Root.TrimEnd('\') + '\'
    if (-not $Path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is outside serverRoot: $Path"
    }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$profileFile = Resolve-AbsolutePath $ProfilePath 'Profile' -MustExist
$sourceExe = Resolve-AbsolutePath $WorldserverSource 'Worldserver source' -MustExist
$profile = Get-Content -LiteralPath $profileFile -Raw -Encoding UTF8 | ConvertFrom-Json
$serverRoot = Resolve-AbsolutePath $profile.serverRoot 'serverRoot' -MustExist
$targetExe = Resolve-AbsolutePath $profile.worldserverExeTarget 'worldserverExeTarget' -MustExist
$targetConfig = Resolve-AbsolutePath $profile.runtimeModuleConfig 'runtimeModuleConfig' -MustExist
$backupRoot = Resolve-AbsolutePath $profile.backupRoot 'backupRoot'

Assert-WithinRoot $targetExe $serverRoot 'worldserverExeTarget'
Assert-WithinRoot $targetConfig $serverRoot 'runtimeModuleConfig'
if ([System.IO.Path]::GetExtension($sourceExe) -ne '.exe' -or [System.IO.Path]::GetFileName($targetExe) -ne 'worldserver.exe') {
    throw 'Worldserver paths must identify worldserver.exe-compatible PE files.'
}
if (-not $backupRoot.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "backupRoot must be on F drive: $backupRoot"
}

$runningTarget = Get-Process -Name worldserver -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and ([System.IO.Path]::GetFullPath($_.Path)).Equals($targetExe, [System.StringComparison]::OrdinalIgnoreCase)
}
if ($runningTarget) {
    throw "Refusing deployment while target worldserver is running (PID $($runningTarget.Id -join ','))."
}

$deploymentId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backupDir = Join-Path $backupRoot $deploymentId
[System.IO.Directory]::CreateDirectory($backupDir) | Out-Null
$exeBackup = Join-Path $backupDir 'worldserver.exe'
$configBackup = Join-Path $backupDir 'transmog.conf'
Copy-Item -LiteralPath $targetExe -Destination $exeBackup
Copy-Item -LiteralPath $targetConfig -Destination $configBackup

$targetDir = Split-Path -Parent $targetExe
$configDir = Split-Path -Parent $targetConfig
$nonce = [guid]::NewGuid().ToString('N')
$stagedExe = Join-Path $targetDir (".worldserver.$nonce.new")
$stagedConfig = Join-Path $configDir (".transmog.$nonce.new")
$replaceBackupExe = Join-Path $targetDir (".worldserver.$nonce.old")
$replaceBackupConfig = Join-Path $configDir (".transmog.$nonce.old")
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

try {
    Copy-Item -LiteralPath $sourceExe -Destination $stagedExe
    if ((Get-Sha256 $sourceExe) -ne (Get-Sha256 $stagedExe)) {
        throw 'Staged worldserver hash differs from source.'
    }

    $lines = [System.IO.File]::ReadAllLines($targetConfig)
    $kept = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -notmatch '^\s*SoloCollections\.Preview\.Enabled\s*=') {
            $kept.Add($line)
        }
    }
    if ($kept.Count -gt 0 -and $kept[$kept.Count - 1] -ne '') { $kept.Add('') }
    $kept.Add("SoloCollections.Preview.Enabled = $PreviewEnabled")
    [System.IO.File]::WriteAllLines($stagedConfig, $kept, $utf8NoBom)

    [System.IO.File]::Replace($stagedConfig, $targetConfig, $replaceBackupConfig)
    [System.IO.File]::Replace($stagedExe, $targetExe, $replaceBackupExe)
}
catch {
    Copy-Item -LiteralPath $configBackup -Destination $targetConfig -Force
    Copy-Item -LiteralPath $exeBackup -Destination $targetExe -Force
    throw
}
finally {
    if (Test-Path -LiteralPath $stagedExe -PathType Leaf) { Remove-Item -LiteralPath $stagedExe -Force }
    if (Test-Path -LiteralPath $stagedConfig -PathType Leaf) { Remove-Item -LiteralPath $stagedConfig -Force }
    if (Test-Path -LiteralPath $replaceBackupExe -PathType Leaf) { Remove-Item -LiteralPath $replaceBackupExe -Force }
    if (Test-Path -LiteralPath $replaceBackupConfig -PathType Leaf) { Remove-Item -LiteralPath $replaceBackupConfig -Force }
}

$manifest = [ordered]@{
    deploymentId = $deploymentId
    profile = $profileFile
    sourceWorldserver = $sourceExe
    targetWorldserver = $targetExe
    runtimeModuleConfig = $targetConfig
    previewEnabled = $PreviewEnabled
    sourceWorldserverSha256 = Get-Sha256 $sourceExe
    previousWorldserverSha256 = Get-Sha256 $exeBackup
    deployedWorldserverSha256 = Get-Sha256 $targetExe
    previousConfigSha256 = Get-Sha256 $configBackup
    deployedConfigSha256 = Get-Sha256 $targetConfig
}
$manifestPath = Join-Path $backupDir 'deployment-manifest.json'
[System.IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine),
    $utf8NoBom
)

Write-Output "deploymentId=$deploymentId"
Write-Output "backup=$backupDir"
Write-Output "worldserverSha256=$($manifest.deployedWorldserverSha256)"
Write-Output "configSha256=$($manifest.deployedConfigSha256)"
