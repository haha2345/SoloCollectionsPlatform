[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientRoot,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][Security.SecureString]$Password,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][string]$AssetInstallationManifest,
    [ValidateSet('cold', 'hot', 'reload')][string]$CacheState,
    [ValidateSet('presentation', 'visual', 'performance')][string]$AuditKind = 'presentation',
    [string]$VisualSamplePlan,
    [ValidateRange(1, 3)][int]$PerformanceRounds = 2,
    [ValidatePattern('^[A-Za-z]{4}$')][string]$WdbLocale = 'zhCN',
    [string]$ColdWdbBackupRoot,
    [string]$ExecutableName = 'Wow-SoloCam-PoC.exe',
    [Parameter(Mandatory = $true)][string]$LoginScript
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-PathChecked {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label, [bool]$MustExist = $true)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "$Label must be an absolute path: $Path" }
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) { throw "$Label cannot contain wildcards: $Path" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($full.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must not target C: $full" }
    if ($MustExist -and -not (Test-Path -LiteralPath $full)) { throw "$Label is missing: $full" }
    return $full
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-ProductionAddonMatchesSource {
    param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Installed)
    foreach ($relative in @(
        'Core\Catalog.lua',
        'UI\Wardrobe.lua',
        'Data\Generated\Catalog.lua',
        'Data\Generated\IdentityRegistry.lua'
    )) {
        $sourceFile = Join-Path $Source $relative
        $installedFile = Join-Path $Installed $relative
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf) -or -not (Test-Path -LiteralPath $installedFile -PathType Leaf)) {
            throw "Production AddOn verification file is missing: $relative"
        }
        if ((Get-Sha256 $sourceFile) -ne (Get-Sha256 $installedFile)) {
            throw "Client SoloCollections AddOn does not match the audited source: $relative"
        }
    }
}

$repo = Resolve-PathChecked (Join-Path $PSScriptRoot '..\..') 'Repository'
$client = Resolve-PathChecked $ClientRoot 'ClientRoot'
$evidence = Resolve-PathChecked $EvidenceRoot 'EvidenceRoot' $false
$installManifestPath = Resolve-PathChecked $AssetInstallationManifest 'AssetInstallationManifest'
$login = Resolve-PathChecked $LoginScript 'LoginScript'
$visualSamplePlanPath = $null
if ($AuditKind -eq 'visual') {
    if ([string]::IsNullOrWhiteSpace($VisualSamplePlan)) { throw 'VisualSamplePlan is required for a visual audit.' }
    $visualSamplePlanPath = Resolve-PathChecked $VisualSamplePlan 'VisualSamplePlan'
}
if (-not $repo.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase) -or -not $evidence.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Repository and EvidenceRoot must be on F:.'
}
$processName = [IO.Path]::GetFileNameWithoutExtension($ExecutableName)
$executable = Join-Path $client $ExecutableName
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Client executable is missing: $executable" }
if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { throw "$processName is already running" }

