[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ClassicAPIRepo,
    [Parameter(Mandatory)] [string] $DragonUIRepo,
    [Parameter(Mandatory)] [string] $DragonUINewEraRepo,
    [string] $ClassicAPICommit = '1ffaa484f62f225052de69dd82d97f78bf723fd7',
    [string] $DragonUICommit = '9c7e5b189f438391e3de8731b4fc62fc2a0f0839',
    [string] $DragonUINewEraCommit = '8f3d1007952abd532c6d5b736b7d43d30a9b4719'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$suite = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$stage = Join-Path $suite '.sync-staging'
if (Test-Path -LiteralPath $stage) { [IO.Directory]::Delete($stage, $true) }
[IO.Directory]::CreateDirectory((Join-Path $stage 'Interface\AddOns')) | Out-Null

function Assert-Commit([string] $Repo, [string] $Commit) {
    $actual = (& git -C $Repo rev-parse $Commit).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $Commit) { throw "Commit unavailable or mismatched in ${Repo}: $Commit" }
}
function Export-Tree([string] $Repo, [string] $Tree, [string] $Prefix, [string] $Name) {
    $archive = Join-Path $stage ($Name + '.tar')
    & git -C $Repo archive --format=tar --output=$archive --prefix=$Prefix $Tree
    if ($LASTEXITCODE -ne 0) { throw "git archive failed for $Tree" }
    & tar.exe -xf $archive -C $stage
    if ($LASTEXITCODE -ne 0) { throw "tar extraction failed for $Tree" }
}

Assert-Commit $ClassicAPIRepo $ClassicAPICommit
Assert-Commit $DragonUIRepo $DragonUICommit
Assert-Commit $DragonUINewEraRepo $DragonUINewEraCommit
Export-Tree $ClassicAPIRepo "$ClassicAPICommit`:!!!ClassicAPI" 'Interface/AddOns/!!!ClassicAPI/' 'classicapi'
Export-Tree $DragonUIRepo "$DragonUICommit`:DragonUI" 'Interface/AddOns/DragonUI/' 'dragonui'
Export-Tree $DragonUIRepo "$DragonUICommit`:DragonUI_Options" 'Interface/AddOns/DragonUI_Options/' 'dragonui-options'
Export-Tree $DragonUINewEraRepo $DragonUINewEraCommit 'Interface/AddOns/DragonUI_NewEra/' 'dragonui-newera'

foreach ($name in @('!!!ClassicAPI', 'DragonUI', 'DragonUI_Options', 'DragonUI_NewEra')) {
    $source = Join-Path $stage "Interface\AddOns\$name"
    if (-not (Get-ChildItem -LiteralPath $source -Filter '*.toc' -File)) { throw "Missing root TOC after export: $name" }
    $target = Join-Path $suite "Interface\AddOns\$name"
    if (Test-Path -LiteralPath $target) { [IO.Directory]::Delete($target, $true) }
    [IO.Directory]::Move($source, $target)
}
Write-Output 'Upstream trees synchronized. Recompute suite-lock directory hashes before committing.'
