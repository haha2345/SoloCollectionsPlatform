[CmdletBinding()]
param(
    [string] $SourceRoot = (Join-Path $PSScriptRoot '..\Interface\AddOns'),
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\build\Interface\AddOns'),
    [string] $SoloCollectionsSource = (Join-Path $PSScriptRoot '..\..\SoloCollections\addon\SoloCollections'),
    [string] $EzCollectionsSource = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

& (Join-Path $PSScriptRoot 'Sync-SoloCollections.ps1') -Source $SoloCollectionsSource
& (Join-Path $PSScriptRoot 'Inspect-ClientSuiteLayout.ps1') -SourceRoot $SourceRoot -VerifyLock

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$output = [IO.Path]::GetFullPath($OutputRoot)
$allowed = [IO.Path]::GetFullPath((Join-Path $suiteRoot 'build\Interface\AddOns'))
if ($output -ne $allowed) { throw "Output must be the suite's exact ignored build/Interface/AddOns directory: $output" }
if (Test-Path -LiteralPath $output) { [IO.Directory]::Delete($output, $true) }
[IO.Directory]::CreateDirectory($output) | Out-Null
foreach ($name in @('!!!ClassicAPI', 'DragonUI', 'DragonUI_Options', 'DragonUI_NewEra', 'SoloCollections', 'SoloCollections_WardrobeData')) {
    Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination (Join-Path $output $name) -Recurse -Force
}
if (-not [string]::IsNullOrWhiteSpace($EzCollectionsSource)) {
    & (Join-Path $PSScriptRoot 'Import-EzCollectionsUI.ps1') -Source $EzCollectionsSource
}
$inspectParameters = @{ SourceRoot = $output; VerifyLock = $true }
if (-not [string]::IsNullOrWhiteSpace($EzCollectionsSource)) {
    $inspectParameters.AllowGeneratedEzCollectionsUI = $true
}
& (Join-Path $PSScriptRoot 'Inspect-ClientSuiteLayout.ps1') @inspectParameters
Write-Output "Build ready: $output"

