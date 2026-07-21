[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$client = [System.IO.Path]::GetFullPath($ClientRoot)
$output = [System.IO.Path]::GetFullPath($OutputRoot)
if ($client.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'RuntimeAudit client and output paths must not target C drive.'
}
if (Get-Process Wow -ErrorAction SilentlyContinue) {
    throw 'Close WoW before seeding RuntimeAudit SavedVariables.'
}
if (-not $output.StartsWith('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'RuntimeAudit output must be on F drive.'
}

$source = Join-Path $repoRoot 'tools\runtime\SoloCollectionsRuntimeAudit'
$target = Join-Path $client 'Interface\AddOns\SoloCollectionsRuntimeAudit'
$saved = Join-Path $client ("WTF\Account\$Account\SavedVariables\SoloCollectionsRuntimeAudit.lua")
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runRoot = Join-Path $output $runId
[System.IO.Directory]::CreateDirectory($runRoot) | Out-Null
if (Test-Path -LiteralPath $target -PathType Container) {
    Copy-Item -LiteralPath $target -Destination (Join-Path $runRoot 'previous-addon') -Recurse
}
if (Test-Path -LiteralPath $saved -PathType Leaf) {
    Copy-Item -LiteralPath $saved -Destination (Join-Path $runRoot 'previous-SavedVariables.lua')
}
[System.IO.Directory]::CreateDirectory($target) | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
$seed = "SoloCollectionsRuntimeAuditDB = {`r`n`t[`"requested`"] = true,`r`n`t[`"runId`"] = `"$runId`",`r`n}`r`n"
[System.IO.File]::WriteAllText($saved, $seed, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $runRoot 'run.json'),
    (([ordered]@{ runId = $runId; clientRoot = $client; account = $Account; savedVariables = $saved } |
        ConvertTo-Json) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
Write-Output "runId=$runId"
Write-Output "runRoot=$runRoot"
Write-Output "savedVariables=$saved"