$presentationSource = Join-Path $repo 'catalog\source\appearance_presentations.json'
$presentationReport = Join-Path $repo 'catalog\generated\appearance-presentation-report.json'
$catalogManifest = Join-Path $repo 'catalog\generated\catalog-manifest.json'
foreach ($path in @($presentationSource, $presentationReport, $catalogManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Presentation contract input is missing: $path" }
}
$presentation = Get-Content -LiteralPath $presentationSource -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedBundleId = [string]$presentation.assetBundle.bundleId
$expectedAssetPackVersion = [string]$presentation.assetPackVersion
if ([string]::IsNullOrWhiteSpace($expectedBundleId) -or [string]::IsNullOrWhiteSpace($expectedAssetPackVersion)) {
    throw 'Presentation source has no bundle/version identity.'
}

$installManifest = Get-Content -LiteralPath $installManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($installManifest.kind -ne 'SoloCollectionsWeaponShadowInstallation' -or $installManifest.status -ne 'INSTALLED' -or
    [string]$installManifest.bundleId -ne $expectedBundleId) {
    throw 'Installed MPQ manifest does not match the production presentation bundle.'
}
foreach ($record in @($installManifest.records)) {
    $target = [IO.Path]::GetFullPath([string]$record.target)
    if (-not $target.StartsWith($client + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (Get-Sha256 $target) -ne [string]$record.installedSha256) {
        throw "Installed MPQ verification failed: $target"
    }
}

$sourceAddon = Join-Path $repo 'addon\SoloCollections'
$installedAddon = Join-Path $client 'Interface\AddOns\SoloCollections'
Assert-ProductionAddonMatchesSource -Source $sourceAddon -Installed $installedAddon

$runPrefix = if ($AuditKind -eq 'visual') {
    'stage8-weapon-visual-' + $CacheState
} elseif ($AuditKind -eq 'performance') {
    'stage8-wardrobe-performance-' + $CacheState
} else {
    'stage8-wardrobe-runtime-' + $CacheState
}
$runId = $runPrefix + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runRoot = Join-Path $evidence $runId
if (Test-Path -LiteralPath $runRoot) { throw "Audit run path already exists: $runRoot" }
$generatedRoot = Join-Path $runRoot 'generated'
$cleanupRoot = Join-Path $runRoot 'client-cleanup'
New-Item -ItemType Directory -Force -Path $generatedRoot, $cleanupRoot | Out-Null
$coldWdbBackup = $null
if ($CacheState -eq 'cold') {
    $coldWdbBackup = if ([string]::IsNullOrWhiteSpace($ColdWdbBackupRoot)) {
        Join-Path $runRoot 'wdb-cold-cache'
    }
    else {
        Resolve-PathChecked $ColdWdbBackupRoot 'ColdWdbBackupRoot' $false
    }
    $coldWdbBackup = [IO.Path]::GetFullPath($coldWdbBackup).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $coldWdbBackup.StartsWith('F:\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "ColdWdbBackupRoot must be on F:: $coldWdbBackup"
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($ColdWdbBackupRoot)) {
    throw 'ColdWdbBackupRoot is only valid when CacheState is cold.'
}
$data = Join-Path $generatedRoot 'Data.lua'
$generator = Join-Path $repo 'tools\runtime\New-WeaponPresentationAuditData.py'
if ($AuditKind -eq 'visual') {
    & python $generator --source $presentationSource --report $presentationReport --catalog-manifest $catalogManifest `
        --sample-plan $visualSamplePlanPath --output $data --cache-state $CacheState --auto-logout --auto-logout-delay 8
    if ($LASTEXITCODE -ne 0) { throw 'Weapon visual audit data generation failed.' }
    & python $generator --source $presentationSource --report $presentationReport --catalog-manifest $catalogManifest `
        --sample-plan $visualSamplePlanPath --output $data --cache-state $CacheState --auto-logout --auto-logout-delay 8 --check
    if ($LASTEXITCODE -ne 0) { throw 'Weapon visual audit data check failed.' }
    $visualPlan = Get-Content -LiteralPath $visualSamplePlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($visualPlan.kind -ne 'SoloCollectionsWeaponPresentationVisualSamplePlan' -or [int]$visualPlan.sampleCount -le 0) {
        throw 'Visual sample plan identity or sample count is invalid.'
    }
    $expected = [int]$visualPlan.sampleCount
    $expectedScreenshots = [int][Math]::Ceiling($expected / 18.0)
}
elseif ($AuditKind -eq 'performance') {
    & python $generator --source $presentationSource --report $presentationReport --catalog-manifest $catalogManifest `
        --performance-rounds $PerformanceRounds --output $data --cache-state $CacheState --auto-logout --auto-logout-delay 8
    if ($LASTEXITCODE -ne 0) { throw 'Weapon performance audit data generation failed.' }
    & python $generator --source $presentationSource --report $presentationReport --catalog-manifest $catalogManifest `
        --performance-rounds $PerformanceRounds --output $data --cache-state $CacheState --auto-logout --auto-logout-delay 8 --check
    if ($LASTEXITCODE -ne 0) { throw 'Weapon performance audit data check failed.' }
    $expected = [int]$presentation.publicAppearanceCount
    $expectedScreenshots = 0
}
else {
    & python $generator --source $presentationSource --report $presentationReport --catalog-manifest $catalogManifest `
        --output $data --cache-state $CacheState --auto-logout --auto-logout-delay 8
    if ($LASTEXITCODE -ne 0) { throw 'Weapon presentation audit data generation failed.' }
    & python $generator --source $presentationSource --report $presentationReport --catalog-manifest $catalogManifest `
        --output $data --cache-state $CacheState --auto-logout --auto-logout-delay 8 --check
    if ($LASTEXITCODE -ne 0) { throw 'Weapon presentation audit data check failed.' }
    $expected = [int]$presentation.publicAppearanceCount
    $expectedScreenshots = 0
}

$auditSource = Join-Path $repo 'tools\runtime\SoloCollectionsWeaponPresentationAudit'
$auditTarget = Join-Path $client 'Interface\AddOns\SoloCollectionsWeaponPresentationAudit'
$saved = Join-Path $client "WTF\Account\$($Account.ToUpperInvariant())\SavedVariables\SoloCollectionsWeaponPresentationAudit.lua"
$screenshots = Join-Path $client 'Screenshots'
$productionSaved = Join-Path $client "WTF\Account\$($Account.ToUpperInvariant())\SavedVariables\SoloCollections.lua"
$productionSavedBackup = Join-Path $runRoot 'SoloCollections.before.lua'
$productionSavedAfter = Join-Path $runRoot 'SoloCollections.after.lua'
$productionSavedExisted = Test-Path -LiteralPath $productionSaved -PathType Leaf
$productionSavedBeforeHash = $null
if (-not $productionSavedExisted) {
    throw "Production SoloCollections SavedVariables must exist for an isolated audit: $productionSaved"
}
$productionSavedBeforeHash = Get-Sha256 $productionSaved
Copy-Item -LiteralPath $productionSaved -Destination $productionSavedBackup -Force
$beforeScreenshots = @{}
if ($AuditKind -eq 'visual' -and (Test-Path -LiteralPath $screenshots -PathType Container)) {
    Get-ChildItem -LiteralPath $screenshots -File | ForEach-Object { $beforeScreenshots[$_.FullName] = $true }
}
if (Test-Path -LiteralPath $auditTarget) { throw "Temporary audit AddOn already exists; ownership is unknown: $auditTarget" }
if (Test-Path -LiteralPath $saved) { throw "Temporary audit SavedVariables already exists; ownership is unknown: $saved" }
Copy-Item -LiteralPath $auditSource -Destination $auditTarget -Recurse
Copy-Item -LiteralPath $data -Destination (Join-Path $auditTarget 'Data.lua') -Force
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved) | Out-Null
[IO.File]::WriteAllText($saved, "SoloCollectionsWeaponPresentationAuditDB = {`r`n`t[`"requested`"] = true,`r`n`t[`"runId`"] = `"$runId`",`r`n}`r`n", [Text.UTF8Encoding]::new($false))

$run = [ordered]@{
    runId=$runId; auditKind=$AuditKind; bundleId=$expectedBundleId; assetPackVersion=$expectedAssetPackVersion; cacheState=$CacheState
    expected=$expected; clientRoot=$client; executable=$ExecutableName; account=$Account.ToUpperInvariant()
    assetInstallationManifest=$installManifestPath; presentationSource=$presentationSource; presentationReport=$presentationReport
    catalogManifest=$catalogManifest; generatedData=$data; savedVariables=$saved; visualSamplePlan=$visualSamplePlanPath
    expectedScreenshots=$expectedScreenshots; performanceRounds=if ($AuditKind -eq 'performance') { $PerformanceRounds } else { 0 }
    wdbLocale=$WdbLocale; coldWdbBackupRoot=$coldWdbBackup
    productionSavedVariables=$productionSaved; productionSavedVariablesExisted=$productionSavedExisted
    productionSavedVariablesBeforeHash=$productionSavedBeforeHash; startedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $runRoot 'run.json'), (($run | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

if (-not ('SoloCollectionsWeaponPresentationAudit.EnterKey' -as [type])) {
    $compileTemp = Join-Path $runRoot '.compile'
    New-Item -ItemType Directory -Force -Path $compileTemp | Out-Null
    $oldTemp = $env:TEMP; $oldTmp = $env:TMP
    try {
        $env:TEMP = $compileTemp; $env:TMP = $compileTemp
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
namespace SoloCollectionsWeaponPresentationAudit {
  public static class EnterKey {
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    public static void Press(IntPtr window) {
      ShowWindowAsync(window, 9);
      if (!SetForegroundWindow(window)) throw new InvalidOperationException("Cannot focus WoW window.");
      Thread.Sleep(300);
      keybd_event(0x0D, 0, 0, UIntPtr.Zero); keybd_event(0x0D, 0, 2, UIntPtr.Zero);
    }
  }
}
'@
    }
    finally { $env:TEMP = $oldTemp; $env:TMP = $oldTmp }
}

$process = $null
$launchStartedAt = $null
$coldWdbPrepared = $false
$coldWdbRestored = $false
$backupWdbScript = Join-Path $PSScriptRoot 'Backup-ClientWdb.ps1'
$restoreWdbScript = Join-Path $PSScriptRoot 'Restore-ClientWdb.ps1'
$clientPerformance = [ordered]@{
    schemaVersion=1; kind='SoloCollectionsWeaponPresentationClientPerformance'; auditKind=$AuditKind
    cacheState=$CacheState; launchStartedUtc=$null; auditCompletedUtc=$null; loginAndAuditElapsedMilliseconds=$null
    workingSetBytes=$null; privateMemoryBytes=$null; virtualMemoryBytes=$null
    wdbLocale=$WdbLocale; coldWdbBackupRoot=$coldWdbBackup; coldWdbRestored=$false
    installedPacks=@($installManifest.records | ForEach-Object {
        $target = [IO.Path]::GetFullPath([string]$_.target)
        [ordered]@{ role=[string]$_.role; target=$target; sizeBytes=(Get-Item -LiteralPath $target).Length; sha256=(Get-Sha256 $target) }
    })
}
try {
    if ($CacheState -eq 'cold') {
        & $backupWdbScript -ClientRoot $client -Locale $WdbLocale -BackupRoot $coldWdbBackup
        if (-not $?) { throw 'Cold WDB backup preparation failed.' }
        $coldWdbPrepared = $true
    }
    $launchStartedAt = [DateTime]::UtcNow
    $clientPerformance.launchStartedUtc = $launchStartedAt.ToString('o')
    & $login -ClientPath $client -ExecutableName $ExecutableName -Account $Account -Password $Password -LoginReadyDelaySeconds 3
    Start-Sleep -Seconds 7
    $process = Get-Process -Name $processName -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
    [SoloCollectionsWeaponPresentationAudit.EnterKey]::Press($process.MainWindowHandle)
    # A performance audit deliberately walks the complete catalogue more than once.
    # Budget every requested pass so the launcher cannot report a false timeout while
    # the second baseline scan is still making progress.
    $pagePasses = [Math]::Ceiling($expected / 18)
    $auditPasses = if ($AuditKind -eq 'performance') { $PerformanceRounds } else { 1 }
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(300, ($pagePasses * 4 * $auditPasses) + 240))
    do {
        Start-Sleep -Seconds 5
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
        if (-not $process -or $process.HasExited) { throw 'Client exited before the production wardrobe audit completed.' }
        $savedText = if (Test-Path -LiteralPath $saved -PathType Leaf) { Get-Content -LiteralPath $saved -Raw -Encoding UTF8 } else { '' }
        if ($savedText -match '\["completed"\]\s*=\s*true') { break }
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($savedText -notmatch '\["completed"\]\s*=\s*true') { throw 'Weapon presentation audit did not complete before its deadline.' }
    $process.Refresh()
    $auditCompletedAt = [DateTime]::UtcNow
    $clientPerformance.auditCompletedUtc = $auditCompletedAt.ToString('o')
    $clientPerformance.loginAndAuditElapsedMilliseconds = [int][Math]::Round(($auditCompletedAt - $launchStartedAt).TotalMilliseconds)
    $clientPerformance.workingSetBytes = [int64]$process.WorkingSet64
    $clientPerformance.privateMemoryBytes = [int64]$process.PrivateMemorySize64
    $clientPerformance.virtualMemoryBytes = [int64]$process.VirtualMemorySize64
    Start-Sleep -Seconds 2
    Copy-Item -LiteralPath $saved -Destination (Join-Path $runRoot 'SoloCollectionsWeaponPresentationAudit.lua') -Force
}
finally {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000) | Out-Null
    }
    if ($coldWdbPrepared) {
        & $restoreWdbScript -ClientRoot $client -Locale $WdbLocale -BackupRoot $coldWdbBackup
        if (-not $?) { throw 'Cold WDB restoration failed.' }
        $coldWdbRestored = $true
    }
    if (Test-Path -LiteralPath $auditTarget) {
        Move-Item -LiteralPath $auditTarget -Destination (Join-Path $cleanupRoot 'SoloCollectionsWeaponPresentationAudit')
    }
    if (Test-Path -LiteralPath $saved) {
        Move-Item -LiteralPath $saved -Destination (Join-Path $cleanupRoot 'SoloCollectionsWeaponPresentationAudit.lua')
    }
    if (Test-Path -LiteralPath $productionSaved -PathType Leaf) {
        Copy-Item -LiteralPath $productionSaved -Destination $productionSavedAfter -Force
    }
    if (-not (Test-Path -LiteralPath $productionSavedBackup -PathType Leaf) -or
        (Get-Sha256 $productionSavedBackup) -ne $productionSavedBeforeHash) {
        throw 'Production SavedVariables backup integrity check failed before restoration.'
    }
    Copy-Item -LiteralPath $productionSavedBackup -Destination $productionSaved -Force
    if ((Get-Sha256 $productionSaved) -ne $productionSavedBeforeHash) {
        throw 'Production SavedVariables did not restore to its pre-audit hash.'
    }
    $clientPerformance.productionSavedVariablesRestored = $true
    $clientPerformance.productionSavedVariablesRestoredSha256 = $productionSavedBeforeHash
    $clientPerformance.coldWdbRestored = $coldWdbRestored
    [IO.File]::WriteAllText((Join-Path $runRoot 'client-performance.json'), (($clientPerformance | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
if ($AuditKind -eq 'visual') {
    $newScreenshots = @()
    if (Test-Path -LiteralPath $screenshots -PathType Container) {
        $newScreenshots = @(Get-ChildItem -LiteralPath $screenshots -File |
            Where-Object { -not $beforeScreenshots.ContainsKey($_.FullName) } |
            Sort-Object LastWriteTime)
    }
    if ($newScreenshots.Count -ne $expectedScreenshots) {
        throw "Weapon visual audit screenshot count mismatch: expected=$expectedScreenshots actual=$($newScreenshots.Count)"
    }
    $captureRoot = Join-Path $runRoot 'screenshots'
    New-Item -ItemType Directory -Force -Path $captureRoot | Out-Null
    $captures = @()
    $index = 0
    foreach ($screenshot in $newScreenshots) {
        $index++
        $destination = Join-Path $captureRoot ('weapon-visual-sample-{0:D2}{1}' -f $index, $screenshot.Extension.ToLowerInvariant())
        Move-Item -LiteralPath $screenshot.FullName -Destination $destination
        $captures += [ordered]@{ index=$index; file=$destination; sha256=(Get-Sha256 $destination); size=(Get-Item -LiteralPath $destination).Length }
    }
    [IO.File]::WriteAllText((Join-Path $runRoot 'screenshots.json'), (($captures | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
Write-Host "run_root=$runRoot"
Write-Host "expected=$expected"
