[CmdletBinding()]
param(
    [string]$CoreRoot,
    [string]$ModuleSource
)

. (Join-Path $PSScriptRoot 'BackendModuleLink.Common.ps1')

$paths = Resolve-BackendModulePaths -CoreRoot $CoreRoot -ModuleSource $ModuleSource
$resolvedTarget = Assert-ExpectedModuleJunction -Paths $paths

# Assert-ExpectedModuleJunction proves this exact path is a junction to the
# expected repository. Directory.Delete(path, false) removes only the reparse
# point. It also avoids the PowerShell 5.1 Remove-Item junction bug and can
# never recurse into the real module worktree.
[System.IO.Directory]::Delete($paths.Target, $false)

if (Test-Path -LiteralPath $paths.Target) {
    throw "Junction still exists after removal: $($paths.Target)"
}
if (-not (Test-Path -LiteralPath $resolvedTarget)) {
    throw "Module source disappeared while removing the junction: $resolvedTarget"
}

Write-Output "Removed module junction."
Write-Output "Removed link: $($paths.Target)"
Write-Output "Preserved source: $resolvedTarget"
