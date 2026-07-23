[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StageRoot,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$BundleId,
    [Parameter(Mandatory = $true)][string]$StormLib
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()

function Resolve-FPath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "Wildcard paths are forbidden: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::GetPathRoot($full) -ne 'F:\') {
        throw "All weapon bundle paths must be on F:, got: $full"
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Required path is missing: $full"
    }
    return $full
}

function Assert-Within {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $fullPath = Resolve-FPath $Path -AllowMissing
    $fullRoot = Resolve-FPath $Root -AllowMissing
    $prefix = $fullRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes declared root: path=$fullPath root=$fullRoot"
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $digest = [Security.Cryptography.SHA256]::Create().ComputeHash($stream)
        return ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    }
    finally { $stream.Dispose() }
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algorithm.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally { $algorithm.Dispose() }
}

function Convert-StageRelativePath {
    param([Parameter(Mandatory = $true)][string]$Relative)
    $value = $Relative.Replace('/', '\').TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains(':') -or $value.Split('\') -contains '..') {
        throw "Unsafe stage-relative path: $Relative"
    }
    return $value
}

$stage = Resolve-FPath $StageRoot
$output = Resolve-FPath $OutputRoot -AllowMissing
$storm = Resolve-FPath $StormLib
if ($BundleId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$') {
    throw "Invalid bundle ID: $BundleId"
}
$stageManifestPath = Join-Path $stage 'weapon-bundle-manifest.json'
if (-not (Test-Path -LiteralPath $stageManifestPath -PathType Leaf)) {
    throw "Stage manifest is missing: $stageManifestPath"
}
$stageManifest = Get-Content -LiteralPath $stageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($stageManifest.kind -ne 'SoloCollectionsWeaponBundleStage' -or [string]$stageManifest.bundleId -ne $BundleId) {
    throw 'Stage manifest identity mismatch'
}
$bundleRoot = Join-Path $output $BundleId
if (Test-Path -LiteralPath $bundleRoot) {
    throw "Bundle output already exists; ownership collision is forbidden: $bundleRoot"
}

New-Item -ItemType Directory -Force -Path $bundleRoot, (Join-Path $bundleRoot 'lists'), (Join-Path $bundleRoot 'verify'), (Join-Path $bundleRoot 'tmp') | Out-Null
Assert-Within $bundleRoot $output
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$env:TEMP = Join-Path $bundleRoot 'tmp'
$env:TMP = $env:TEMP

