[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SavedVariablesPath,
    [Parameter(Mandatory = $true)][string]$RunRoot
)

$ErrorActionPreference = 'Stop'
$saved = [System.IO.Path]::GetFullPath($SavedVariablesPath)
$output = [System.IO.Path]::GetFullPath($RunRoot)
if ($saved.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'WeaponAudit input and output paths must not target C drive.'
}
if (-not $output.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'WeaponAudit output must be on F drive.'
}
if (Get-Process Wow* -ErrorAction SilentlyContinue) {
    throw 'Close WoW normally before exporting WeaponAudit SavedVariables.'
}
if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
    throw "SavedVariables file does not exist: $saved"
}

function Read-LuaScalar([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, ('\["' + [regex]::Escape($Name) + '"\]\s*=\s*([^,\r\n]+)'))
    if (-not $match.Success) {
        throw "Missing WeaponAudit field: $Name"
    }
    $value = $match.Groups[1].Value.Trim()
    if ($value -eq 'true') { return $true }
    if ($value -eq 'false') { return $false }
    if ($value -match '^\d+$') { return [int64]$value }
    if ($value -match '^"(.*)"$') { return $Matches[1] }
    throw "Unsupported WeaponAudit scalar for $Name`: $value"
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
        if ($index -ge $Value.Length) { throw 'Incomplete Lua escape in WeaponAudit CSV.' }
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
    throw 'WeaponAudit did not complete; refusing to publish partial evidence.'
}
$csvMatch = [regex]::Match($text, '(?s)\["csv"\]\s*=\s*"((?:\\.|[^"\\])*)"')
if (-not $csvMatch.Success) {
    throw 'WeaponAudit CSV payload is missing or malformed.'
}
$csv = ConvertFrom-LuaString $csvMatch.Groups[1].Value
$records = @($csv | ConvertFrom-Csv)
$total = [int](Read-LuaScalar $text 'total')
$expected = [int](Read-LuaScalar $text 'expected')
$ready = [int](Read-LuaScalar $text 'ready')
$failed = [int](Read-LuaScalar $text 'failed')
if ($records.Count -ne $total) {
    throw "WeaponAudit row count mismatch: rows=$($records.Count) total=$total"
}
if ($total -ne 21 -or $expected -ne 21 -or $ready -ne 21 -or $failed -ne 0) {
    throw "WeaponAudit acceptance failed: total=$total expected=$expected ready=$ready failed=$failed"
}
if (@($records | Where-Object status -ne 'READY').Count -ne 0) {
    throw 'WeaponAudit contains a non-READY record.'
}
if (@($records.syntheticDisplayId | Sort-Object -Unique).Count -ne 21) {
    throw 'WeaponAudit synthetic display IDs are not unique.'
}

[System.IO.Directory]::CreateDirectory($output) | Out-Null
$savedCopy = Join-Path $output 'SoloCollectionsWeaponAudit.lua'
$csvPath = Join-Path $output 'weapon-audit.csv'
$summaryPath = Join-Path $output 'weapon-audit-summary.json'
Copy-Item -LiteralPath $saved -Destination $savedCopy -Force
[System.IO.File]::WriteAllText($csvPath, $csv, [System.Text.UTF8Encoding]::new($false))
$summary = [ordered]@{
    runId = Read-LuaScalar $text 'runId'
    completed = $true
    total = $total
    expected = $expected
    ready = $ready
    failed = $failed
    csvSha256 = (Get-FileHash -LiteralPath $csvPath -Algorithm SHA256).Hash.ToLowerInvariant()
    savedVariablesSha256 = (Get-FileHash -LiteralPath $savedCopy -Algorithm SHA256).Hash.ToLowerInvariant()
}
[System.IO.File]::WriteAllText($summaryPath,
    (($summary | ConvertTo-Json) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json
