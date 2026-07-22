[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AddonRoot,
    [Parameter(Mandatory)][string]$ModuleRoot,
    [string]$CoreRoot = '',
    [switch]$RequireClean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
. (Join-Path $PSScriptRoot 'RoundTwoRelease.Common.ps1')

$repositories = @(Resolve-RoundTwoPath $AddonRoot, Resolve-RoundTwoPath $ModuleRoot)
if ($CoreRoot) { $repositories += Resolve-RoundTwoPath $CoreRoot }
$forbiddenExtensions = @('.exe','.dll','.mpq','.pdb','.ilk','.obj','.lib','.db','.sqlite')
$forbiddenNames = @('.env','worldserver.conf','authserver.conf','realmlist.wtf','deployment-profile.local.json')
foreach ($repo in $repositories) {
    $files = @(& git -C $repo ls-files)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed: $repo" }
    foreach ($relative in $files) {
        $name = [System.IO.Path]::GetFileName($relative).ToLowerInvariant()
        $extension = [System.IO.Path]::GetExtension($relative).ToLowerInvariant()
        if ($extension -in $forbiddenExtensions -or $name -in $forbiddenNames) { throw "Forbidden tracked artifact: $repo\$relative" }
        $path = Join-Path $repo $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $path).Length -le 4MB -and $extension -in @('.ps1','.py','.json','.md','.txt','.lua','.cpp','.h','.inc','.yml','.yaml','.xml','.dist')) {
            $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if ($text -match '(?im)^\s*(?:password|passwd|databasepassword)\s*[=:]\s*["'']?[^$<{\s][^\r\n]*$') { throw "Credential-like assignment in tracked file: $repo\$relative" }
        }
    }
    if ($RequireClean) { Assert-RoundTwoCleanTracked $repo }
    Write-Host "repository_hygiene_ok=$repo"
}
