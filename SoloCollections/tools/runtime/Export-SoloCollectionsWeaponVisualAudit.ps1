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
    if (-not $full.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full)) {
        throw "$Label must be an existing F: path: $full"
    }
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
        $character = $Value[$index]
        if ($character -ne '\') { [void]$builder.Append($character); continue }
        $index++
        if ($index -ge $Value.Length) { throw 'Incomplete Lua escape in visual audit CSV.' }
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
    throw 'Visual audit metadata or SavedVariables capture is missing.'
}
$runMetadata = Get-Content -LiteralPath $runMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($runMetadata.auditKind -ne 'visual' -or [int]$runMetadata.expected -le 0) {
    throw 'Run is not a visual weapon presentation audit.'
}
$planPath = Resolve-FPath ([string]$runMetadata.visualSamplePlan) 'VisualSamplePlan'
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plan.kind -ne 'SoloCollectionsWeaponPresentationVisualSamplePlan' -or [int]$plan.sampleCount -ne [int]$runMetadata.expected) {
    throw 'Visual sample plan identity or denominator drifted.'
}
$presentationSource = Resolve-FPath ([string]$runMetadata.presentationSource) 'PresentationSource'
if ([string]$plan.presentationSourceSha256 -ne (Get-Sha256 $presentationSource)) {
    throw 'Visual sample plan no longer binds to the production presentation source.'
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

if (-not (Read-LuaScalar 'completed') -or -not (Read-LuaScalar 'ready') -or
    -not (Read-LuaScalar 'sampleOnly') -or -not (Read-LuaScalar 'visualCapture') -or
    [int](Read-LuaScalar 'sampleCount') -ne [int]$plan.sampleCount -or
    [string](Read-LuaScalar 'bundleId') -ne [string]$plan.bundleId -or
    [string](Read-LuaScalar 'assetPackVersion') -ne [string]$plan.assetPackVersion -or
    [string](Read-LuaScalar 'presentationSourceSha256') -ne [string]$plan.presentationSourceSha256 -or
    [string](Read-LuaScalar 'samplePlanSha256') -ne (Get-Sha256 $planPath)) {
    throw 'Visual SavedVariables do not bind to the expected production/sample contract.'
}
if ([int](Read-LuaScalar 'expected') -ne [int]$plan.sampleCount -or
    [int](Read-LuaScalar 'total') -ne [int]$plan.sampleCount -or
    [int](Read-LuaScalar 'readyCount') -ne [int]$plan.readySampleCount -or
    [int](Read-LuaScalar 'unavailableCount') -ne [int]$plan.unavailableSampleCount -or
    [int](Read-LuaScalar 'failedCount') -ne 0) {
    throw 'Visual audit terminal counts are not closed against the sample plan.'
}

$csvMatch = [regex]::Match($savedText, '(?s)\["csv"\]\s*=\s*"((?:\\.|[^"\\])*)"')
if (-not $csvMatch.Success) { throw 'Visual audit CSV payload is missing.' }
$csv = ConvertFrom-LuaString $csvMatch.Groups[1].Value
$rows = @($csv | ConvertFrom-Csv)
if ($rows.Count -ne [int]$plan.sampleCount) { throw "Visual audit row count mismatch: expected=$($plan.sampleCount) actual=$($rows.Count)" }

$expectedByAppearance = @{}
foreach ($record in @($plan.records)) {
    $appearanceId = [string][int]$record.appearanceId
    if ($expectedByAppearance.ContainsKey($appearanceId)) { throw "Duplicate sample plan appearance: $appearanceId" }
    $expectedByAppearance[$appearanceId] = $record
}
$seen = @{}
foreach ($row in $rows) {
    $appearanceId = [string][int]$row.appearanceId
    if ($seen.ContainsKey($appearanceId) -or -not $expectedByAppearance.ContainsKey($appearanceId)) {
        throw "Visual audit appearance is invalid or duplicated: $appearanceId"
    }
    $seen[$appearanceId] = $true
    $expected = $expectedByAppearance[$appearanceId]
    $expectedKinds = (@($expected.sampleKinds) -join '|')
    if ([int]$row.sourceItemId -ne [int]$expected.sourceItemId -or
        [string]$row.presentationStatus -ne [string]$expected.presentationStatus -or
        [string]$row.weaponType -ne [string]$expected.weaponType -or
        [string]$row.sampleKinds -ne $expectedKinds -or
        [string]$row.failureReason) {
        throw "Visual sample identity/result mismatch for appearance $appearanceId"
    }
    if ($expected.presentationStatus -eq 'READY') {
        if ([int]$row.syntheticDisplayId -ne [int]$expected.syntheticDisplayId -or
            (Normalize-ModelPath $row.expectedModelPath) -ne (Normalize-ModelPath $expected.modelPath) -or
            (Normalize-ModelPath $row.actualModelPath) -ne (Normalize-ModelPath $expected.modelPath) -or
            [string]$row.cardState -ne 'STANDALONE' -or [int]$row.stableTicks -lt 3 -or
            [string]::IsNullOrWhiteSpace([string]$row.poseSource)) {
            throw "READY visual sample contract failed for appearance $appearanceId"
        }
    }
    else {
        if ([int]$row.syntheticDisplayId -ne 0 -or [string]$row.actualModelPath -ne '' -or
            [string]$row.cardState -ne 'UNAVAILABLE' -or [string]$row.iconVisible -ne 'true' -or
            [string]$row.reasonVisible -ne 'true') {
            throw "UNAVAILABLE visual sample contract failed for appearance $appearanceId"
        }
    }
}
if ($seen.Count -ne $expectedByAppearance.Count) { throw 'Visual sample coverage is incomplete.' }

$screenshotsPath = Join-Path $run 'screenshots.json'
if (-not (Test-Path -LiteralPath $screenshotsPath -PathType Leaf)) { throw 'Visual screenshots manifest is missing.' }
$captures = @((Get-Content -LiteralPath $screenshotsPath -Raw -Encoding UTF8 | ConvertFrom-Json))
if ($captures.Count -ne [int]$runMetadata.expectedScreenshots) {
    throw "Visual screenshot count mismatch: expected=$($runMetadata.expectedScreenshots) actual=$($captures.Count)"
}
foreach ($capture in $captures) {
    $path = Resolve-FPath ([string]$capture.file) 'VisualScreenshot'
    if ([string]$capture.sha256 -ne (Get-Sha256 $path) -or [int64]$capture.size -ne (Get-Item -LiteralPath $path).Length) {
        throw "Visual screenshot manifest hash/size mismatch: $path"
    }
}

$csvPath = Join-Path $run 'weapon-visual-sample-audit.csv'
[IO.File]::WriteAllText($csvPath, $csv, [Text.UTF8Encoding]::new($false))
$summary = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponPresentationVisualAudit'; runId=[string]$runMetadata.runId
    bundleId=[string]$plan.bundleId; assetPackVersion=[string]$plan.assetPackVersion
    sampleCount=[int]$plan.sampleCount; ready=[int]$plan.readySampleCount; unavailable=[int]$plan.unavailableSampleCount; failed=0
    samplePlanSha256=(Get-Sha256 $planPath); presentationSourceSha256=[string]$plan.presentationSourceSha256
    csvSha256=(Get-Sha256 $csvPath); savedVariablesSha256=(Get-Sha256 $saved); screenshots=$captures.Count
}
[IO.File]::WriteAllText((Join-Path $run 'weapon-visual-sample-audit-summary.json'), (($summary | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json -Depth 8
