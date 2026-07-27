<#
.SYNOPSIS
Builds the fixed, local-only round-two evidence pack on F: with a SHA-256 manifest.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $EvidenceRoot,
    [Parameter(Mandatory = $true)][string] $ClientRoot,
    [Parameter(Mandatory = $true)][string] $WeaponBuildRoot,
    [string] $AddonRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string] $EvidenceId = ('round2-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')),
    [string] $WorldSnapshotQueryVersion = 'mount-catalog-exact-entry-v1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\WdbState.Common.ps1')

$evidenceRootFull = Get-NormalizedFullPath $EvidenceRoot
$clientRootFull = Get-NormalizedFullPath $ClientRoot
$weaponRootFull = Get-NormalizedFullPath $WeaponBuildRoot
$addonRootFull = Get-NormalizedFullPath $AddonRoot
Assert-NonSystemDrivePath $evidenceRootFull

foreach ($requiredRoot in @($clientRootFull, $weaponRootFull, $addonRootFull)) {
    if (-not (Test-Path -LiteralPath $requiredRoot -PathType Container)) {
        throw "Evidence source root does not exist: $requiredRoot"
    }
}
if (Test-Path -LiteralPath $evidenceRootFull) {
    $existing = @(Get-ChildItem -LiteralPath $evidenceRootFull -Force)
    if ($existing.Count -gt 0) {
        throw "EvidenceRoot must be new or empty: $evidenceRootFull"
    }
}
else {
    [void](New-Item -ItemType Directory -Path $evidenceRootFull)
}

$records = @()
function Add-EvidenceRecord {
    param(
        [Parameter(Mandatory = $true)][string] $Destination,
        [Parameter(Mandatory = $true)][string] $RelativePath,
        [Parameter(Mandatory = $true)][string] $Role
    )

    $file = Get-Item -LiteralPath $Destination
    $script:records += [ordered]@{
        relativePath = $RelativePath
        role = $Role
        size = [int64]$file.Length
        sha256 = Get-Sha256Lower $Destination
    }
}

function Add-EvidenceFile {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $RelativePath,
        [Parameter(Mandatory = $true)][string] $Role
    )

    $sourceFull = Get-NormalizedFullPath $Source
    if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
        throw "Required evidence file is missing: $sourceFull"
    }
    $normalizedRelative = $RelativePath.Replace('\\', '/').TrimStart('/')
    if ($normalizedRelative -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($normalizedRelative)) {
        throw "Evidence relative path is unsafe: $RelativePath"
    }
    $destination = Get-NormalizedFullPath (Join-Path $evidenceRootFull $normalizedRelative.Replace('/', '\\'))
    Assert-PathUnderRoot -Path $destination -Root $evidenceRootFull
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    if (Test-Path -LiteralPath $destination) {
        throw "Duplicate evidence destination: $normalizedRelative"
    }
    Copy-Item -LiteralPath $sourceFull -Destination $destination
    Add-EvidenceRecord -Destination $destination -RelativePath $normalizedRelative -Role $Role
}

