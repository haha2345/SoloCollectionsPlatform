[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [string]$AddonSource = '',
    [Parameter(Mandatory = $true)][string]$AddonTarget,
    [string]$ServerLuaSource = '',
    [Parameter(Mandatory = $true)][string]$ServerLuaTarget,
    [string]$BackupRoot = '',
    [string]$StageRoot = '',
    [ValidateRange(0, 2147483647)][int]$SimulateFailureAfter = 0
)

$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($AddonSource)) {
    $AddonSource = Join-Path $RepoRoot 'addon\SoloCollections'
}
if ([string]::IsNullOrWhiteSpace($ServerLuaSource)) {
    $ServerLuaSource = Join-Path $RepoRoot 'server\ale\solo_collections.lua'
}
if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $BackupRoot = Join-Path $RepoRoot '_work\deploy\backups'
}
if ([string]::IsNullOrWhiteSpace($StageRoot)) {
    $StageRoot = Join-Path $RepoRoot '_work\deploy\staging'
}

function Test-FullyQualifiedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '^[A-Za-z]:\\') { return $true }
    if ($Path -match '^\\\\[^\\]+\\[^\\]+(?:\\|$)') { return $true }
    return $false
}

function Resolve-SafeAbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    if (-not (Test-FullyQualifiedPath $Path)) {
        throw "$Label must be a fully qualified drive or UNC path: $Path"
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function Test-PathOverlap {
    param([Parameter(Mandatory = $true)][string]$First, [Parameter(Mandatory = $true)][string]$Second)
    $a = $First.TrimEnd('\', '/')
    $b = $Second.TrimEnd('\', '/')
    if ($a.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $aWithSlash = $a + '\'
    $bWithSlash = $b + '\'
    return $aWithSlash.StartsWith($bWithSlash, [System.StringComparison]::OrdinalIgnoreCase) -or
        $bWithSlash.StartsWith($aWithSlash, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoPathOverlap {
    param([Parameter(Mandatory = $true)][array]$NamedPaths)
    for ($i = 0; $i -lt $NamedPaths.Count; $i++) {
        for ($j = $i + 1; $j -lt $NamedPaths.Count; $j++) {
            if (Test-PathOverlap $NamedPaths[$i].Path $NamedPaths[$j].Path) {
                throw "Dangerous path overlap: $($NamedPaths[$i].Name) and $($NamedPaths[$j].Name)."
            }
        }
    }
}

function Assert-NoTargetCollision {
    param([Parameter(Mandatory = $true)][string]$Target, [Parameter(Mandatory = $true)][string]$Label)
    if (Test-Path -LiteralPath $Target -PathType Container) {
        throw "Target collision: $Label is a directory: $Target"
    }
    $parent = Split-Path -Parent $Target
    while ($parent) {
        if (Test-Path -LiteralPath $parent -PathType Leaf) {
            throw "Target collision: a parent path for $Label is a file: $parent"
        }
        $next = Split-Path -Parent $parent
        if (-not $next -or $next -eq $parent) { break }
        $parent = $next
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally { $sha256.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Ensure-DirectoryActual {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        throw "Target collision: directory path is a file: $Path"
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}

$AddonSource = Resolve-SafeAbsolutePath $AddonSource 'AddOn source'
$AddonTarget = Resolve-SafeAbsolutePath $AddonTarget 'AddOn target'
$ServerLuaSource = Resolve-SafeAbsolutePath $ServerLuaSource 'Server Lua source'
$ServerLuaTarget = Resolve-SafeAbsolutePath $ServerLuaTarget 'Server Lua target'
$BackupRoot = Resolve-SafeAbsolutePath $BackupRoot 'Backup root'
$StageRoot = Resolve-SafeAbsolutePath $StageRoot 'Stage root'

if ([System.IO.Path]::GetFileName($AddonSource.TrimEnd('\')) -ne 'SoloCollections') {
    throw "AddOn source must be the SoloCollections directory: $AddonSource"
}
if ([System.IO.Path]::GetFileName($AddonTarget.TrimEnd('\')) -ne 'SoloCollections') {
    throw "AddOn target must be the SoloCollections directory: $AddonTarget"
}
if ([System.IO.Path]::GetFileName($ServerLuaSource) -ne 'solo_collections.lua' -or
    [System.IO.Path]::GetFileName($ServerLuaTarget) -ne 'solo_collections.lua') {
    throw 'Server deployment is restricted to solo_collections.lua.'
}
if (-not (Test-Path -LiteralPath $AddonSource -PathType Container)) {
    throw "Missing AddOn source directory: $AddonSource"
}
if (-not (Test-Path -LiteralPath $ServerLuaSource -PathType Leaf)) {
    throw "Missing server Lua source: $ServerLuaSource"
}

$namedPaths = @(
    [pscustomobject]@{ Name = 'AddOn source'; Path = $AddonSource },
    [pscustomobject]@{ Name = 'AddOn target'; Path = $AddonTarget },
    [pscustomobject]@{ Name = 'server Lua source'; Path = $ServerLuaSource },
    [pscustomobject]@{ Name = 'server Lua target'; Path = $ServerLuaTarget },
    [pscustomobject]@{ Name = 'backup root'; Path = $BackupRoot },
    [pscustomobject]@{ Name = 'stage root'; Path = $StageRoot }
)
Assert-NoPathOverlap $namedPaths

$sourceRootWithSlash = $AddonSource.TrimEnd('\') + '\'
$targetRootWithSlash = $AddonTarget.TrimEnd('\') + '\'
$operations = New-Object System.Collections.Generic.List[object]
$sourceFiles = Get-ChildItem -LiteralPath $AddonSource -Recurse -File |
    Sort-Object { $_.FullName.Substring($sourceRootWithSlash.Length) }
foreach ($sourceFile in $sourceFiles) {
    $relativePath = $sourceFile.FullName.Substring($sourceRootWithSlash.Length)
    $livePath = [System.IO.Path]::GetFullPath((Join-Path $AddonTarget $relativePath))
    if (-not $livePath.StartsWith($targetRootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside AddOn target: $livePath"
    }
    Assert-NoTargetCollision $livePath "AddOn file $relativePath"
    $operations.Add([pscustomobject]@{
        Kind = 'ADDON'; Status = $null; RelativePath = $relativePath
        Source = $sourceFile.FullName; Target = $livePath
        SourceHash = Get-Sha256 $sourceFile.FullName; StageSource = $null
    })
}
Assert-NoTargetCollision $ServerLuaTarget 'server Lua'
$operations.Add([pscustomobject]@{
    Kind = 'SERVER'; Status = $null; RelativePath = 'solo_collections.lua'
    Source = $ServerLuaSource; Target = $ServerLuaTarget
    SourceHash = Get-Sha256 $ServerLuaSource; StageSource = $null
})

foreach ($operation in $operations) {
    if (Test-Path -LiteralPath $operation.Target -PathType Leaf) {
        if ($operation.SourceHash -eq (Get-Sha256 $operation.Target)) { $operation.Status = 'UNCHANGED' }
        else { $operation.Status = 'UPDATE' }
    }
    else { $operation.Status = 'CREATE' }
    Write-Output ("{0,-9} {1} [{2}]" -f $operation.Status, $operation.RelativePath, $operation.Kind)
}

$createCount = @($operations | Where-Object { $_.Status -eq 'CREATE' }).Count
$updateCount = @($operations | Where-Object { $_.Status -eq 'UPDATE' }).Count
$unchangedCount = @($operations | Where-Object { $_.Status -eq 'UNCHANGED' }).Count
$changedOperations = @($operations | Where-Object { $_.Status -ne 'UNCHANGED' })
$needsBackup = $updateCount -gt 0
$deploymentId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
$backupPath = Join-Path $BackupRoot $deploymentId
$stagePath = Join-Path $StageRoot $deploymentId

if ($WhatIfPreference) {
    if ($needsBackup) { Write-Output "WOULD_BACKUP $backupPath" }
    Write-Output "SUMMARY create=$createCount update=$updateCount unchanged=$unchangedCount"
    return
}
if ($changedOperations.Count -eq 0) {
    Write-Output "SUMMARY create=$createCount update=$updateCount unchanged=$unchangedCount"
    return
}
if (-not $PSCmdlet.ShouldProcess($AddonTarget, 'Deploy staged SoloCollections Phase 1 transaction')) {
    return
}
if ($SimulateFailureAfter -gt 0 -and $env:SOLO_COLLECTIONS_DEPLOY_TEST_MODE -ne '1') {
    throw 'SimulateFailureAfter is restricted to SOLO_COLLECTIONS_DEPLOY_TEST_MODE=1 recovery drills.'
}

$createdTargets = New-Object System.Collections.Generic.List[string]
$overwrittenOperations = New-Object System.Collections.Generic.List[object]
$backupComplete = $false
$commitCount = 0
try {
    # Stage every output first, then prove it is byte-identical to its source.
    Ensure-DirectoryActual $stagePath
    $stageAddon = Join-Path $stagePath 'SoloCollections'
    foreach ($operation in $operations) {
        if ($operation.Kind -eq 'ADDON') {
            $operation.StageSource = Join-Path $stageAddon $operation.RelativePath
        }
        else {
            $operation.StageSource = Join-Path (Join-Path $stagePath 'server') 'solo_collections.lua'
        }
        Ensure-DirectoryActual (Split-Path -Parent $operation.StageSource)
        Copy-Item -LiteralPath $operation.Source -Destination $operation.StageSource -Force
        if ((Get-Sha256 $operation.StageSource) -ne $operation.SourceHash) {
            throw "Staging hash mismatch: $($operation.RelativePath)"
        }
    }

    # Snapshot existing feature targets before the first live write.
    if ($needsBackup) {
        Ensure-DirectoryActual $backupPath
        $addonUpdates = @($operations | Where-Object { $_.Kind -eq 'ADDON' -and $_.Status -eq 'UPDATE' })
        if ($addonUpdates.Count -gt 0) {
            $backupAddon = Join-Path $backupPath 'SoloCollections'
            Ensure-DirectoryActual $backupAddon
            foreach ($operation in $addonUpdates) {
                $backupFile = Join-Path $backupAddon $operation.RelativePath
                Ensure-DirectoryActual (Split-Path -Parent $backupFile)
                Copy-Item -LiteralPath $operation.Target -Destination $backupFile -Force
                if ((Get-Sha256 $backupFile) -ne (Get-Sha256 $operation.Target)) {
                    throw "Backup hash mismatch: $($operation.RelativePath)"
                }
            }
        }
        $serverUpdate = @($operations | Where-Object { $_.Kind -eq 'SERVER' -and $_.Status -eq 'UPDATE' })
        if ($serverUpdate.Count -gt 0) {
            $serverBackup = Join-Path $backupPath 'solo_collections.lua'
            Copy-Item -LiteralPath $ServerLuaTarget -Destination $serverBackup -Force
            if ((Get-Sha256 $serverBackup) -ne (Get-Sha256 $ServerLuaTarget)) {
                throw 'Backup hash mismatch: solo_collections.lua'
            }
        }
        $backupComplete = $true
        Write-Output "BACKUP $backupPath"
    }

    # Commit only desired feature files. Unrelated target files are never enumerated for writes.
    foreach ($operation in $changedOperations) {
        Ensure-DirectoryActual (Split-Path -Parent $operation.Target)
        if ($operation.Status -eq 'CREATE') { $createdTargets.Add($operation.Target) }
        else { $overwrittenOperations.Add($operation) }
        Copy-Item -LiteralPath $operation.StageSource -Destination $operation.Target -Force
        if ((Get-Sha256 $operation.Target) -ne $operation.SourceHash) {
            throw "Committed hash mismatch: $($operation.RelativePath)"
        }
        $commitCount++
        if ($SimulateFailureAfter -gt 0 -and $commitCount -eq $SimulateFailureAfter) {
            throw "Simulated mid-deploy failure after $commitCount commit operations."
        }
    }
    Write-Output "SUMMARY create=$createCount update=$updateCount unchanged=$unchangedCount"
}
catch {
    $failure = $_
    $restored = 0
    $removed = 0
    $rollbackErrors = New-Object System.Collections.Generic.List[string]
    for ($index = $overwrittenOperations.Count - 1; $index -ge 0; $index--) {
        $operation = $overwrittenOperations[$index]
        try {
            if (-not $backupComplete) { throw 'verified backup was not completed' }
            if ($operation.Kind -eq 'ADDON') {
                $backupFile = Join-Path (Join-Path $backupPath 'SoloCollections') $operation.RelativePath
            }
            else { $backupFile = Join-Path $backupPath 'solo_collections.lua' }
            Copy-Item -LiteralPath $backupFile -Destination $operation.Target -Force
            $restored++
        }
        catch { $rollbackErrors.Add("restore $($operation.Target): $($_.Exception.Message)") }
    }
    for ($index = $createdTargets.Count - 1; $index -ge 0; $index--) {
        $createdTarget = $createdTargets[$index]
        try {
            if (Test-Path -LiteralPath $createdTarget -PathType Leaf) {
                [System.IO.File]::Delete($createdTarget)
            }
            $removed++
        }
        catch { $rollbackErrors.Add("remove ${createdTarget}: $($_.Exception.Message)") }
    }
    Write-Output "ROLLBACK restored=$restored removed=$removed"
    $failureReport = Join-Path $backupPath 'deployment-failure.txt'
    try {
        Ensure-DirectoryActual $backupPath
        $reportLines = @(
            'status=failed',
            "failure=$($failure.Exception.Message)",
            "rollback_restored=$restored",
            "rollback_removed=$removed",
            "rollback_errors=$($rollbackErrors -join '; ')"
        )
        [System.IO.File]::WriteAllLines($failureReport, $reportLines, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "FAILURE_REPORT $failureReport"
    }
    catch { $rollbackErrors.Add("failure report: $($_.Exception.Message)") }
    if ($rollbackErrors.Count -gt 0) {
        throw "Deployment failed: $($failure.Exception.Message). Rollback errors: $($rollbackErrors -join '; ')"
    }
    throw "Deployment failed and rollback completed: $($failure.Exception.Message)"
}
finally {
    if ((Test-Path -LiteralPath $stagePath -PathType Container) -and
        (Test-PathOverlap $stagePath $StageRoot) -and
        -not $stagePath.Equals($StageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        [System.IO.Directory]::Delete($stagePath, $true)
        if ((Test-Path -LiteralPath $StageRoot -PathType Container) -and
            @(Get-ChildItem -LiteralPath $StageRoot -Force).Count -eq 0) {
            [System.IO.Directory]::Delete($StageRoot, $false)
        }
    }
}
