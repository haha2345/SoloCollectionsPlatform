[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SavedVariablesPath,
    [Parameter(Mandatory = $true)][string]$RunRoot,
    [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][int]$ExpectedCompanions,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedMappingHash
)

$ErrorActionPreference = 'Stop'
$saved = [System.IO.Path]::GetFullPath($SavedVariablesPath)
$output = [System.IO.Path]::GetFullPath($RunRoot)
if ($saved.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'RuntimeAudit input and output paths must not target C drive.'
}
if (-not $output.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'RuntimeAudit output must be on F drive.'
}
if (Get-Process Wow -ErrorAction SilentlyContinue) {
    throw 'Close WoW normally before exporting RuntimeAudit SavedVariables.'
}
if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
    throw "SavedVariables file does not exist: $saved"
}

function Read-LuaScalar([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, ('\["' + [regex]::Escape($Name) + '"\]\s*=\s*([^,\r\n]+)'))
    if (-not $match.Success) {
        throw "Missing RuntimeAudit field: $Name"
    }
    $value = $match.Groups[1].Value.Trim()
    if ($value -eq 'true') { return $true }
    if ($value -eq 'false') { return $false }
    if ($value -match '^\d+$') { return [int64]$value }
    if ($value -match '^"(.*)"$') { return $Matches[1] }
    throw "Unsupported RuntimeAudit scalar for $Name`: $value"
}

function ConvertFrom-LuaString([string]$Value) {
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        if ($character -ne '\') {
            [void]$builder.Append($character)
            continue
        }
        $index++
        if ($index -ge $Value.Length) { throw 'Incomplete Lua escape in RuntimeAudit CSV.' }
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

$text = [System.IO.File]::ReadAllText($saved, [System.Text.Encoding]::UTF8)
if (-not (Read-LuaScalar $text 'completed')) {
    throw 'RuntimeAudit did not complete; refusing to publish partial evidence.'
}
$csvMatch = [regex]::Match($text, '(?s)\["csv"\]\s*=\s*"((?:\\.|[^"\\])*)"')
if (-not $csvMatch.Success) {
    throw 'RuntimeAudit CSV payload is missing or malformed.'
}
$csv = ConvertFrom-LuaString $csvMatch.Groups[1].Value
$rows = @($csv.TrimEnd("`r", "`n") -split "`r?`n")
$total = [int](Read-LuaScalar $text 'total')
$ready = [int](Read-LuaScalar $text 'readyCount')
$failed = [int](Read-LuaScalar $text 'failedCount')
if ($rows.Count -ne ($total + 1)) {
    throw "RuntimeAudit row count mismatch: rows=$($rows.Count - 1) total=$total"
}
$records = @($csv | ConvertFrom-Csv)
$mounts = @($records | Where-Object typeId -eq '10').Count
$companions = @($records | Where-Object typeId -eq '11').Count
$expectedTotal = 281 + $ExpectedCompanions
if ($mounts -ne 281 -or $companions -ne $ExpectedCompanions -or $ready -ne $expectedTotal -or $failed -ne 0) {
    throw "RuntimeAudit acceptance failed: mounts=$mounts companions=$companions ready=$ready failed=$failed"
}
if ((Read-LuaScalar $text 'mappingHash') -ne $ExpectedMappingHash) {
    throw 'RuntimeAudit mapping hash differs from the reviewed catalog.'
}
if (@($records | Where-Object { $_.previewStatus -ne 'ACCEPTED' -or $_.modelStatus -ne 'READY' }).Count -ne 0) {
    throw 'RuntimeAudit contains a non-ACCEPTED or non-READY record.'
}
if (-not (Read-LuaScalar $text 'staleGenerationDiscarded')) {
    throw 'RuntimeAudit stale generation discard probe did not pass.'
}

[System.IO.Directory]::CreateDirectory($output) | Out-Null
$savedCopy = Join-Path $output 'SoloCollectionsRuntimeAudit.lua'
$csvPath = Join-Path $output 'runtime-audit.csv'
$summaryPath = Join-Path $output 'runtime-audit-summary.json'
Copy-Item -LiteralPath $saved -Destination $savedCopy -Force
[System.IO.File]::WriteAllText($csvPath, $csv, [System.Text.UTF8Encoding]::new($false))
$summary = [ordered]@{
    runId = Read-LuaScalar $text 'runId'
    completed = $true
    total = $total
    mounts = $mounts
    companions = $companions
    mappingHash = $ExpectedMappingHash
    ready = $ready
    failed = $failed
    staleGenerationDiscarded = $true
    csvSha256 = (Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash.ToLowerInvariant()
    savedVariablesSha256 = (Get-FileHash -LiteralPath $savedCopy -Algorithm SHA256).Hash.ToLowerInvariant()
}
[System.IO.File]::WriteAllText($summaryPath,
    (($summary | ConvertTo-Json) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json
