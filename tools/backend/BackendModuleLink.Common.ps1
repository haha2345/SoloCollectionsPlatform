Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Resolve-BackendModulePaths {
    param(
        [string]$CoreRoot,
        [string]$ModuleSource
    )

    $repositoryRoot = Get-NormalizedPath (Join-Path $PSScriptRoot '..\..')
    if ([string]::IsNullOrWhiteSpace($CoreRoot)) {
        $CoreRoot = Join-Path $repositoryRoot '..\..\azerothcore-wotlk'
    }
    if ([string]::IsNullOrWhiteSpace($ModuleSource)) {
        $ModuleSource = Join-Path $repositoryRoot '..\mod-solo-collections'
    }

    $resolvedCore = Get-NormalizedPath (Resolve-Path -LiteralPath $CoreRoot).Path
    $resolvedSource = Get-NormalizedPath (Resolve-Path -LiteralPath $ModuleSource).Path
    $modulesRoot = Get-NormalizedPath (Resolve-Path -LiteralPath (Join-Path $resolvedCore 'modules')).Path
    $target = Get-NormalizedPath (Join-Path $modulesRoot 'mod-solo-collections')

    if (-not (Test-Path -LiteralPath (Join-Path $resolvedCore '.git'))) {
        throw "CoreRoot is not an AzerothCore Git worktree: $resolvedCore"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource '.git'))) {
        throw "ModuleSource is not the mod-solo-collections Git worktree: $resolvedSource"
    }

    $modulesPrefix = $modulesRoot + '\'
    if (-not $target.StartsWith($modulesPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Module target escapes the Core modules directory: $target"
    }

    $sourcePrefix = $resolvedSource + '\'
    $targetPrefix = $target + '\'
    if ($target.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedSource.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedSource.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Module source and target overlap: source=$resolvedSource target=$target"
    }

    return [PSCustomObject]@{
        CoreRoot = $resolvedCore
        ModuleSource = $resolvedSource
        ModulesRoot = $modulesRoot
        Target = $target
    }
}

function Get-JunctionResolvedTarget {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Item)

    if ($Item.LinkType -ne 'Junction') {
        throw "Path is not a junction: $($Item.FullName)"
    }

    $rawTarget = @($Item.Target)[0]
    if ([string]::IsNullOrWhiteSpace($rawTarget)) {
        throw "Junction target cannot be read: $($Item.FullName)"
    }
    if (-not [System.IO.Path]::IsPathRooted($rawTarget)) {
        $rawTarget = Join-Path $Item.Parent.FullName $rawTarget
    }

    return Get-NormalizedPath (Resolve-Path -LiteralPath $rawTarget).Path
}

function Assert-ExpectedModuleJunction {
    param([Parameter(Mandatory = $true)]$Paths)

    $item = Get-Item -LiteralPath $Paths.Target -Force -ErrorAction Stop
    if (-not ($item -is [System.IO.DirectoryInfo])) {
        throw "Module target is not a directory junction: $($Paths.Target)"
    }

    $resolvedTarget = Get-JunctionResolvedTarget -Item $item
    if (-not $resolvedTarget.Equals($Paths.ModuleSource, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Junction points to an unexpected source: expected=$($Paths.ModuleSource) actual=$resolvedTarget"
    }

    return $resolvedTarget
}

function Get-GitCommit {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $commit = (& git -C $Repository rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Git commit for $Repository`: $commit"
    }
    return $commit
}
