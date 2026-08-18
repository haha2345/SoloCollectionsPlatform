[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-FPath {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label must be absolute: $Path" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $full.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must be on F:, got: $full" }
    if (-not (Test-Path -LiteralPath $full)) { throw "$Label is missing: $full" }
    return $full
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function ConvertFrom-LuaString {
    param([Parameter(Mandatory = $true)][string]$Value)
    $builder = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $char = $Value[$index]
        if ($char -ne '\') { [void]$builder.Append($char); continue }
        $index++
        if ($index -ge $Value.Length) { throw 'Incomplete Lua escape in SavedVariables CSV.' }
        switch ($Value[$index]) {
            'n' { [void]$builder.Append("`n") }
            'r' { [void]$builder.Append("`r") }
            't' { [void]$builder.Append("`t") }
            '\' { [void]$builder.Append('\') }
            '"' { [void]$builder.Append('"') }
            default { [void]$builder.Append($Value[$index]) }
        }
    }
    return $builder.ToString()
}

function Normalize-ModelPath {
    param([AllowNull()][string]$Value)
    return ([string]$Value).Replace('/', '\').ToLowerInvariant()
}

$run = Resolve-FPath $RunRoot 'RunRoot'
$runMetadataPath = Join-Path $run 'run.json'
$saved = Join-Path $run 'SoloCollectionsWeaponPresentationAudit.lua'
if (-not (Test-Path -LiteralPath $runMetadataPath -PathType Leaf) -or -not (Test-Path -LiteralPath $saved -PathType Leaf)) {
    throw 'Runtime audit run metadata or SavedVariables capture is missing.'
}
$runMetadata = Get-Content -LiteralPath $runMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($name in @('bundleId', 'assetPackVersion', 'cacheState', 'expected', 'presentationSource', 'presentationReport', 'catalogManifest')) {
    if (-not ($runMetadata.PSObject.Properties.Name -contains $name)) { throw "Run metadata is missing $name." }
}
$presentationSource = Resolve-FPath ([string]$runMetadata.presentationSource) 'PresentationSource'
$presentationReport = Resolve-FPath ([string]$runMetadata.presentationReport) 'PresentationReport'
$catalogManifest = Resolve-FPath ([string]$runMetadata.catalogManifest) 'CatalogManifest'
$source = Get-Content -LiteralPath $presentationSource -Raw -Encoding UTF8 | ConvertFrom-Json
$report = Get-Content -LiteralPath $presentationReport -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog = Get-Content -LiteralPath $catalogManifest -Raw -Encoding UTF8 | ConvertFrom-Json
if ($source.schemaVersion -ne 2 -or $report.schemaVersion -ne 3 -or
    [string]$source.assetPackVersion -ne [string]$runMetadata.assetPackVersion -or
    [string]$source.assetBundle.bundleId -ne [string]$runMetadata.bundleId -or
    [string]$catalog.appearancePresentationHash -notmatch '^[0-9a-f]{64}$') {
    throw 'Production presentation identity drifted from audit run metadata.'
}
$productionExpected = [int]$source.publicAppearanceCount
if ([int]$report.publicAppearanceCount -ne $productionExpected -or
    [int]$catalog.appearancePresentationPublicCount -ne $productionExpected) {
    throw 'Production presentation denominator drifted.'
}

$savedText = Get-Content -LiteralPath $saved -Raw -Encoding UTF8
function Read-LuaScalar {
    param([Parameter(Mandatory = $true)][string]$Name, [switch]$Optional)
    $match = [regex]::Match($savedText, ('\["' + [regex]::Escape($Name) + '"\]\s*=\s*([^,\r\n]+)'))
    if (-not $match.Success) {
        if ($Optional) { return $null }
        throw "SavedVariables field is missing: $Name"
    }
    $value = $match.Groups[1].Value.Trim()
    if ($value -eq 'true') { return $true }
    if ($value -eq 'false') { return $false }
    if ($value -match '^\d+$') { return [long]$value }
    if ($value -match '^"(.*)"$') { return $Matches[1] }
    throw "Unsupported SavedVariables scalar: $Name=$value"
}

if (-not (Read-LuaScalar 'completed') -or -not (Read-LuaScalar 'ready')) {
    throw 'Weapon presentation audit did not reach an accepted terminal state.'
}
if ([string](Read-LuaScalar 'bundleId') -ne [string]$runMetadata.bundleId -or
    [string](Read-LuaScalar 'assetPackVersion') -ne [string]$runMetadata.assetPackVersion -or
    [string](Read-LuaScalar 'appearancePresentationHash') -ne [string]$catalog.appearancePresentationHash -or
    [string](Read-LuaScalar 'cacheState') -ne [string]$runMetadata.cacheState) {
    throw 'SavedVariables identity differs from the audited production contract.'
}
if ([string](Read-LuaScalar 'presentationSourceSha256') -ne (Get-Sha256 $presentationSource) -or
    [string](Read-LuaScalar 'presentationReportSha256') -ne (Get-Sha256 $presentationReport) -or
    [string](Read-LuaScalar 'catalogManifestSha256') -ne (Get-Sha256 $catalogManifest)) {
    throw 'SavedVariables source hashes differ from the audited production contract.'
}
$sampleOnly = [bool](Read-LuaScalar 'sampleOnly' -Optional)
$allPublicByAppearance = @{}
foreach ($entry in @($source.entries)) {
    $status = [string]$entry.presentationStatus
    if ($status -notin @('READY', 'UNAVAILABLE')) { continue }
    $appearanceId = [string][int]$entry.appearanceId
    if ($allPublicByAppearance.ContainsKey($appearanceId)) { throw "Duplicate source appearance ID: $appearanceId" }
    $allPublicByAppearance[$appearanceId] = $entry
}
if ($allPublicByAppearance.Count -ne $productionExpected) { throw 'Source public appearance records are incomplete.' }

$expected = $productionExpected
$expectedReady = [int]$source.terminalCounts.READY
$expectedUnavailable = [int]$source.terminalCounts.UNAVAILABLE
$expectedByAppearance = $allPublicByAppearance
if ($sampleOnly) {
    if ([string]$runMetadata.auditKind -ne 'visual' -or [string]::IsNullOrWhiteSpace([string]$runMetadata.visualSamplePlan)) {
        throw 'Sample-only audit is not bound to a visual sample plan.'
    }
    $samplePlanPath = Resolve-FPath ([string]$runMetadata.visualSamplePlan) 'VisualSamplePlan'
    $samplePlan = Get-Content -LiteralPath $samplePlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($samplePlan.schemaVersion -ne 1 -or $samplePlan.kind -ne 'SoloCollectionsWeaponPresentationVisualSamplePlan' -or
        [string]$samplePlan.bundleId -ne [string]$runMetadata.bundleId -or
        [string]$samplePlan.assetPackVersion -ne [string]$runMetadata.assetPackVersion -or
        [string]$samplePlan.presentationSourceSha256 -ne (Get-Sha256 $presentationSource) -or
        [string](Read-LuaScalar 'samplePlanSha256') -ne (Get-Sha256 $samplePlanPath)) {
        throw 'Visual sample plan identity differs from the audited production contract.'
    }
    $expectedByAppearance = @{}
    $expectedReady = 0
    $expectedUnavailable = 0
    foreach ($sample in @($samplePlan.records)) {
        $appearanceId = [string][int]$sample.appearanceId
        if ($expectedByAppearance.ContainsKey($appearanceId) -or -not $allPublicByAppearance.ContainsKey($appearanceId)) {
            throw "Visual sample appearance is invalid or duplicated: $appearanceId"
        }
        $entry = $allPublicByAppearance[$appearanceId]
        if ([string]$sample.presentationStatus -ne [string]$entry.presentationStatus -or
            [int]$sample.sourceItemId -ne [int]$entry.sourceItemId) {
            throw "Visual sample identity drifted for appearance $appearanceId"
        }
        $expectedByAppearance[$appearanceId] = $entry
        if ([string]$entry.presentationStatus -eq 'READY') { $expectedReady++ } else { $expectedUnavailable++ }
    }
    $expected = $expectedByAppearance.Count
    if ($expected -le 0 -or $expected -ne [int]$samplePlan.sampleCount -or
        $expectedReady -ne [int]$samplePlan.readySampleCount -or
        $expectedUnavailable -ne [int]$samplePlan.unavailableSampleCount -or
        $expected -ne [int]$runMetadata.expected) {
        throw 'Visual sample plan denominator drifted.'
    }
}
elseif ($expected -ne [int]$runMetadata.expected) {
    throw 'Full production audit denominator differs from run metadata.'
}
if ([int](Read-LuaScalar 'expected') -ne $expected -or [int](Read-LuaScalar 'total') -ne $expected -or
    [int](Read-LuaScalar 'readyCount') -ne $expectedReady -or
    [int](Read-LuaScalar 'unavailableCount') -ne $expectedUnavailable -or
    [int](Read-LuaScalar 'failedCount') -ne 0) {
    throw 'SavedVariables terminal counts are not closed against the audited denominator.'
}
if ([string]$runMetadata.cacheState -eq 'reload') {
    if (-not (Read-LuaScalar 'reloadObserved') -or
        [int](Read-LuaScalar 'reloadLoginCount') -ne 2 -or
        [string](Read-LuaScalar 'reloadBoundary') -ne 'PLAYER_LOGIN') {
        throw 'Reload audit did not prove a second PLAYER_LOGIN across the external /reload boundary.'
    }
    $reloadMarkerPath = Join-Path $run 'reload-command.json'
    if (-not (Test-Path -LiteralPath $reloadMarkerPath -PathType Leaf)) {
        throw 'Reload audit is missing its external /reload command marker.'
    }
    $reloadMarker = Get-Content -LiteralPath $reloadMarkerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($reloadMarker.kind -ne 'SoloCollectionsWeaponPresentationAuditReloadCommand' -or
        [string]$reloadMarker.runId -ne [string]$runMetadata.runId -or
        [string]$reloadMarker.cacheState -ne 'reload' -or
        [string]::IsNullOrWhiteSpace([string]$reloadMarker.sentUtc)) {
        throw 'Reload command marker does not bind to this audit run.'
    }
}

$csvMatch = [regex]::Match($savedText, '(?s)\["csv"\]\s*=\s*"((?:\\.|[^"\\])*)"')
if (-not $csvMatch.Success) { throw 'Runtime audit CSV payload is missing.' }
$csv = ConvertFrom-LuaString $csvMatch.Groups[1].Value
$rows = @($csv | ConvertFrom-Csv)
if ($rows.Count -ne $expected) { throw "Runtime audit row count mismatch: expected=$expected actual=$($rows.Count)" }

$seen = @{}
$readyRows = 0
$unavailableRows = 0
foreach ($row in $rows) {
    $appearanceId = [string][int]$row.appearanceId
    if ($seen.ContainsKey($appearanceId)) { throw "Audit appearance ID is not unique: $appearanceId" }
    $seen[$appearanceId] = $true
    if (-not $expectedByAppearance.ContainsKey($appearanceId)) { throw "Audit appearance ID is not in production source: $appearanceId" }
    $entry = $expectedByAppearance[$appearanceId]
    $status = [string]$entry.presentationStatus
    if ([string]$row.presentationStatus -ne $status -or [int]$row.sourceItemId -ne [int]$entry.sourceItemId -or
        [string]$row.slot -notin @('MAINHAND', 'OFFHAND')) {
        throw "Runtime audit catalog identity mismatch for appearance $appearanceId"
    }
    if ([string]$row.failureReason) { throw "Runtime audit row has failure reason for appearance ${appearanceId}: $($row.failureReason)" }
    if ($status -eq 'READY') {
        if ([int]$row.syntheticDisplayId -ne [int]$entry.syntheticDisplayId -or
            (Normalize-ModelPath $row.expectedModelPath) -ne (Normalize-ModelPath $entry.modelPath) -or
            (Normalize-ModelPath $row.actualModelPath) -ne (Normalize-ModelPath $entry.modelPath) -or
            [string]$row.cardState -ne 'STANDALONE' -or
            [int]$row.stableTicks -lt 3 -or
            [int]$row.readyMilliseconds -lt 0 -or
            [string]::IsNullOrWhiteSpace([string]$row.poseSource)) {
            throw "READY runtime contract failed for appearance $appearanceId"
        }
        $readyRows++
    }
    else {
        if ([int]$row.syntheticDisplayId -ne 0 -or [string]$row.expectedModelPath -ne '' -or
            [string]$row.actualModelPath -ne '' -or [string]$row.cardState -ne 'UNAVAILABLE' -or
            [string]$row.iconVisible -ne 'true' -or [string]$row.reasonVisible -ne 'true') {
            throw "UNAVAILABLE runtime card contract failed for appearance $appearanceId"
        }
        $unavailableRows++
    }
}
if ($seen.Count -ne $expected -or $readyRows -ne $expectedReady -or
    $unavailableRows -ne $expectedUnavailable) {
    throw 'Runtime audit terminal coverage is incomplete.'
}

$csvPath = Join-Path $run 'weapon-presentation-runtime-audit.csv'
[IO.File]::WriteAllText($csvPath, $csv, [Text.UTF8Encoding]::new($false))
$reloadObserved = [string]$runMetadata.cacheState -eq 'reload'
$reloadLoginCount = if ($reloadObserved) { [int](Read-LuaScalar 'reloadLoginCount') } else { 0 }
$summary = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponPresentationRuntimeAudit'; runId=[string]$runMetadata.runId
    bundleId=[string]$runMetadata.bundleId; assetPackVersion=[string]$runMetadata.assetPackVersion
    cacheState=[string]$runMetadata.cacheState; expected=$expected; productionExpected=$productionExpected; sampleOnly=$sampleOnly
    ready=$readyRows; unavailable=$unavailableRows; failed=0
    appearancePresentationHash=[string]$catalog.appearancePresentationHash
    presentationSourceSha256=(Get-Sha256 $presentationSource); presentationReportSha256=(Get-Sha256 $presentationReport)
    catalogManifestSha256=(Get-Sha256 $catalogManifest); csvSha256=(Get-Sha256 $csvPath)
    savedVariablesSha256=(Get-Sha256 $saved); reloadObserved=$reloadObserved; reloadLoginCount=$reloadLoginCount
}
[IO.File]::WriteAllText((Join-Path $run 'weapon-presentation-runtime-audit-summary.json'), (($summary | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json -Depth 8