try {
    $rows = @($stageManifest.files)
    if ($rows.Count -eq 0) { throw 'Stage manifest has no file rows' }
    $seen = @{}
    foreach ($row in $rows) {
        $relative = Convert-StageRelativePath ([string]$row.relativePath)
        $key = $relative.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate stage manifest path: $relative" }
        $seen[$key] = $true
        $source = Join-Path $stage $relative
        Assert-Within $source $stage
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Stage file is missing: $relative" }
        if ((Get-Item -LiteralPath $source).Length -ne [long]$row.size -or (Get-Sha256 $source) -ne [string]$row.sha256) {
            throw "Stage file hash mismatch: $relative"
        }
    }
    $assetRows = @($rows | Where-Object { -not ([string]$_.relativePath).StartsWith('DBFilesClient/', [StringComparison]::OrdinalIgnoreCase) })
    $localeRows = @($rows | Where-Object { ([string]$_.relativePath).StartsWith('DBFilesClient/', [StringComparison]::OrdinalIgnoreCase) })
    if ($assetRows.Count -eq 0 -or $localeRows.Count -ne 2) {
        throw "Unexpected aggregate input split: assets=$($assetRows.Count) locale=$($localeRows.Count)"
    }
    $assetList = Join-Path $bundleRoot 'lists\assets.lst'
    $localeList = Join-Path $bundleRoot 'lists\locale.lst'
    [IO.File]::WriteAllLines($assetList, [string[]]@($assetRows | ForEach-Object { Convert-StageRelativePath ([string]$_.relativePath) }), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllLines($localeList, [string[]]@($localeRows | ForEach-Object { Convert-StageRelativePath ([string]$_.relativePath) }), [Text.UTF8Encoding]::new($false))

    $owner = [ordered]@{
        schemaVersion = 1
        owner = 'SoloCollectionsWeaponShadow'
        bundleId = $BundleId
        stageManifestSha256 = Get-Sha256 $stageManifestPath
        assetArchiveFileName = "SoloCollections-Weapon-$BundleId-assets.MPQ"
        localeArchiveFileName = "SoloCollections-Weapon-$BundleId-locale.MPQ"
    }
    [IO.File]::WriteAllText((Join-Path $bundleRoot 'ownership.json'), ($owner | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))

    $stormTool = Join-Path $PSScriptRoot 'StormMpq.ps1'
    $batchExtractor = Join-Path $PSScriptRoot 'Extract-StormMpqBatch.ps1'
    $assetArchive = Join-Path $bundleRoot $owner.assetArchiveFileName
    $localeArchive = Join-Path $bundleRoot $owner.localeArchiveFileName
    & $stormTool -Command create -Archive $assetArchive -MaxFiles ($assetRows.Count + 1) -StormLib $storm
    & $stormTool -Command add -Archive $assetArchive -SourceRoot $stage -IncludeListFile $assetList -StormLib $storm
    & $stormTool -Command compact -Archive $assetArchive -StormLib $storm
    & $stormTool -Command create -Archive $localeArchive -MaxFiles ($localeRows.Count + 1) -StormLib $storm
    & $stormTool -Command add -Archive $localeArchive -SourceRoot $stage -IncludeListFile $localeList -StormLib $storm
    & $stormTool -Command compact -Archive $localeArchive -StormLib $storm

    $verification = New-Object System.Collections.Generic.List[object]
    foreach ($pair in @(
        [pscustomobject]@{ Label='assets'; Archive=$assetArchive; List=$assetList; Rows=$assetRows },
        [pscustomobject]@{ Label='locale'; Archive=$localeArchive; List=$localeList; Rows=$localeRows }
    )) {
        $verifyRoot = Join-Path (Join-Path $bundleRoot 'verify') $pair.Label
        & $batchExtractor -Archive $pair.Archive -ListFile $pair.List -OutputRoot $verifyRoot -StormLib $storm
        foreach ($row in $pair.Rows) {
            $relative = Convert-StageRelativePath ([string]$row.relativePath)
            $source = Join-Path $stage $relative
            $verified = Join-Path $verifyRoot $relative
            Assert-Within $verified $verifyRoot
            if (-not (Test-Path -LiteralPath $verified -PathType Leaf)) { throw "MPQ reopen/extract failed: $relative" }
            $verifiedHash = Get-Sha256 $verified
            if ($verifiedHash -ne [string]$row.sha256) { throw "MPQ reopen hash mismatch: $relative" }
            $verification.Add([ordered]@{ archive=$pair.Label; relativePath=$relative.Replace('\','/'); sha256=$verifiedHash })
        }
    }
    $archiveRecords = New-Object System.Collections.Generic.List[object]
    $archiveRecords.Add([ordered]@{
        role='assets'; fileName=[IO.Path]::GetFileName($assetArchive); size=(Get-Item -LiteralPath $assetArchive).Length; sha256=Get-Sha256 $assetArchive; entries=$assetRows.Count
    }) | Out-Null
    $archiveRecords.Add([ordered]@{
        role='locale'; fileName=[IO.Path]::GetFileName($localeArchive); size=(Get-Item -LiteralPath $localeArchive).Length; sha256=Get-Sha256 $localeArchive; entries=$localeRows.Count
    }) | Out-Null
    $pack = [ordered]@{
        schemaVersion = 1
        kind = 'SoloCollectionsWeaponShadowMpqBundle'
        bundleId = $BundleId
        assetPackVersion = [string]$stageManifest.assetPackVersion
        stageManifestSha256 = Get-Sha256 $stageManifestPath
        stageBundleManifestHash = [string]$stageManifest.bundleManifestHash
        archives = $archiveRecords.ToArray()
        verification = $verification.ToArray()
        deployment = [ordered]@{
            status='NOT_DEPLOYED'
            collisionPolicy='NEW_OR_OWNED_TARGET_ONLY'
            restorePolicy='EXPLICIT_BACKUP_MANIFEST_REQUIRED'
        }
    }
    $pack.bundlePackHash = Get-TextSha256 (($pack | ConvertTo-Json -Depth 20 -Compress) + "`n")
    [IO.File]::WriteAllText((Join-Path $bundleRoot 'weapon-mpq-manifest.json'), ($pack | ConvertTo-Json -Depth 30) + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "bundle_root=$bundleRoot"
    Write-Host "asset_archive=$assetArchive"
    Write-Host "locale_archive=$localeArchive"
    Write-Host "verified_entry_count=$($verification.Count)"
    Write-Host "bundle_pack_hash=$($pack.bundlePackHash)"
}
finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
