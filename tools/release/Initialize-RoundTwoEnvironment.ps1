[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'RoundTwoRelease.Common.ps1')

$root = Resolve-RoundTwoPath -Path $WorkRoot -AllowMissing
if ([System.IO.Path]::GetPathRoot($root) -ne 'F:\') { throw "Round-two work root must be on F: $root" }
New-Item -ItemType Directory -Force -Path $root | Out-Null
$paths = [ordered]@{
    TEMP = Join-Path $root 'tmp'
    TMP = Join-Path $root 'tmp'
    PYTHONPYCACHEPREFIX = Join-Path $root 'pycache'
    PIP_CACHE_DIR = Join-Path $root 'pip-cache'
}
foreach ($pair in $paths.GetEnumerator()) {
    New-Item -ItemType Directory -Force -Path $pair.Value | Out-Null
    if ([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($pair.Value)) -eq 'C:\') { throw "$($pair.Key) resolved to C drive" }
    Set-Item -Path "Env:$($pair.Key)" -Value ([System.IO.Path]::GetFullPath($pair.Value))
}
$env:PYTHONDONTWRITEBYTECODE = '1'
Write-Host "round_two_work_root=$root"
foreach ($pair in $paths.GetEnumerator()) { Write-Host "$($pair.Key.ToLowerInvariant())=$($pair.Value)" }
