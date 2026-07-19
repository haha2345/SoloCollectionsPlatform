[CmdletBinding()]
param(
    [string]$CoreRoot,
    [string]$ModuleSource
)

. (Join-Path $PSScriptRoot 'BackendModuleLink.Common.ps1')

$paths = Resolve-BackendModulePaths -CoreRoot $CoreRoot -ModuleSource $ModuleSource
if (Test-Path -LiteralPath $paths.Target) {
    throw "Refusing to replace an existing module path: $($paths.Target)"
}

$null = New-Item -ItemType Junction -Path $paths.Target -Target $paths.ModuleSource
$resolvedTarget = Assert-ExpectedModuleJunction -Paths $paths

Write-Output "Installed module junction."
Write-Output "Core root: $($paths.CoreRoot)"
Write-Output "Module link: $($paths.Target)"
Write-Output "Resolved target: $resolvedTarget"
