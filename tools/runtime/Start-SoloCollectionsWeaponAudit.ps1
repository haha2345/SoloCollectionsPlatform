[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$client = [System.IO.Path]::GetFullPath($ClientRoot)
$output = [System.IO.Path]::GetFullPath($OutputRoot)
if ((Get-Process Wow -ErrorAction SilentlyContinue) -or $client.StartsWith('C:\') -or
    -not $output.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'WeaponAudit requires a closed client, non-C client root and F-drive output.'
}
$source = Join-Path $repo 'tools\runtime\SoloCollectionsWeaponAudit'
$target = Join-Path $client 'Interface\AddOns\SoloCollectionsWeaponAudit'
$saved = Join-Path $client "WTF\Account\$Account\SavedVariables\SoloCollectionsWeaponAudit.lua"
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runRoot = Join-Path $output $runId
[System.IO.Directory]::CreateDirectory($runRoot) | Out-Null
if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $runRoot 'previous-addon') -Recurse }
if (Test-Path -LiteralPath $saved) { Copy-Item -LiteralPath $saved -Destination (Join-Path $runRoot 'previous-SavedVariables.lua') }
[System.IO.Directory]::CreateDirectory($target) | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
$seed = "SoloCollectionsWeaponAuditDB = {`r`n`t[`"requested`"] = true,`r`n`t[`"runId`"] = `"$runId`",`r`n}`r`n"
[System.IO.File]::WriteAllText($saved, $seed, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $runRoot 'run.json'),
    (([ordered]@{runId=$runId; savedVariables=$saved}|ConvertTo-Json)+[Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false))
"runId=$runId"
"runRoot=$runRoot"
"savedVariables=$saved"
