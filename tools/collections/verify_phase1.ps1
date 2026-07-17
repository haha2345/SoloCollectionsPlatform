[CmdletBinding()]
param(
    [string]$AddonSource = '',
    [Parameter(Mandatory = $true)][string]$AddonTarget,
    [string]$ServerLuaSource = '',
    [Parameter(Mandatory = $true)][string]$ServerLuaTarget,
    [string]$ManifestPath = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($AddonSource)) {
    $AddonSource = Join-Path $RepoRoot 'addon\SoloCollections'
}
if ([string]::IsNullOrWhiteSpace($ServerLuaSource)) {
    $ServerLuaSource = Join-Path $RepoRoot 'server\ale\solo_collections.lua'
}
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $RepoRoot '_work\verification\phase1_manifest.json'
}

function Test-FullyQualifiedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^[A-Za-z]:\\') { return $true }
    if ($Path -match '^\\\\[^\\]+\\[^\\]+(?:\\|$)') { return $true }
    return $false
}

function Resolve-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    if (-not (Test-FullyQualifiedPath $Path)) {
        throw "$Label must be a fully qualified drive or UNC path: $Path"
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function Test-PathOverlap {
    param([Parameter(Mandatory = $true)][string]$First, [Parameter(Mandatory = $true)][string]$Second)
    $a = $First.TrimEnd('\', '/')
    $b = $Second.TrimEnd('\', '/')
    if ($a.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $aWithSlash = $a + '\'
    $bWithSlash = $b + '\'
    return $aWithSlash.StartsWith($bWithSlash, [System.StringComparison]::OrdinalIgnoreCase) -or
        $bWithSlash.StartsWith($aWithSlash, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoPathOverlap {
    param([Parameter(Mandatory = $true)][array]$NamedPaths)
    for ($i = 0; $i -lt $NamedPaths.Count; $i++) {
        for ($j = $i + 1; $j -lt $NamedPaths.Count; $j++) {
            if (Test-PathOverlap $NamedPaths[$i].Path $NamedPaths[$j].Path) {
                throw "Dangerous path overlap: $($NamedPaths[$i].Name) and $($NamedPaths[$j].Name)."
            }
        }
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    return [System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
}

function Get-FileMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        Size = [int64]$item.Length
        Sha256 = Get-Sha256Hex $Path
    }
}

$AddonSource = Resolve-AbsolutePath $AddonSource 'AddOn source'
$AddonTarget = Resolve-AbsolutePath $AddonTarget 'AddOn target'
$ServerLuaSource = Resolve-AbsolutePath $ServerLuaSource 'Server Lua source'
$ServerLuaTarget = Resolve-AbsolutePath $ServerLuaTarget 'Server Lua target'
$ManifestPath = Resolve-AbsolutePath $ManifestPath 'Manifest path'

Assert-NoPathOverlap @(
    [pscustomobject]@{ Name = 'AddOn source'; Path = $AddonSource },
    [pscustomobject]@{ Name = 'AddOn target'; Path = $AddonTarget },
    [pscustomobject]@{ Name = 'server Lua source'; Path = $ServerLuaSource },
    [pscustomobject]@{ Name = 'server Lua target'; Path = $ServerLuaTarget },
    [pscustomobject]@{ Name = 'manifest'; Path = $ManifestPath }
)

if ([System.IO.Path]::GetFileName($AddonSource.TrimEnd('\')) -ne 'SoloCollections' -or
    [System.IO.Path]::GetFileName($AddonTarget.TrimEnd('\')) -ne 'SoloCollections') {
    throw 'Verification is restricted to the SoloCollections directory.'
}
if ([System.IO.Path]::GetFileName($ServerLuaSource) -ne 'solo_collections.lua' -or
    [System.IO.Path]::GetFileName($ServerLuaTarget) -ne 'solo_collections.lua') {
    throw 'Verification is restricted to solo_collections.lua.'
}
if (-not (Test-Path -LiteralPath $AddonSource -PathType Container)) {
    throw "Missing AddOn source directory: $AddonSource"
}
if (-not (Test-Path -LiteralPath $ServerLuaSource -PathType Leaf)) {
    throw "Missing server Lua source: $ServerLuaSource"
}

$sourceRootWithSlash = $AddonSource.TrimEnd('\') + '\'
$records = New-Object System.Collections.Generic.List[object]
$targetOnlyRecords = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]
$sourceFiles = Get-ChildItem -LiteralPath $AddonSource -Recurse -File | Sort-Object { $_.FullName.Substring($sourceRootWithSlash.Length) }
$sourceRelativePaths = @{}
foreach ($sourceFile in $sourceFiles) {
    $relativePath = $sourceFile.FullName.Substring($sourceRootWithSlash.Length)
    $sourceRelativePaths[$relativePath.ToLowerInvariant()] = $true
    $livePath = [System.IO.Path]::GetFullPath((Join-Path $AddonTarget $relativePath))
    $sourceMetadata = Get-FileMetadata $sourceFile.FullName
    $liveMetadata = Get-FileMetadata $livePath
    $status = 'match'
    if ($null -eq $liveMetadata) {
        $status = 'missing'
        $failures.Add("missing AddOn file: $relativePath")
    }
    elseif ($sourceMetadata.Size -ne $liveMetadata.Size -or $sourceMetadata.Sha256 -ne $liveMetadata.Sha256) {
        $status = 'mismatch'
        $failures.Add("mismatch AddOn file: $relativePath")
    }
    $records.Add([ordered]@{
        relative_path = $relativePath.Replace('\', '/')
        size = $sourceMetadata.Size
        source_sha256 = $sourceMetadata.Sha256
        live_size = if ($liveMetadata) { $liveMetadata.Size } else { $null }
        live_sha256 = if ($liveMetadata) { $liveMetadata.Sha256 } else { $null }
        status = $status
    })
}

$targetFiles = @()
if (Test-Path -LiteralPath $AddonTarget -PathType Container) {
    $targetRootWithSlash = $AddonTarget.TrimEnd('\') + '\'
    $targetFiles = @(Get-ChildItem -LiteralPath $AddonTarget -Recurse -File | Sort-Object { $_.FullName.Substring($targetRootWithSlash.Length) })
    foreach ($targetFile in $targetFiles) {
        $relativePath = $targetFile.FullName.Substring($targetRootWithSlash.Length)
        if (-not $sourceRelativePaths.ContainsKey($relativePath.ToLowerInvariant())) {
            $liveMetadata = Get-FileMetadata $targetFile.FullName
            $normalizedRelativePath = $relativePath.Replace('\', '/')
            $failures.Add("target-only AddOn file: $normalizedRelativePath")
            $targetOnlyRecords.Add([ordered]@{
                relative_path = $normalizedRelativePath
                live_size = $liveMetadata.Size
                live_sha256 = $liveMetadata.Sha256
                status = 'target_only'
            })
        }
    }
}

$serverSourceMetadata = Get-FileMetadata $ServerLuaSource
$serverLiveMetadata = Get-FileMetadata $ServerLuaTarget
$serverStatus = 'match'
if ($null -eq $serverLiveMetadata) {
    $serverStatus = 'missing'
    $failures.Add('missing server Lua: solo_collections.lua')
}
elseif ($serverSourceMetadata.Size -ne $serverLiveMetadata.Size -or $serverSourceMetadata.Sha256 -ne $serverLiveMetadata.Sha256) {
    $serverStatus = 'mismatch'
    $failures.Add('mismatch server Lua: solo_collections.lua')
}

$manifest = [ordered]@{
    schema_version = 2
    addon_name = 'SoloCollections'
    addon_source = $AddonSource
    addon_target = $AddonTarget
    server_lua = 'solo_collections.lua'
    server_lua_source = $ServerLuaSource
    server_lua_target = $ServerLuaTarget
    addon_files = $records.ToArray()
    addon_target_only_files = $targetOnlyRecords.ToArray()
    server_file = [ordered]@{
        relative_path = 'solo_collections.lua'
        size = $serverSourceMetadata.Size
        source_sha256 = $serverSourceMetadata.Sha256
        live_size = if ($serverLiveMetadata) { $serverLiveMetadata.Size } else { $null }
        live_sha256 = if ($serverLiveMetadata) { $serverLiveMetadata.Sha256 } else { $null }
        status = $serverStatus
    }
    summary = [ordered]@{
        addon_source_file_count = $records.Count
        addon_target_file_count = $targetFiles.Count
        matched = @($records | Where-Object { $_.status -eq 'match' }).Count + $(if ($serverStatus -eq 'match') { 1 } else { 0 })
        missing = @($failures | Where-Object { $_ -like 'missing*' }).Count
        mismatched = @($failures | Where-Object { $_ -like 'mismatch*' }).Count
        target_only = $targetOnlyRecords.Count
    }
}

$manifestParent = Split-Path -Parent $ManifestPath
if (-not (Test-Path -LiteralPath $manifestParent -PathType Container)) {
    New-Item -ItemType Directory -Path $manifestParent -Force | Out-Null
}
$json = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($ManifestPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "MANIFEST $ManifestPath"
Write-Output "SUMMARY source_files=$($manifest.summary.addon_source_file_count) target_files=$($manifest.summary.addon_target_file_count) matched=$($manifest.summary.matched) missing=$($manifest.summary.missing) mismatched=$($manifest.summary.mismatched) target_only=$($manifest.summary.target_only)"
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }
    throw "Phase 1 verification failed with $($failures.Count) parity difference(s)."
}
