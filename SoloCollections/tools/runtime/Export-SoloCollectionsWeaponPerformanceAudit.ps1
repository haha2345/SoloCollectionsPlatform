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
        if ($index -ge $Value.Length) { throw 'Incomplete Lua escape in SavedVariables payload.' }
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

$run = Resolve-FPath $RunRoot 'RunRoot'
$runMetadataPath = Join-Path $run 'run.json'
$saved = Join-Path $run 'SoloCollectionsWeaponPresentationAudit.lua'
$clientPerformancePath = Join-Path $run 'client-performance.json'
if (-not (Test-Path -LiteralPath $runMetadataPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $saved -PathType Leaf) -or
    -not (Test-Path -LiteralPath $clientPerformancePath -PathType Leaf)) {
    throw 'Performance audit metadata, SavedVariables capture, or client-performance capture is missing.'
}

$runMetadata = Get-Content -LiteralPath $runMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$runMetadata.auditKind -ne 'performance') { throw 'RunRoot is not a performance audit.' }
$expected = [int]$runMetadata.expected
$rounds = [int]$runMetadata.performanceRounds
if ($expected -le 0 -or $rounds -lt 2) { throw 'Performance audit must contain a positive catalog and at least two rounds.' }

# First retain the existing terminal-contract verifier: performance evidence is
# meaningful only if the full production wardrobe scan itself is closed.
$runtimeExporter = Join-Path $PSScriptRoot 'Export-SoloCollectionsWeaponPresentationAudit.ps1'
& $runtimeExporter -RunRoot $run
if (-not $?) { throw 'Base runtime-audit export failed.' }

$savedText = Get-Content -LiteralPath $saved -Raw -Encoding UTF8
function Read-LuaScalar {
    param([Parameter(Mandatory = $true)][string]$Name)
    $match = [regex]::Match($savedText, ('\["' + [regex]::Escape($Name) + '"\]\s*=\s*([^,\r\n]+)'))
    if (-not $match.Success) { throw "SavedVariables field is missing: $Name" }
    $value = $match.Groups[1].Value.Trim()
    if ($value -eq 'true') { return $true }
    if ($value -eq 'false') { return $false }
    if ($value -match '^\d+(?:\.\d+)?$') { return [double]$value }
    if ($value -match '^"(.*)"$') { return $Matches[1] }
    throw "Unsupported SavedVariables scalar: $Name=$value"
}
function Read-LuaString {
    param([Parameter(Mandatory = $true)][string]$Name)
    $match = [regex]::Match($savedText, ('(?s)\["' + [regex]::Escape($Name) + '"\]\s*=\s*"((?:\\.|[^"\\])*)"'))
    if (-not $match.Success) { throw "SavedVariables string field is missing: $Name" }
    return ConvertFrom-LuaString $match.Groups[1].Value
}

if (-not (Read-LuaScalar 'performanceMode') -or [int](Read-LuaScalar 'performanceRoundsRequested') -ne $rounds -or
    [int](Read-LuaScalar 'performanceRoundsCompleted') -ne $rounds -or [int](Read-LuaScalar 'cardPoolSize') -ne 18 -or
    [double](Read-LuaScalar 'modelWindowSeconds') -gt 3.0 -or [int](Read-LuaScalar 'stableTicksRequired') -lt 3) {
    throw 'SavedVariables performance contract is incomplete or unbounded.'
}

$pageCsv = Read-LuaString 'performancePageCsv'
$roundCsv = Read-LuaString 'performanceRoundCsv'
$filterCsv = Read-LuaString 'performanceFilterCsv'
$pageRows = @($pageCsv | ConvertFrom-Csv)
$roundRows = @($roundCsv | ConvertFrom-Csv)
$filterRows = @($filterCsv | ConvertFrom-Csv)
$pagesPerRound = [int][Math]::Ceiling($expected / 18.0)
if ($pageRows.Count -ne ($pagesPerRound * $rounds) -or $roundRows.Count -ne $rounds -or $filterRows.Count -ne 4 -or
    [int](Read-LuaScalar 'performanceFilterScenarioCount') -ne 4) {
    throw "Performance metric coverage drift: pages=$($pageRows.Count) rounds=$($roundRows.Count) filters=$($filterRows.Count)"
}

