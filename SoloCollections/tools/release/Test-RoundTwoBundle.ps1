[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot,
    [string]$Profile = '',
    [switch]$Installed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'RoundTwoRelease.Common.ps1')

$bundle = Resolve-RoundTwoPath $BundleRoot
$manifest = Read-RoundTwoJson (Join-Path $bundle 'release-manifest.json')
if ($manifest.schemaVersion -ne 1 -or [string]$manifest.bundleId -ne (Split-Path -Leaf $bundle)) { throw "Bundle identity mismatch" }
$seen = @{}
foreach ($entry in $manifest.files) {
    $relative = [string]$entry.relativePath
    if ($relative -match '(^|/)\.\.(/|$)' -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($relative)) { throw "Unsafe bundle path: $relative" }
    if ($seen.ContainsKey($relative)) { throw "Duplicate bundle path: $relative" }
    $seen[$relative] = $true
    $path = Join-Path $bundle $relative.Replace('/','\')
    Assert-RoundTwoWithin -Path $path -Root $bundle
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bundle file missing: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$entry.size -or (Get-RoundTwoSha256 $path) -ne [string]$entry.sha256) { throw "Bundle hash mismatch: $relative" }
}
Assert-RoundTwoBaseMedia -AddonRoot (Join-Path $bundle 'addon\SoloCollections')
$worldserver = Join-Path $bundle 'server\worldserver.exe'
$pe = Get-RoundTwoPeInfo $worldserver
if (-not $pe.IsX64 -or $pe.Machine -ne [string]$manifest.worldserver.machine) { throw "Bundle worldserver PE mismatch" }
if ((Get-RoundTwoSha256 $worldserver) -ne [string]$manifest.worldserver.sha256) { throw "Bundle worldserver manifest mismatch" }
$metadata = Read-RoundTwoJson (Join-Path $bundle 'server\module-build-metadata.json')
foreach ($name in @('addonCommit','moduleCommit','coreCommit','metadataVersion','assetPackVersion','mappingHash','presentationHash','mountMappingHash','companionMappingHash','toyMappingHash','appearanceMappingHash','setMappingHash')) {
    if ([string]$metadata.values.$name -ne [string]$manifest.build.$name) { throw "Build metadata mismatch: $name" }
}
$catalogLua = Get-Content -LiteralPath (Join-Path $bundle 'addon\SoloCollections\Data\Generated\Catalog.lua') -Raw -Encoding UTF8
foreach ($pair in @(@('metadataVersion',$manifest.build.metadataVersion),@('assetPackVersion',$manifest.build.assetPackVersion),@('mappingHash',$manifest.build.mappingHash),@('presentationHash',$manifest.build.presentationHash))) {
    if ($catalogLua -notmatch ([regex]::Escape($pair[0]) + '\s*=\s*"' + [regex]::Escape([string]$pair[1]) + '"')) { throw "AddOn generated constant mismatch: $($pair[0])" }
}
foreach ($dependency in $manifest.dependencies) {
    if ($dependency.classification -eq 'BUNDLED_NON_SYSTEM') {
        $path = Join-Path $bundle ('server\runtime-dependencies\' + [string]$dependency.fileName)
        if (-not (Test-Path -LiteralPath $path) -or (Get-RoundTwoSha256 $path) -ne [string]$dependency.sha256) { throw "Bundled dependency mismatch: $($dependency.fileName)" }
    }
}
if ($Installed) {
    if (-not $Profile) { throw "-Installed requires -Profile" }
    $profilePath = Resolve-RoundTwoPath $Profile
    $deployment = Read-RoundTwoJson $profilePath
    Assert-RoundTwoProfile $deployment
    $backupManifestPath = Join-Path $bundle 'backup\backup-manifest.json'
    $backup = Read-RoundTwoJson $backupManifestPath
    foreach ($entry in $backup.entries) {
        $target = Resolve-RoundTwoPath -Path ([string]$entry.target) -AllowMissing
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-RoundTwoSha256 $target) -ne [string]$entry.installedSha256) { throw "Installed file mismatch: $target" }
    }
    Write-Host "installed_status_contract=manual_console_or_captured_key_value_required"
    Write-Host "expected_build_mapping_hash=$($manifest.build.mappingHash)"
}
Write-Host "bundle_verified=$bundle"
Write-Host "bundle_file_count=$($manifest.files.Count)"
Write-Host "worldserver_machine=$($pe.Machine)"
