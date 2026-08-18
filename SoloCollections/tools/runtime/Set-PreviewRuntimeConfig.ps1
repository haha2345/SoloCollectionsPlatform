[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][ValidateSet(0, 1)][int]$PreviewEnabled
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

$profileFile = Resolve-AbsolutePath $ProfilePath 'Profile' -MustExist
$profile = Get-Content -LiteralPath $profileFile -Raw -Encoding UTF8 | ConvertFrom-Json
$serverRoot = Resolve-AbsolutePath $profile.serverRoot 'serverRoot' -MustExist
$targetConfig = Resolve-AbsolutePath $profile.runtimeModuleConfig 'runtimeModuleConfig' -MustExist
$backupRoot = Resolve-AbsolutePath $profile.backupRoot 'backupRoot'
$rootPrefix = $serverRoot.TrimEnd('\') + '\'
if (-not $targetConfig.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "runtimeModuleConfig is outside serverRoot: $targetConfig"
}
if (-not $backupRoot.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "backupRoot must be on F drive: $backupRoot"
}

$changeId = 'config-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$backupDir = Join-Path $backupRoot $changeId
[System.IO.Directory]::CreateDirectory($backupDir) | Out-Null
$backupConfig = Join-Path $backupDir 'transmog.conf'
Copy-Item -LiteralPath $targetConfig -Destination $backupConfig

$configDir = Split-Path -Parent $targetConfig
$nonce = [guid]::NewGuid().ToString('N')
$staged = Join-Path $configDir (".transmog.$nonce.new")
$replaced = Join-Path $configDir (".transmog.$nonce.old")
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
try {
    $kept = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($targetConfig)) {
        if ($line -notmatch '^\s*SoloCollections\.Preview\.Enabled\s*=') { $kept.Add($line) }
    }
    if ($kept.Count -gt 0 -and $kept[$kept.Count - 1] -ne '') { $kept.Add('') }
    $kept.Add("SoloCollections.Preview.Enabled = $PreviewEnabled")
    [System.IO.File]::WriteAllLines($staged, $kept, $utf8NoBom)
    [System.IO.File]::Replace($staged, $targetConfig, $replaced)
}
catch {
    Copy-Item -LiteralPath $backupConfig -Destination $targetConfig -Force
    throw
}
finally {
    if (Test-Path -LiteralPath $staged -PathType Leaf) { Remove-Item -LiteralPath $staged -Force }
    if (Test-Path -LiteralPath $replaced -PathType Leaf) { Remove-Item -LiteralPath $replaced -Force }
}

$hash = (Get-FileHash -LiteralPath $targetConfig -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "changeId=$changeId"
Write-Output "backup=$backupDir"
Write-Output "previewEnabled=$PreviewEnabled"
Write-Output "configSha256=$hash"
