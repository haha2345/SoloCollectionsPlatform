<#
.SYNOPSIS
Writes a sanitized, F:-only baseline manifest for the wardrobe/camera/set work.

.DESCRIPTION
The manifest deliberately stores only repository-relative and deployment-root-relative
paths.  It is a live snapshot of the files that the current client/server deployment
would consume; it never copies credentials, client assets, database dumps, or source
machine paths into the report.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$AddonRoot,
    [Parameter(Mandatory)][string]$ModuleRoot,
    [Parameter(Mandatory)][string]$CoreRoot,
    [Parameter(Mandatory)][string]$DeploymentProfile,
    [string]$BaselineBundleRoot = '',
    [string]$FixedInputsRoot = '',
    [string]$ClientEvidenceRoot = '',
    [string]$AutomatedEvidenceRoot = '',
    [string]$EvidenceId = 'round3-wardrobe-camera-set-stage0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'release\RoundTwoRelease.Common.ps1')

function Assert-FDrivePath {
    param([Parameter(Mandatory)][string]$Path)

    if (-not $Path.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Wardrobe/camera/set evidence must stay on F:: $Path"
    }
}

function Get-PortableRelativePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $rootPrefix = $Root.TrimEnd('\') + '\'
    if (-not $Path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside declared root: $Path"
    }
    $relative = $Path.Substring($rootPrefix.Length).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -eq '..' -or $relative.StartsWith('../')) {
        throw "Path has no portable relative form: $Path"
    }
    return $relative
}

function Get-PortableFileRecord {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Role
    )

    $file = Resolve-RoundTwoPath -Path $Path
    $rootPath = Resolve-RoundTwoPath -Path $Root
    Assert-RoundTwoWithin -Path $file -Root $rootPath
    $item = Get-Item -LiteralPath $file
    return [ordered]@{
        relativePath = Get-PortableRelativePath -Path $file -Root $rootPath
        role = $Role
        size = [int64]$item.Length
        sha256 = Get-RoundTwoSha256 -Path $file
    }
}

function Get-PortableTreeRecords {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Role
    )

    $rootPath = Resolve-RoundTwoPath -Path $Root
    return @(
        Get-ChildItem -LiteralPath $rootPath -File -Recurse |
            Sort-Object FullName |
            ForEach-Object { Get-PortableFileRecord -Path $_.FullName -Root $rootPath -Role $Role }
    )
}

function Get-GitSnapshot {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$Role)

    $repo = Resolve-RoundTwoPath -Path $Repository
    $commit = Get-RoundTwoCommit -Repo $repo
    $branchOutput = @(& git -C $repo symbolic-ref --short -q HEAD)
    $branch = if ($branchOutput.Count -gt 0) { ([string]$branchOutput[0]).Trim() } else { '' }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { $branch = 'DETACHED' }
    $status = @(& git -C $repo status --short --branch)
    if ($LASTEXITCODE -ne 0) { throw "git status failed: $repo" }
    return [ordered]@{
        role = $Role
        commit = $commit
        branch = $branch
        status = @($status)
        trackedDirty = (@(& git -C $repo status --porcelain --untracked-files=no)).Count -gt 0
        untracked = @(& git -C $repo ls-files --others --exclude-standard)
    }
}

function Get-EvidenceRecords {
    param([string]$Root, [Parameter(Mandatory)][string]$Role)

    if ([string]::IsNullOrWhiteSpace($Root)) { return @() }
    $full = Resolve-RoundTwoPath -Path $Root
    Assert-FDrivePath -Path $full
    return Get-PortableTreeRecords -Root $full -Role $Role
}

