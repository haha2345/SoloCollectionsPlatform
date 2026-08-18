[CmdletBinding()]
param(
    [string]$CoreRoot,
    [string]$ModuleSource
)

. (Join-Path $PSScriptRoot 'BackendModuleLink.Common.ps1')

$paths = Resolve-BackendModulePaths -CoreRoot $CoreRoot -ModuleSource $ModuleSource
$resolvedTarget = Assert-ExpectedModuleJunction -Paths $paths
$coreCommit = Get-GitCommit -Repository $paths.CoreRoot
$moduleCommit = Get-GitCommit -Repository $paths.ModuleSource

Write-Output "Module junction is valid."
Write-Output "Core root: $($paths.CoreRoot)"
Write-Output "Core commit: $coreCommit"
Write-Output "Module link: $($paths.Target)"
Write-Output "Resolved target: $resolvedTarget"
Write-Output "Module commit: $moduleCommit"
