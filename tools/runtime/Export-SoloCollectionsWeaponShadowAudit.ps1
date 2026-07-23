[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$run = [IO.Path]::GetFullPath($RunRoot)
if (-not $run.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) { throw "RunRoot must be on F:, got: $run" }
$runMetadata = Get-Content -LiteralPath (Join-Path $run 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$bundleStage = if ($runMetadata.PSObject.Properties.Name -contains 'bundleStage') {
    [string]$runMetadata.bundleStage
}
elseif ($runMetadata.PSObject.Properties.Name -contains 'stage') {
    # Manual client gates recorded the stage under the shorter ``stage`` name
    # before this exporter gained a summary field.  Accept that immutable
    # evidence shape instead of hiding an otherwise successful audit behind a
    # StrictMode property failure.
    [string]$runMetadata.stage
}
else {
    throw 'Run metadata is missing bundleStage/stage.'
}
$saved = Join-Path $run 'SoloCollectionsWeaponShadowAudit.lua'
if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) { throw "SavedVariables capture is missing: $saved" }
$text = Get-Content -LiteralPath $saved -Raw -Encoding UTF8
function Read-LuaScalar([string]$Name) {
    $match = [regex]::Match($text, ('\["' + [regex]::Escape($Name) + '"\]\s*=\s*([^,\r\n]+)'))
    if (-not $match.Success) { throw "SavedVariables field is missing: $Name" }
    $value = $match.Groups[1].Value.Trim()
    if ($value -eq 'true') { return $true }
    if ($value -eq 'false') { return $false }
    if ($value -match '^\d+$') { return [int]$value }
    if ($value -match '^"(.*)"$') { return $Matches[1] }
    throw "Unsupported SavedVariables scalar: $Name=$value"
}
function ConvertFrom-LuaString([string]$Value) {
    $builder = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $char = $Value[$index]
        if ($char -ne '\') { [void]$builder.Append($char); continue }
        $index++
        if ($index -ge $Value.Length) { throw 'Incomplete Lua string escape.' }
        switch ($Value[$index]) {
            'n' { [void]$builder.Append("`n") }; 'r' { [void]$builder.Append("`r") }; 't' { [void]$builder.Append("`t") }
            '\' { [void]$builder.Append('\') }; '"' { [void]$builder.Append('"') }; default { [void]$builder.Append($Value[$index]) }
        }
    }
    return $builder.ToString()
}
if (-not (Read-LuaScalar 'completed')) { throw 'Shadow audit did not complete.' }
$csvMatch = [regex]::Match($text, '(?s)\["csv"\]\s*=\s*"((?:\\.|[^"\\])*)"')
if (-not $csvMatch.Success) { throw 'Shadow audit CSV payload is missing.' }
$csv = ConvertFrom-LuaString $csvMatch.Groups[1].Value
$rows = @($csv | ConvertFrom-Csv)
$expected = [int]$runMetadata.expected
$total = [int](Read-LuaScalar 'total')
$ready = [int](Read-LuaScalar 'ready')
$failed = [int](Read-LuaScalar 'failed')
if ($expected -ne $total -or $rows.Count -ne $expected -or $ready -ne $expected -or $failed -ne 0) {
    throw "Shadow audit acceptance failed: expected=$expected total=$total rows=$($rows.Count) ready=$ready failed=$failed"
}
if (@($rows | Where-Object { $_.status -ne 'READY' }).Count -ne 0) { throw 'Shadow audit has non-READY rows.' }
$stage = [IO.Path]::GetFullPath($bundleStage)
if (-not $stage.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Bundle stage must be on F:, got: $stage"
}
$stageManifestPath = Join-Path $stage 'weapon-bundle-manifest.json'
if (-not (Test-Path -LiteralPath $stageManifestPath -PathType Leaf)) {
    throw "Stage bundle manifest is missing: $stageManifestPath"
}
$stageManifest = Get-Content -LiteralPath $stageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($stageManifest.kind -ne 'SoloCollectionsWeaponBundleStage') {
    throw 'Stage manifest is not a weapon bundle stage.'
}
$runBundleId = if ($runMetadata.PSObject.Properties.Name -contains 'bundleId') {
    [string]$runMetadata.bundleId
}
else {
    # Early manual/starter runs already bind their exact stage path.  Preserve
    # their immutable evidence by deriving the identity from that validated
    # stage instead of treating a missing redundant field as an audit failure.
    [string]$stageManifest.bundleId
}
if ([string]$stageManifest.bundleId -ne $runBundleId) {
    throw 'Audit run metadata and stage bundle manifest do not agree.'
}
# Synthetic display IDs are intentionally shared by equivalent appearances.
# Use the same explicit secondary order as New-WeaponShadowAuditData.py so
# a manifest-bounded slice cannot drift at a shared-display boundary.
$allProjection = @($stageManifest.registryProjection.records | Sort-Object -Property @{ Expression = { [int]$_.syntheticDisplayId }; Ascending = $true }, @{ Expression = { [int]$_.appearanceId }; Ascending = $true })
$projection = $allProjection
if ($runMetadata.PSObject.Properties.Name -contains 'selection') {
    $selection = $runMetadata.selection
    $startIndex = [int]$selection.startIndex
    $selectionCount = [int]$selection.count
    if ($startIndex -lt 1 -or $selectionCount -lt 1 -or ($startIndex - 1 + $selectionCount) -gt $allProjection.Count) {
        throw "Invalid audit selection: start=$startIndex count=$selectionCount total=$($allProjection.Count)"
    }
    $projection = @($allProjection | Select-Object -Skip ($startIndex - 1) -First $selectionCount)
}
if ($projection.Count -ne $expected) {
    throw "Stage registry projection count drift: expected=$expected actual=$($projection.Count)"
}
$expectedByAppearance = @{}
foreach ($record in $projection) {
    $appearanceId = [string]$record.appearanceId
    if ($expectedByAppearance.ContainsKey($appearanceId)) { throw "Duplicate stage appearance ID: $appearanceId" }
    $expectedByAppearance[$appearanceId] = $record
}
$seenAppearances = @{}
foreach ($row in $rows) {
    $appearanceId = [string]$row.appearanceId
    if ($seenAppearances.ContainsKey($appearanceId)) { throw "Audit appearance ID is not unique: $appearanceId" }
    $seenAppearances[$appearanceId] = $true
    if (-not $expectedByAppearance.ContainsKey($appearanceId)) {
        throw "Audit contains an appearance absent from the stage: $appearanceId"
    }
    $expectedRecord = $expectedByAppearance[$appearanceId]
    if ([string]$row.syntheticDisplayId -ne [string]$expectedRecord.syntheticDisplayId) {
        throw "Audit display mismatch for appearance $appearanceId"
    }
    if (-not [string]::Equals([string]$row.expectedModel, [string]$expectedRecord.modelPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$row.getModel, [string]$expectedRecord.modelPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Audit model path mismatch for appearance $appearanceId"
    }
}
if ($seenAppearances.Count -ne $expected) { throw 'Audit appearance IDs are incomplete.' }
$csvPath = Join-Path $run 'weapon-shadow-audit.csv'
[IO.File]::WriteAllText($csvPath, $csv, [Text.UTF8Encoding]::new($false))
$summary = [ordered]@{
    runId=[string]$runMetadata.runId; bundleId=$runBundleId; bundleStage=$bundleStage; expected=$expected; total=$total; ready=$ready; failed=$failed
    selectionStartIndex=if ($runMetadata.PSObject.Properties.Name -contains 'selection') { [int]$runMetadata.selection.startIndex } else { 1 }
    selectionCount=$projection.Count
    uniqueSyntheticDisplayIds=@($projection.syntheticDisplayId | Sort-Object -Unique).Count
    csvSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $csvPath).Hash.ToLowerInvariant()
    savedVariablesSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $saved).Hash.ToLowerInvariant()
}
[IO.File]::WriteAllText((Join-Path $run 'weapon-shadow-audit-summary.json'), (($summary | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json
