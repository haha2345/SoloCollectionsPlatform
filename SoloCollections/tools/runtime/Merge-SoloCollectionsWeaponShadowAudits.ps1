[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$RunRoots,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-FPath {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$AllowMissing)
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "Wildcard paths are forbidden: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $full.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be on F:, got: $full"
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Required path is missing: $full"
    }
    return $full
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$output = Resolve-FPath $OutputRoot -AllowMissing
if (Test-Path -LiteralPath $output) { throw "Aggregate output already exists: $output" }
if ($RunRoots.Count -eq 0) { throw 'At least one accepted audit run is required.' }

$runs = @($RunRoots | ForEach-Object { Resolve-FPath $_ })
$allRows = New-Object System.Collections.Generic.List[object]
$seenAppearances = @{}
$bundleStage = $null
$bundleId = $null
$stageManifest = $null
$runMetadata = New-Object System.Collections.Generic.List[object]

foreach ($run in $runs) {
    $summaryPath = Join-Path $run 'weapon-shadow-audit-summary.json'
    $csvPath = Join-Path $run 'weapon-shadow-audit.csv'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf) -or -not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        throw "Accepted audit artifacts are incomplete: $run"
    }
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$summary.expected -ne [int]$summary.total -or [int]$summary.ready -ne [int]$summary.expected -or [int]$summary.failed -ne 0) {
        throw "Audit summary is not accepted: $run"
    }
    $runInfo = Get-Content -LiteralPath (Join-Path $run 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runBundleId = if ($runInfo.PSObject.Properties.Name -contains 'bundleId') {
        [string]$runInfo.bundleId
    }
    elseif ($summary.PSObject.Properties.Name -contains 'bundleId') {
        # Export-SoloCollectionsWeaponShadowAudit.ps1 derives this field from
        # the validated stage for immutable early runs that did not yet write
        # a duplicate bundleId in run.json.
        [string]$summary.bundleId
    }
    else {
        throw "Audit run lacks a bundle identity: $run"
    }
    if ($null -eq $bundleStage) {
        $bundleStage = [string]$summary.bundleStage
        $bundleId = $runBundleId
        $stageManifestPath = Join-Path $bundleStage 'weapon-bundle-manifest.json'
        if (-not (Test-Path -LiteralPath $stageManifestPath -PathType Leaf)) { throw "Stage manifest is missing: $stageManifestPath" }
        $stageManifest = Get-Content -LiteralPath $stageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($stageManifest.kind -ne 'SoloCollectionsWeaponBundleStage' -or [string]$stageManifest.bundleId -ne $bundleId) {
            throw 'Stage manifest identity mismatch.'
        }
    }
    elseif ([string]$summary.bundleStage -ne $bundleStage -or $runBundleId -ne $bundleId) {
        throw "Audit runs do not share the same stage/bundle identity: $run"
    }
    foreach ($row in @((Get-Content -LiteralPath $csvPath -Raw -Encoding UTF8) | ConvertFrom-Csv)) {
        if ([string]$row.status -ne 'READY') { throw "Aggregate contains a non-ready row: $($row.appearanceId)" }
        $appearanceId = [string]$row.appearanceId
        if ($seenAppearances.ContainsKey($appearanceId)) { throw "Aggregate appearance is duplicated: $appearanceId" }
        $seenAppearances[$appearanceId] = $true
        $allRows.Add($row) | Out-Null
    }
    $runMetadata.Add([ordered]@{
        runId=[string]$summary.runId; expected=[int]$summary.expected; ready=[int]$summary.ready
        selectionStartIndex=[int]$summary.selectionStartIndex; selectionCount=[int]$summary.selectionCount
        csvSha256=[string]$summary.csvSha256
    }) | Out-Null
}

$projection = @($stageManifest.registryProjection.records | Sort-Object -Property @{ Expression = { [int]$_.syntheticDisplayId }; Ascending = $true }, @{ Expression = { [int]$_.appearanceId }; Ascending = $true })
if ($seenAppearances.Count -ne $projection.Count) {
    throw "All stage appearances are not covered: expected=$($projection.Count) actual=$($seenAppearances.Count)"
}
$expectedByAppearance = @{}
foreach ($record in $projection) {
    $appearanceId = [string]$record.appearanceId
    if ($expectedByAppearance.ContainsKey($appearanceId)) { throw "Stage appearance is duplicated: $appearanceId" }
    $expectedByAppearance[$appearanceId] = $record
}
foreach ($appearanceId in $seenAppearances.Keys) {
    if (-not $expectedByAppearance.ContainsKey($appearanceId)) { throw "Aggregate appearance is absent from stage: $appearanceId" }
}

New-Item -ItemType Directory -Path $output | Out-Null
$csvOutput = Join-Path $output 'weapon-shadow-audit-aggregate.csv'
$csvLines = @($allRows | Sort-Object -Property @{ Expression = { [int]$_.syntheticDisplayId }; Ascending = $true }, @{ Expression = { [int]$_.appearanceId }; Ascending = $true } | ConvertTo-Csv -NoTypeInformation)
[IO.File]::WriteAllLines($csvOutput, [string[]]$csvLines, [Text.UTF8Encoding]::new($false))
$summaryOutput = Join-Path $output 'weapon-shadow-audit-aggregate-summary.json'
$result = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponShadowAuditAggregate'; bundleId=$bundleId; bundleStage=$bundleStage
    stageBundleManifestHash=[string]$stageManifest.bundleManifestHash; expected=$projection.Count; ready=$allRows.Count; failed=0
    csvSha256=Get-Sha256 $csvOutput; runs=$runMetadata.ToArray()
}
[IO.File]::WriteAllText($summaryOutput, (($result | ConvertTo-Json -Depth 16) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 16