function Get-AppearanceStatistics {
    param([Parameter(Mandatory)][string]$Repository)

    $manifest = Read-RoundTwoJson -Path (Join-Path $Repository 'catalog\generated\catalog-manifest.json')
    $all = @($manifest.collections | Where-Object { [string]$_.typeKey -eq 'appearance' })
    $public = @($all | Where-Object { [string]$_.uiLifecycle -eq 'public' })
    function Group-RenderModes([object[]]$Rows) {
        $result = [ordered]@{ BODY = 0; STANDALONE = 0; UNAVAILABLE = 0 }
        foreach ($row in $Rows) {
            $mode = [string]$row.renderMode
            if (-not $result.Contains($mode)) { throw "Unknown appearance render mode: $mode" }
            $result[$mode]++
        }
        return $result
    }
    return [ordered]@{
        all = Group-RenderModes -Rows $all
        public = Group-RenderModes -Rows $public
    }
}

$output = Resolve-RoundTwoPath -Path $OutputRoot -AllowMissing
Assert-FDrivePath -Path $output
$addon = Resolve-RoundTwoPath -Path $AddonRoot
$module = Resolve-RoundTwoPath -Path $ModuleRoot
$core = Resolve-RoundTwoPath -Path $CoreRoot
$profilePath = Resolve-RoundTwoPath -Path $DeploymentProfile
$profile = Read-RoundTwoJson -Path $profilePath
Assert-RoundTwoProfile -Profile $profile

if (Test-Path -LiteralPath $output -PathType Leaf) { throw "OutputRoot is a file: $output" }
New-Item -ItemType Directory -Force -Path $output | Out-Null

$clientRoot = Resolve-RoundTwoPath -Path ([string]$profile.clientRoot)
$serverRoot = Resolve-RoundTwoPath -Path ([string]$profile.serverRoot)
$catalogManifest = Read-RoundTwoJson -Path (Join-Path $addon 'catalog\generated\catalog-manifest.json')
$setManifest = Read-RoundTwoJson -Path (Join-Path $addon 'catalog\generated\normalized-itemsets.json')
$cameraProfiles = Read-RoundTwoJson -Path (Join-Path $addon 'catalog\source\camera_profiles.json')
$presentationReport = Read-RoundTwoJson -Path (Join-Path $addon 'catalog\generated\appearance-presentation-report.json')

$deploymentFiles = @(
    [ordered]@{ root = 'client'; record = Get-PortableTreeRecords -Root ([string]$profile.addonRoot) -Role 'deployed-addon' },
    [ordered]@{ root = 'client'; record = @(
        Get-PortableFileRecord -Path ([string]$profile.soloCamDllTarget) -Root $clientRoot -Role 'solocam-dll'
    ) },
    [ordered]@{ root = 'server'; record = @(
        Get-PortableFileRecord -Path ([string]$profile.worldserverExeTarget) -Root $serverRoot -Role 'worldserver'
    ) }
)
foreach ($assetPatch in @($profile.assetPatchTargets)) {
    $deploymentFiles += [ordered]@{ root = 'client'; record = @(
        Get-PortableFileRecord -Path ([string]$assetPatch.target) -Root $clientRoot -Role 'asset-patch'
    ) }
}

