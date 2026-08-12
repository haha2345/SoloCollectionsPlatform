[CmdletBinding()]
param(
    [string] $SourceRoot = (Join-Path $PSScriptRoot '..\Interface\AddOns'),
    [string] $LockFile = (Join-Path $PSScriptRoot '..\upstream\suite-lock.json'),
    [string] $EzCollectionsReferenceFile = (Join-Path $PSScriptRoot '..\upstream\ezCollections-reference.json'),
    [switch] $VerifyLock,
    [switch] $AllowGeneratedEzCollectionsUI
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$generatedEzUI = 'SoloCollections_EzUI'
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json
$expected = @($lock.components | ForEach-Object { $_.addonRoot })
if (-not $expected -or $expected.Count -eq 0) { throw "Suite lock has no component addonRoot entries." }

function Get-TreeHash([string] $Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $files = Get-ChildItem -LiteralPath $resolved -File -Recurse -Force |
            Sort-Object { [IO.Path]::GetRelativePath($resolved, $_.FullName).Replace('\', '/') }
        foreach ($file in $files) {
            $relative = [IO.Path]::GetRelativePath($resolved, $file.FullName).Replace('\', '/')
            $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $bytes = [Text.Encoding]::UTF8.GetBytes("$relative`0$fileHash`n")
            [void] $sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
        }
        [void] $sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [BitConverter]::ToString($sha.Hash).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$actual = @(Get-ChildItem -LiteralPath $root -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$expectedRoots = @($expected)
if ($AllowGeneratedEzCollectionsUI) { $expectedRoots += $generatedEzUI }
$expectedSorted = @($expectedRoots | Sort-Object)
if (($actual -join "`n") -ne ($expectedSorted -join "`n")) {
    $shape = if ($AllowGeneratedEzCollectionsUI) { 'the locked AddOn roots plus generated SoloCollections_EzUI' } else { 'exactly the locked AddOn roots' }
    throw "Expected ${shape}: $($expectedRoots -join ', '); found: $($actual -join ', ')"
}

function Get-TreeHashFromFiles {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [System.IO.FileInfo[]] $Files
    )
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $orderedFiles = @($Files | Sort-Object {
            [IO.Path]::GetRelativePath($resolved, $_.FullName).Replace('\', '/')
        })
        foreach ($file in $orderedFiles) {
            $relative = [IO.Path]::GetRelativePath($resolved, $file.FullName).Replace('\', '/')
            $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $bytes = [Text.Encoding]::UTF8.GetBytes("$relative`0$fileHash`n")
            [void] $sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
        }
        [void] $sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [BitConverter]::ToString($sha.Hash).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$lockForVerification = if ($VerifyLock) { $lock } else { $null }
$rows = foreach ($name in $expected) {
    $addon = Join-Path $root $name
    $toc = @(Get-ChildItem -LiteralPath $addon -Filter '*.toc' -File)
    if ($toc.Count -ne 1) { throw "$name must contain exactly one root-level .toc; found $($toc.Count)" }
    $nested = Join-Path $addon $name
    if (Test-Path -LiteralPath $nested -PathType Container) { throw "$name is nested one directory too deep: $nested" }
    $hash = Get-TreeHash $addon
    if ($VerifyLock) {
        $entry = @($lockForVerification.components | Where-Object addonRoot -eq $name)
        if ($entry.Count -ne 1) { throw "Lock must contain exactly one entry for $name" }
        if ($entry[0].directoryHash -ne $hash) { throw "Directory hash mismatch for $name. expected=$($entry[0].directoryHash) actual=$hash" }
    }
    [pscustomobject]@{ addon = $name; toc = $toc[0].Name; directoryHash = $hash }
}

if ($AllowGeneratedEzCollectionsUI) {
    $addon = Join-Path $root $generatedEzUI
    $toc = @(Get-ChildItem -LiteralPath $addon -Filter '*.toc' -File)
    if ($toc.Count -ne 1) { throw "$generatedEzUI must contain exactly one root-level .toc; found $($toc.Count)" }
    foreach ($required in @('Assets.lua', 'EZUI-PROVENANCE.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $addon $required) -PathType Leaf)) {
            throw "$generatedEzUI is missing generated marker: $required"
        }
    }
    $reference = Get-Content -LiteralPath $EzCollectionsReferenceFile -Raw | ConvertFrom-Json
    $provenance = Get-Content -LiteralPath (Join-Path $addon 'EZUI-PROVENANCE.json') -Raw | ConvertFrom-Json
    if ($provenance.schemaVersion -ne 1 -or $provenance.generatedAddon -ne $generatedEzUI) {
        throw "$generatedEzUI provenance schema or AddOn name is invalid"
    }
    if ($provenance.sourceTreeHash -ne $reference.directoryHash) {
        throw "$generatedEzUI source hash does not match ezCollections-reference.json"
    }
    $assetFiles = @(Get-ChildItem -LiteralPath $addon -File -Recurse -Force | Where-Object {
        $_.Name -notin @('Assets.lua', 'MountDescriptions.zhCN.lua', 'SoloCollections_EzUI.toc', 'EZUI-PROVENANCE.json')
    })
    $assetHash = Get-TreeHashFromFiles -Path $addon -Files $assetFiles
    if ($assetHash -ne $reference.localAssetProjection.directoryHash -or
        $assetHash -ne $provenance.assetTreeHash) {
        throw "$generatedEzUI asset projection hash mismatch. reference=$($reference.localAssetProjection.directoryHash) provenance=$($provenance.assetTreeHash) actual=$assetHash"
    }
    $rows += [pscustomobject]@{
        addon = $generatedEzUI
        toc = $toc[0].Name
        directoryHash = "assets:$assetHash"
    }
}

$rows | Format-Table -AutoSize