foreach ($row in $pageRows) {
    if ([int]$row.recordCount -le 0 -or [int]$row.recordCount -gt 18 -or [int]$row.poolSize -ne 18 -or
        [int]$row.totalOnUpdateCount -lt 0 -or [int]$row.totalOnUpdateCount -gt 36 -or
        [int]$row.generation -le 0 -or [int]$row.loadMilliseconds -lt 0 -or [int]$row.loadMilliseconds -gt 3000) {
        throw "Performance page metric violates bounded pool/timeout contract: round=$($row.round) page=$($row.page)"
    }
}
foreach ($round in $roundRows) {
    if ([int]$round.pageCount -ne $pagesPerRound -or [double]$round.luaMemoryStartKb -le 0 -or
        [double]$round.luaMemoryEndKb -le 0 -or [double]$round.luaMemoryPeakKb -lt [double]$round.luaMemoryEndKb) {
        throw "Performance round metric is incomplete: round=$($round.round)"
    }
}
foreach ($filter in $filterRows) {
    if ([string]$filter.slot -notin @('MAINHAND', 'OFFHAND') -or [int]$filter.page -ne 2 -or
        [int]$filter.recordCount -le 0 -or [int]$filter.recordCount -gt 18 -or [int]$filter.poolSize -ne 18 -or
        [int]$filter.totalOnUpdateCount -lt 0 -or [int]$filter.totalOnUpdateCount -gt 36 -or
        [int]$filter.generation -le 0 -or [int]$filter.generationDelta -lt 2 -or
        [string]$filter.crossContamination -ne 'false' -or [int]$filter.loadMilliseconds -gt 3000) {
        throw "Rapid filter/page generation contract failed: $($filter.scenario)"
    }
}

$baseline = $roundRows | Where-Object { [int]$_.round -eq 1 } | Select-Object -First 1
$second = $roundRows | Where-Object { [int]$_.round -eq 2 } | Select-Object -First 1
if (-not $baseline -or -not $second) { throw 'Performance baseline or second round is missing.' }
if ([double]$second.luaMemoryPeakKb -gt ([double]$baseline.luaMemoryPeakKb * 1.20) -or
    [double]$second.luaMemoryEndKb -gt ([double]$baseline.luaMemoryEndKb * 1.20)) {
    throw 'Second-round Lua memory exceeds the first-round baseline by more than 20 percent.'
}

$clientPerformance = Get-Content -LiteralPath $clientPerformancePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $clientPerformance.productionSavedVariablesRestored -or [int64]$clientPerformance.workingSetBytes -le 0 -or
    [int64]$clientPerformance.privateMemoryBytes -le 0 -or @($clientPerformance.installedPacks).Count -lt 2) {
    throw 'Client memory, installed-pack metrics, or SavedVariables restoration evidence is missing.'
}
$assetPackBytes = 0L
foreach ($pack in @($clientPerformance.installedPacks)) {
    if ([int64]$pack.sizeBytes -le 0 -or [string]::IsNullOrWhiteSpace([string]$pack.sha256)) {
        throw 'Installed pack metric is invalid.'
    }
    $assetPackBytes += [int64]$pack.sizeBytes
}

$pagePath = Join-Path $run 'weapon-presentation-performance-pages.csv'
$roundPath = Join-Path $run 'weapon-presentation-performance-rounds.csv'
$filterPath = Join-Path $run 'weapon-presentation-performance-filters.csv'
[IO.File]::WriteAllText($pagePath, $pageCsv, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($roundPath, $roundCsv, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($filterPath, $filterCsv, [Text.UTF8Encoding]::new($false))
$firstPage = $pageRows | Where-Object { [int]$_.round -eq 1 -and [int]$_.page -eq 1 } | Select-Object -First 1
$summary = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponPresentationPerformanceAudit'; runId=[string]$runMetadata.runId
    expected=$expected; rounds=$rounds; pagesPerRound=$pagesPerRound; totalPageMeasurements=$pageRows.Count; rapidFilterScenarios=$filterRows.Count
    fixedCardPool=18; maxObservedOnUpdateCount=([int](($pageRows | Measure-Object -Property totalOnUpdateCount -Maximum).Maximum))
    firstPageLoadMilliseconds=[int]$firstPage.loadMilliseconds
    firstRoundLuaPeakKb=[double]$baseline.luaMemoryPeakKb; secondRoundLuaPeakKb=[double]$second.luaMemoryPeakKb
    firstRoundLuaEndKb=[double]$baseline.luaMemoryEndKb; secondRoundLuaEndKb=[double]$second.luaMemoryEndKb
    luaMemoryLimitPercent=20; modelReadyTimeoutSeconds=[double](Read-LuaScalar 'modelWindowSeconds')
    stableTicksRequired=[int](Read-LuaScalar 'stableTicksRequired')
    clientWorkingSetBytes=[int64]$clientPerformance.workingSetBytes; clientPrivateMemoryBytes=[int64]$clientPerformance.privateMemoryBytes
    clientVirtualMemoryBytes=[int64]$clientPerformance.virtualMemoryBytes; loginAndAuditElapsedMilliseconds=[int]$clientPerformance.loginAndAuditElapsedMilliseconds
    installedAssetPackBytes=$assetPackBytes; installedPacks=@($clientPerformance.installedPacks)
    productionSavedVariablesRestoredSha256=[string]$clientPerformance.productionSavedVariablesRestoredSha256
    pageCsvSha256=(Get-Sha256 $pagePath); roundCsvSha256=(Get-Sha256 $roundPath); filterCsvSha256=(Get-Sha256 $filterPath)
}
$summaryPath = Join-Path $run 'weapon-presentation-performance-summary.json'
[IO.File]::WriteAllText($summaryPath, (($summary | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json -Depth 8
