[CmdletBinding()]
param(
    [string] $SourceRoot = (Join-Path $PSScriptRoot '..\Interface\AddOns'),
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\build\Interface\AddOns')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& (Join-Path $PSScriptRoot 'Sync-SoloCollections.ps1')
& (Join-Path $PSScriptRoot 'Inspect-ClientSuiteLayout.ps1') -SourceRoot $SourceRoot -VerifyLock

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$output = [IO.Path]::GetFullPath($OutputRoot)
$allowed = [IO.Path]::GetFullPath((Join-Path $suiteRoot 'build\Interface\AddOns'))
if ($output -ne $allowed) { throw "Output must be the suite's exact ignored build/Interface/AddOns directory: $output" }
if (Test-Path -LiteralPath $output) { [IO.Directory]::Delete($output, $true) }
[IO.Directory]::CreateDirectory($output) | Out-Null
foreach ($name in @('!!!ClassicAPI', 'DragonUI', 'DragonUI_Options', 'DragonUI_NewEra', 'SoloCollections')) {
    Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination (Join-Path $output $name) -Recurse -Force
}
& (Join-Path $PSScriptRoot 'Inspect-ClientSuiteLayout.ps1') -SourceRoot $output -VerifyLock
Write-Output "Build ready: $output"

