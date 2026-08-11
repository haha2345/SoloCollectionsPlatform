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
if (Test-Path -LiteralPath $destinationPath) {
    [IO.Directory]::Delete($destinationPath, $true)
}
[IO.Directory]::CreateDirectory($destinationPath) | Out-Null
Get-ChildItem -LiteralPath $sourcePath -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destinationPath -Recurse -Force
}
Write-Output "Synced SoloCollections: $sourcePath -> $destinationPath"