function Get-PortableWeaponSourcePath {
    param([AllowNull()][object] $Value)

    $normalized = ([string]$Value).Replace('\', '/')
    if ($normalized.StartsWith('extract/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalized
    }
    $marker = '/extract/'
    $markerIndex = $normalized.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($markerIndex -ge 0) {
        return $normalized.Substring($markerIndex + 1)
    }
    return [System.IO.Path]::GetFileName($normalized)
}

function Add-SanitizedWeaponManifests {
    $buildSource = Join-Path $weaponRootFull 'weapon-creature-build.json'
    $verificationSource = Join-Path $weaponRootFull 'weapon-model-verification.csv'
    foreach ($required in @($buildSource, $verificationSource)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required weapon evidence file is missing: $required"
        }
    }

    $buildRelative = 'weapon-resources/weapon-creature-build.json'
    $buildDestination = Join-Path $evidenceRootFull $buildRelative.Replace('/', '\')
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $buildDestination))
    $parsedBuildEntries = Get-Content -LiteralPath $buildSource -Raw -Encoding UTF8 | ConvertFrom-Json
    $buildEntries = @($parsedBuildEntries | ForEach-Object { $_ })
    $sanitizedEntries = @($buildEntries | ForEach-Object {
        $itemId = $null
        if ([string]$_.target -match '_(\d+)$') { $itemId = [int64]$Matches[1] }
        [ordered]@{
            item_id = $itemId
            source_m2 = Get-PortableWeaponSourcePath $_.source_m2
            source_skin = Get-PortableWeaponSourcePath $_.source_skin
            source_texture = Get-PortableWeaponSourcePath $_.source_texture
            target = ([string]$_.target).Replace('\', '/')
            texture_name = [string]$_.texture_name
            model_id = [int64]$_.model_id
            display_id = [int64]$_.display_id
        }
    })
    $serializedEntries = @($sanitizedEntries | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress })
    $buildJson = "[`n" + (($serializedEntries | ForEach-Object { "  $_" }) -join ",`n") + "`n]`n"
    [System.IO.File]::WriteAllText($buildDestination, $buildJson, (New-Object System.Text.UTF8Encoding($false)))
    Add-EvidenceRecord -Destination $buildDestination -RelativePath $buildRelative -Role 'weapon-resource-manifest'

    $verificationRelative = 'weapon-resources/weapon-model-verification.csv'
    $verificationDestination = Join-Path $evidenceRootFull $verificationRelative.Replace('/', '\')
    $verificationRows = @(Import-Csv -LiteralPath $verificationSource | ForEach-Object {
        [pscustomobject][ordered]@{
            Archive = [System.IO.Path]::GetFileName([string]$_.Archive)
            Path = ([string]$_.Path).Replace('\', '/')
            StageLength = [string]$_.StageLength
            VerifyLength = [string]$_.VerifyLength
            StageSHA256 = ([string]$_.StageSHA256).ToLowerInvariant()
            VerifySHA256 = ([string]$_.VerifySHA256).ToLowerInvariant()
            Match = [string]$_.Match
        }
    })
    $verificationRows | Export-Csv -LiteralPath $verificationDestination -NoTypeInformation -Encoding UTF8
    Add-EvidenceRecord -Destination $verificationDestination -RelativePath $verificationRelative -Role 'weapon-real-client-verification'
}

$dbcNames = @(
    'ChrRaces.dbc',
    'CreatureDisplayInfo.dbc',
    'CreatureModelData.dbc',
    'Item.dbc',
    'ItemDisplayInfo.dbc',
    'ItemSet.dbc',
    'SkillLineAbility.dbc',
    'Spell.dbc',
    'SpellIcon.dbc'
)
foreach ($name in $dbcNames) {
    Add-EvidenceFile -Source (Join-Path $clientRootFull "dbc\$name") -RelativePath "dbc/$name" -Role 'client-dbc'
}

$repositoryInputs = [ordered]@{
    'catalog/review/mounts/evidence.json' = 'parsed-world-and-dbc-evidence'
    'catalog/review/mounts/review-policy.json' = 'review-policy'
    'catalog/review/companions/evidence.json' = 'parsed-world-and-dbc-evidence'
    'catalog/review/companions/review-policy.json' = 'review-policy'
    'catalog/generated/companion-candidates.csv' = 'generated-review-table'
    'catalog/generated/companion-exclusions.csv' = 'generated-review-table'
    'catalog/review/toys/evidence.json' = 'parsed-world-and-dbc-evidence'
    'catalog/review/toys/review-policy.json' = 'review-policy'
    'catalog/generated/toy-candidates.csv' = 'generated-review-table'
    'catalog/generated/toy-exclusions.csv' = 'generated-review-table'
    'catalog/review/sets/evidence.json' = 'parsed-world-and-dbc-evidence'
    'catalog/review/sets/review-policy.json' = 'review-policy'
    'catalog/generated/itemset-candidates.csv' = 'generated-review-table'
    'catalog/generated/itemset-exclusions.csv' = 'generated-review-table'
    'catalog/generated/normalized-itemsets.json' = 'normalized-catalog'
    'catalog/generated/set-id-registry-view.json' = 'generated-registry-view'
    'catalog/fixtures/sets/manual8.normalized.json' = 'rollback-fixture'
    'catalog/generated/catalog-manifest.json' = 'generated-baseline'
    'catalog/generated/appearance-sources.json' = 'generated-baseline'
    'catalog/source/versions.json' = 'catalog-version'
    'catalog/source/mount_actions.json' = 'server-action-map'
    'catalog/source/companion_actions.json' = 'server-action-map'
    'catalog/source/toy_actions.json' = 'server-action-map'
    'catalog/source/sets.json' = 'server-action-map'
    'catalog/ids.json' = 'stable-id-registry'
}
foreach ($relative in $repositoryInputs.Keys) {
    Add-EvidenceFile -Source (Join-Path $addonRootFull $relative.Replace('/', '\\')) -RelativePath "repository/$relative" -Role $repositoryInputs[$relative]
}

Add-SanitizedWeaponManifests
$weaponStage = Get-NormalizedFullPath (Join-Path $weaponRootFull 'stage')
if (-not (Test-Path -LiteralPath $weaponStage -PathType Container)) {
    throw "Verified weapon stage is missing: $weaponStage"
}
$weaponPrefix = $weaponStage.Length + 1
foreach ($file in @(Get-ChildItem -LiteralPath $weaponStage -File -Recurse | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($weaponPrefix).Replace([System.IO.Path]::DirectorySeparatorChar, [char]'/')
    Add-EvidenceFile -Source $file.FullName -RelativePath "weapon-resources/stage/$relative" -Role 'weapon-client-asset'
}

$recordByPath = @{}
[string[]]$sortedPaths = @($records | ForEach-Object {
    $recordByPath[[string]$_.relativePath] = $_
    [string]$_.relativePath
})
[System.Array]::Sort($sortedPaths, [System.StringComparer]::Ordinal)
$sortedRecords = @($sortedPaths | ForEach-Object { $recordByPath[$_] })
$canonicalLines = @($sortedRecords | ForEach-Object {
    "$($_.relativePath)`0$($_.size)`0$($_.sha256)`n"
}) -join ''
$bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($canonicalLines)
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $packHash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
}
finally {
    $sha.Dispose()
}

$clientBuild = 'unknown'
$wowPath = Join-Path $clientRootFull 'Wow.exe'
if (Test-Path -LiteralPath $wowPath -PathType Leaf) {
    $version = (Get-Item -LiteralPath $wowPath).VersionInfo.FileVersion
    if (-not [string]::IsNullOrWhiteSpace($version)) { $clientBuild = $version }
}
$locale = 'unknown'
$configPath = Join-Path $clientRootFull 'WTF\Config.wtf'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $match = Select-String -LiteralPath $configPath -Pattern '^\s*SET\s+locale\s+"([^"]+)"\s*$' | Select-Object -First 1
    if ($match -and $match.Matches.Count -gt 0) { $locale = $match.Matches[0].Groups[1].Value }
}

$manifest = [ordered]@{
    schemaVersion = 1
    evidenceId = $EvidenceId
    createdUtc = [DateTime]::UtcNow.ToString('o')
    clientBuild = $clientBuild
    clientLocale = $locale
    sourceSanitization = [ordered]@{
        credentialsIncluded = $false
        databaseDumpIncluded = $false
        absoluteSourcePathsIncluded = $false
    }
    worldSnapshot = [ordered]@{
        queryVersion = $WorldSnapshotQueryVersion
        source = 'repository/catalog/review/mounts/evidence.json'
        credentialsIncluded = $false
        databaseDumpIncluded = $false
    }
    weaponResourceManifest = 'weapon-resources/weapon-creature-build.json'
    fileCount = @($records).Count
    packHash = $packHash
    files = @($sortedRecords)
}
$manifestPath = Join-Path $evidenceRootFull 'evidence-manifest.json'
Write-JsonAtomic -Path $manifestPath -Value $manifest
Write-Host "Round-two evidence pack created: id=$EvidenceId files=$($manifest.fileCount) hash=$packHash"
