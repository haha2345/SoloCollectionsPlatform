[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][Security.SecureString]$Password,
    [Parameter(Mandatory = $true)][string]$StageRoot,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [string]$ExecutableName = 'Wow-SoloCam-PoC.exe',
    [Parameter(Mandatory = $true)][string]$LoginScript
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-PathChecked {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label, [bool]$MustExist = $true)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label must be an absolute path: $Path" }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must not target C: $full" }
    if ($MustExist -and -not (Test-Path -LiteralPath $full)) { throw "$Label is missing: $full" }
    return $full.TrimEnd([IO.Path]::DirectorySeparatorChar)
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$client = Resolve-PathChecked $ClientRoot 'ClientRoot'
$stage = Resolve-PathChecked $StageRoot 'StageRoot'
$evidence = Resolve-PathChecked $EvidenceRoot 'EvidenceRoot' $false
$login = Resolve-PathChecked $LoginScript 'LoginScript'
if (-not $stage.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase) -or -not $evidence.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'StageRoot and EvidenceRoot must be on F:.'
}
$stageManifestPath = Join-Path $stage 'weapon-bundle-manifest.json'
if (-not (Test-Path -LiteralPath $stageManifestPath -PathType Leaf)) { throw "Stage manifest is missing: $stageManifestPath" }
$stageManifest = Get-Content -LiteralPath $stageManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($stageManifest.kind -ne 'SoloCollectionsWeaponBundleStage' -or [string]::IsNullOrWhiteSpace([string]$stageManifest.bundleId)) {
    throw 'Stage manifest identity is invalid.'
}
$processName = [IO.Path]::GetFileNameWithoutExtension($ExecutableName)
if (-not (Test-Path -LiteralPath (Join-Path $client $ExecutableName) -PathType Leaf)) { throw "Client executable is missing: $ExecutableName" }
if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { throw "$processName is already running" }

$runId = 'stage7-shadow-audit-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runRoot = Join-Path $evidence $runId
$generatedRoot = Join-Path $runRoot 'generated'
$cleanupRoot = Join-Path $runRoot 'client-cleanup'
New-Item -ItemType Directory -Force -Path $generatedRoot, $cleanupRoot | Out-Null
$data = Join-Path $generatedRoot 'Data.lua'
python (Join-Path $repo 'tools\runtime\New-WeaponShadowAuditData.py') --stage $stage --output $data --auto-logout --auto-logout-delay 8
if ($LASTEXITCODE -ne 0) { throw 'Weapon shadow audit data generation failed.' }
$expected = ([regex]::Matches((Get-Content -LiteralPath $data -Raw -Encoding UTF8), 'appearanceId\s*=')).Count
if ($expected -le 0) { throw 'Generated shadow audit has no records.' }

$source = Join-Path $repo 'tools\runtime\SoloCollectionsWeaponShadowAudit'
$target = Join-Path $client 'Interface\AddOns\SoloCollectionsWeaponShadowAudit'
$saved = Join-Path $client "WTF\Account\$($Account.ToUpperInvariant())\SavedVariables\SoloCollectionsWeaponShadowAudit.lua"
if (Test-Path -LiteralPath $target) { throw "Temporary audit AddOn already exists; ownership is unknown: $target" }
if (Test-Path -LiteralPath $saved) { throw "Temporary audit SavedVariables already exists; ownership is unknown: $saved" }
Copy-Item -LiteralPath $source -Destination $target -Recurse
Copy-Item -LiteralPath $data -Destination (Join-Path $target 'Data.lua') -Force
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
[IO.File]::WriteAllText($saved, "SoloCollectionsWeaponShadowAuditDB = { requested = true }`r`n", [Text.UTF8Encoding]::new($false))
$run = [ordered]@{
    runId=$runId; bundleId=$stageManifest.bundleId; bundleStage=$stage; clientRoot=$client; executable=$ExecutableName; account=$Account.ToUpperInvariant()
    expected=$expected; generatedData=$data; savedVariables=$saved; autoLogout=$true; startedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $runRoot 'run.json'), (($run | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

$process = $null
try {
    & $login -ClientPath $client -ExecutableName $ExecutableName -Account $Account -Password $Password -LoginReadyDelaySeconds 3
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(90, $expected * 3 + 30))
    do {
        Start-Sleep -Seconds 5
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
        if (-not $process -or $process.HasExited) { throw 'Client exited before the shadow audit completed.' }
        $text = if (Test-Path -LiteralPath $saved -PathType Leaf) { Get-Content -LiteralPath $saved -Raw -Encoding UTF8 } else { '' }
        if ($text -match '\["completed"\]\s*=\s*true') { break }
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($text -notmatch '\["completed"\]\s*=\s*true') { throw 'Shadow audit did not complete before its deadline.' }
    # The temporary audit AddOn performs Logout only after it has written a
    # completed result.  SavedVariables are flushed on that client transition;
    # polling an in-memory file before logout would otherwise never observe
    # progress on a 3.3.5 client.
    Start-Sleep -Seconds 2
    Copy-Item -LiteralPath $saved -Destination (Join-Path $runRoot 'SoloCollectionsWeaponShadowAudit.lua') -Force
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000) | Out-Null
    }
    if (Test-Path -LiteralPath $target) {
        Move-Item -LiteralPath $target -Destination (Join-Path $cleanupRoot 'SoloCollectionsWeaponShadowAudit')
    }
    if (Test-Path -LiteralPath $saved) {
        Move-Item -LiteralPath $saved -Destination (Join-Path $cleanupRoot 'SoloCollectionsWeaponShadowAudit.lua')
    }
}
Write-Host "run_root=$runRoot"
Write-Host "expected=$expected"