$templates = Get-Content -LiteralPath (Join-Path $addon 'addon\SoloCollections\UI\Templates.lua') -Raw -Encoding UTF8
$retailReferences = @([regex]::Matches($templates, 'Retail\\[^"\r\n]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
$bundleScript = Get-Content -LiteralPath (Join-Path $addon 'tools\release\New-RoundTwoBundle.ps1') -Raw -Encoding UTF8

$fixedInputs = @()
if (-not [string]::IsNullOrWhiteSpace($FixedInputsRoot)) {
    $fixed = Resolve-RoundTwoPath -Path $FixedInputsRoot
    Assert-FDrivePath -Path $fixed
    $fixedManifest = Join-Path $fixed 'evidence-manifest.json'
    $fixedInputs = @([ordered]@{
        relativePath = 'fixed-inputs/evidence-manifest.json'
        role = 'fixed-input-manifest'
        size = [int64](Get-Item -LiteralPath $fixedManifest).Length
        sha256 = Get-RoundTwoSha256 -Path $fixedManifest
    })
}

$bundleBaseline = $null
if (-not [string]::IsNullOrWhiteSpace($BaselineBundleRoot)) {
    $bundleRoot = Resolve-RoundTwoPath -Path $BaselineBundleRoot
    Assert-FDrivePath -Path $bundleRoot
    $bundleManifestPath = Join-Path $bundleRoot 'release-manifest.json'
    $bundleManifest = Read-RoundTwoJson -Path $bundleManifestPath
    $bundleAddonFiles = @($bundleManifest.files |
        Where-Object { ([string]$_.relativePath).StartsWith('addon/SoloCollections/', [System.StringComparison]::Ordinal) } |
        ForEach-Object { [string]$_.relativePath } |
        Sort-Object)
    $bundleBaseline = [ordered]@{
        bundleId = [string]$bundleManifest.bundleId
        manifestSha256 = Get-RoundTwoSha256 -Path $bundleManifestPath
        addonFileCount = $bundleAddonFiles.Count
        addonFiles = $bundleAddonFiles
        retailFiles = @($bundleAddonFiles | Where-Object { $_ -match '^addon/SoloCollections/Media/Retail/' })
    }
}

$evidenceRecords = @(
    Get-EvidenceRecords -Root $ClientEvidenceRoot -Role 'client-observation'
    Get-EvidenceRecords -Root $AutomatedEvidenceRoot -Role 'automated-test'
)
$weaponEntries = @($presentationReport.entries | ForEach-Object {
    [ordered]@{
        appearanceId = [int64]$_.appearanceId
        sourceItemId = [int64]$_.sourceItemId
        syntheticDisplayId = [int64]$_.syntheticDisplayId
        modelPath = [string]$_.modelPath
        assetHashes = $_.assetHashes
        cameraTuningKey = [string]$_.cameraTuningKey
        pose = $_.m2Camera
    }
})

$manifest = [ordered]@{
    schemaVersion = 1
    evidenceId = $EvidenceId
    createdUtc = [DateTime]::UtcNow.ToString('o')
    sourceSanitization = [ordered]@{
        credentialsIncluded = $false
        databaseDumpIncluded = $false
        absoluteSourcePathsIncluded = $false
        clientAssetBodiesIncluded = $false
    }
    repositories = @(
        Get-GitSnapshot -Repository $addon -Role 'addon'
        Get-GitSnapshot -Repository $module -Role 'module'
        Get-GitSnapshot -Repository $core -Role 'core'
    )
    catalog = [ordered]@{
        metadataVersion = [string]$catalogManifest.metadataVersion
        assetPackVersion = [string]$catalogManifest.assetPackVersion
        appearancePresentationHash = [string]$catalogManifest.appearancePresentationHash
        cameraProfileHash = [string]$cameraProfiles.evidenceHash
        setMappingHash = [string]$setManifest.mappingHash
        setPresentationHash = [string]$setManifest.presentationHash
        appearanceStatistics = Get-AppearanceStatistics -Repository $addon
        verifiedStandaloneWeapons = @($weaponEntries)
    }
    deployments = $deploymentFiles
    mediaFailureBaseline = [ordered]@{
        productionRetailReferences = $retailReferences
        bundleExcludesRetailDirectory = $bundleScript -match 'Media/Retail/\*'
        requiredBaseMediaRolesPresent = $false
        cleanBundle = $bundleBaseline
    }
    fixedInputs = $fixedInputs
    observations = $evidenceRecords
}

$manifestText = $manifest | ConvertTo-Json -Depth 40
if ($manifestText -match '(?i)([A-Z]:\\|password|"admin")') {
    throw 'Sanitization failure: baseline manifest contains an absolute path or credential-like value.'
}
$manifestPath = Join-Path $output 'evidence-manifest.json'
Write-RoundTwoJson -Value $manifest -Path $manifestPath -Depth 40
Write-Host "wardrobe_camera_set_baseline=$manifestPath"
Write-Host "observations=$($evidenceRecords.Count)"
Write-Host "verified_weapons=$($weaponEntries.Count)"
