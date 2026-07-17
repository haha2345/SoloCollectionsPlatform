[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientDirectory,
    [string]$VcVars = $env:SOLOCOLLECTIONS_VCVARS
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SourceWow = Join-Path $ClientDirectory 'Wow.exe'
$TargetWow = Join-Path $ClientDirectory 'Wow-SoloCam-PoC.exe'
$BuiltDll = Join-Path $ProjectRoot 'build\Release\SoloCam.dll'
$TargetDll = Join-Path $ClientDirectory 'SoloCam.dll'

& (Join-Path $PSScriptRoot 'build.ps1') -VcVars $VcVars
if ($LASTEXITCODE -ne 0) {
    throw 'PoC DLL build failed.'
}

python (Join-Path $ProjectRoot 'poc_patch.py') $SourceWow $TargetWow
if ($LASTEXITCODE -ne 0) {
    throw 'PoC client copy patch failed.'
}

Copy-Item -LiteralPath $BuiltDll -Destination $TargetDll -Force

Write-Host "PoC executable: $TargetWow"
Write-Host "PoC DLL:        $TargetDll"
Write-Host 'Original Wow.exe was not modified.'
