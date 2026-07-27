[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$AddonSource,
    [Parameter(Mandatory = $true)][string]$SoloCamSource,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{64}$')][string]$CameraProfileHash
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-NonCPath {
    param([string]$Path, [string]$Label, [bool]$MustExist = $true)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label must be an absolute path: $Path" }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must not use C: $full"
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $full)) { throw "$Label does not exist: $full" }
    return $full
}

function Assert-UnderRoot {
    param([string]$Path, [string]$Root, [string]$Label)
    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is outside the approved root: $full"
    }
    return $full
}

function Get-TreeHash {
    param([string]$Root)
    $entries = foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
        "$relative $((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant())"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes((($entries -join "`n") + "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Assert-X86Pe {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "SoloCam source is not a PE file: $Path"
    }
    $offset = [BitConverter]::ToInt32($bytes, 0x3C)
    if (($offset -lt 0) -or (($offset + 6) -gt $bytes.Length) -or $bytes[$offset] -ne 0x50 -or $bytes[$offset + 1] -ne 0x45) {
        throw "SoloCam source has an invalid PE header: $Path"
    }
    if ([BitConverter]::ToUInt16($bytes, $offset + 4) -ne 0x014c) {
        throw "SoloCam source is not x86: $Path"
    }
}

$client = Resolve-NonCPath $ClientRoot 'ClientRoot'
$sourceAddon = Resolve-NonCPath $AddonSource 'AddonSource'
$sourceDll = Resolve-NonCPath $SoloCamSource 'SoloCamSource'
$evidence = Resolve-NonCPath $EvidenceRoot 'EvidenceRoot' $false
if (-not (Test-Path -LiteralPath $sourceAddon -PathType Container)) { throw "AddonSource is not a directory: $sourceAddon" }
if (-not (Test-Path -LiteralPath (Join-Path $sourceAddon 'SoloCollections.toc') -PathType Leaf)) {
    throw "AddonSource does not contain SoloCollections.toc: $sourceAddon"
}
if (-not (Test-Path -LiteralPath $sourceDll -PathType Leaf)) { throw "SoloCamSource is not a file: $sourceDll" }
Assert-X86Pe $sourceDll

$targetAddon = Assert-UnderRoot (Join-Path $client 'Interface\AddOns\SoloCollections') $client 'AddOn target'
$targetDll = Assert-UnderRoot (Join-Path $client 'SoloCam.dll') $client 'SoloCam target'
$targetAddonParent = Split-Path -Parent $targetAddon
if (-not (Test-Path -LiteralPath $targetAddonParent -PathType Container)) {
    throw "Client AddOns directory is missing: $targetAddonParent"
}
$running = Get-Process -Name 'Wow', 'Wow-SoloCam-PoC', 'Wow-CQM-SoloCam' -ErrorAction SilentlyContinue
if ($running) { throw "Stop the client before deployment (PID(s): $($running.Id -join ', '))." }

[IO.Directory]::CreateDirectory($evidence) | Out-Null
$runId = 'stage5-camera-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runRoot = Join-Path $evidence $runId
$backupRoot = Join-Path $runRoot 'backup'
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$backupAddon = Join-Path $backupRoot 'SoloCollections'
$backupDll = Join-Path $backupRoot 'SoloCam.dll'
$hadAddon = Test-Path -LiteralPath $targetAddon -PathType Container
$hadDll = Test-Path -LiteralPath $targetDll -PathType Leaf
$before = [ordered]@{
    addonTreeHash = if ($hadAddon) { Get-TreeHash $targetAddon } else { $null }
    soloCamSha256 = if ($hadDll) { (Get-FileHash -Algorithm SHA256 -LiteralPath $targetDll).Hash.ToLowerInvariant() } else { $null }
}
if ($hadDll) {
    Copy-Item -LiteralPath $targetDll -Destination $backupDll
}

$addonMoved = $false
$targetDllWasTouched = $false
try {
    if ($hadAddon) {
        Move-Item -LiteralPath $targetAddon -Destination $backupAddon
        $addonMoved = $true
    }
    Copy-Item -LiteralPath $sourceAddon -Destination $targetAddon -Recurse
    $targetDllWasTouched = $true
    Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force
} catch {
    $failedAddon = Join-Path $backupRoot 'failed-new-SoloCollections'
    if (Test-Path -LiteralPath $targetAddon -PathType Container) {
        Move-Item -LiteralPath $targetAddon -Destination $failedAddon
    }
    if ($addonMoved -and (Test-Path -LiteralPath $backupAddon -PathType Container)) {
        Move-Item -LiteralPath $backupAddon -Destination $targetAddon
    }
    if ($hadDll -and $targetDllWasTouched -and (Test-Path -LiteralPath $backupDll -PathType Leaf)) {
        Copy-Item -LiteralPath $backupDll -Destination $targetDll -Force
    } elseif (-not $hadDll -and $targetDllWasTouched -and (Test-Path -LiteralPath $targetDll -PathType Leaf)) {
        Move-Item -LiteralPath $targetDll -Destination (Join-Path $backupRoot 'failed-new-SoloCam.dll')
    }
    throw
}

$after = [ordered]@{
    addonTreeHash = Get-TreeHash $targetAddon
    soloCamSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetDll).Hash.ToLowerInvariant()
}
$manifest = [ordered]@{
    schemaVersion = 1
    runId = $runId
    completedUtc = [DateTime]::UtcNow.ToString('o')
    clientRoot = $client
    addonSource = $sourceAddon
    soloCamSource = $sourceDll
    cameraProfileHash = $CameraProfileHash
    targets = [ordered]@{ addon = $targetAddon; soloCam = $targetDll }
    backups = [ordered]@{ addon = if ($hadAddon) { $backupAddon } else { $null }; soloCam = if ($hadDll) { $backupDll } else { $null } }
    before = $before
    after = $after
}
[IO.File]::WriteAllText(
    (Join-Path $runRoot 'deployment.json'),
    (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
)
$manifest | ConvertTo-Json -Depth 8
