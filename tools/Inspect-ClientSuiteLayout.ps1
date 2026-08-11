[CmdletBinding()]
param(
    [string] $SourceRoot = (Join-Path $PSScriptRoot '..\Interface\AddOns'),
    [string] $LockFile = (Join-Path $PSScriptRoot '..\upstream\suite-lock.json'),
    [switch] $VerifyLock
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expected = @('!!!ClassicAPI', 'DragonUI', 'DragonUI_Options', 'DragonUI_NewEra', 'SoloCollections')
$root = (Resolve-Path -LiteralPath $SourceRoot).Path

function Get-TreeHash([string] $Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $files = Get-ChildItem -LiteralPath $resolved -File -Recurse -Force |
            Sort-Object { [IO.Path]::GetRelativePath($resolved, $_.FullName).Replace('\', '/') }
        foreach ($file in $files) {
            $relative = [IO.Path]::GetRelativePath($resolved, $file.FullName).Replace('\', '/')
            $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $bytes = [Text.Encoding]::UTF8.GetBytes("$relative`0$fileHash`n")
            [void] $sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
        }
        [void] $sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [BitConverter]::ToString($sha.Hash).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$actual = @(Get-ChildItem -LiteralPath $root -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$expectedSorted = @($expected | Sort-Object)
if (($actual -join "`n") -ne ($expectedSorted -join "`n")) {
    throw "Expected exactly five AddOn roots: $($expected -join ', '); found: $($actual -join ', ')"
}

$lock = if ($VerifyLock) { Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json } else { $null }
$rows = foreach ($name in $expected) {
    $addon = Join-Path $root $name
    $toc = @(Get-ChildItem -LiteralPath $addon -Filter '*.toc' -File)
    if ($toc.Count -ne 1) { throw "$name must contain exactly one root-level .toc; found $($toc.Count)" }
    $nested = Join-Path $addon $name
    if (Test-Path -LiteralPath $nested -PathType Container) { throw "$name is nested one directory too deep: $nested" }
    $hash = Get-TreeHash $addon
    if ($VerifyLock) {
        $entry = @($lock.components | Where-Object addonRoot -eq $name)
        if ($entry.Count -ne 1) { throw "Lock must contain exactly one entry for $name" }
        if ($entry[0].directoryHash -ne $hash) { throw "Directory hash mismatch for $name. expected=$($entry[0].directoryHash) actual=$hash" }
    }
    [pscustomobject]@{ addon = $name; toc = $toc[0].Name; directoryHash = $hash }
}

$rows | Format-Table -AutoSize

