[CmdletBinding()]
param(
    [string] $Source = (Join-Path $PSScriptRoot '..\..\SoloCollections\addon\SoloCollections'),
    [string] $Destination = (Join-Path $PSScriptRoot '..\Interface\AddOns\SoloCollections')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$destinationPath = [IO.Path]::GetFullPath($Destination)
$allowedParent = [IO.Path]::GetFullPath((Join-Path $suiteRoot 'Interface\AddOns'))
if ([IO.Path]::GetDirectoryName($destinationPath) -ne $allowedParent -or [IO.Path]::GetFileName($destinationPath) -ne 'SoloCollections') {
    throw "Destination must be the suite's exact Interface/AddOns/SoloCollections path: $destinationPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $sourcePath 'SoloCollections.toc') -PathType Leaf)) {
    throw "Source is not a SoloCollections AddOn root: $sourcePath"
}
$sourceParent = [IO.Path]::GetDirectoryName($sourcePath)
foreach ($addonName in @('SoloCollections', 'SoloCollections_WardrobeData')) {
    $addonSource = if ($addonName -eq 'SoloCollections') { $sourcePath } else { Join-Path $sourceParent $addonName }
    $addonDestination = Join-Path $allowedParent $addonName
    if (-not (Test-Path -LiteralPath (Join-Path $addonSource "$addonName.toc") -PathType Leaf)) {
        throw "Source is not a $addonName AddOn root: $addonSource"
    }
    if (Test-Path -LiteralPath $addonDestination) {
        [IO.Directory]::Delete($addonDestination, $true)
    }
    [IO.Directory]::CreateDirectory($addonDestination) | Out-Null
    Get-ChildItem -LiteralPath $addonSource -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $addonDestination -Recurse -Force
    }
    Write-Output "Synced ${addonName}: $addonSource -> $addonDestination"
}
