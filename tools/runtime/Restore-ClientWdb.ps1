<#
.SYNOPSIS
Quarantines WDB generated during a cold-cache test and restores the exact old cache.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ClientRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z]{4}$')][string] $Locale,
    [Parameter(Mandatory = $true)][string] $BackupRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WdbState.Common.ps1')

$clientRootFull = Get-NormalizedFullPath $ClientRoot
$backupRootFull = Get-NormalizedFullPath $BackupRoot
Assert-FDrivePath $backupRootFull
if (-not (Test-Path -LiteralPath $clientRootFull -PathType Container)) {
    throw "Client root does not exist: $clientRootFull"
}
Assert-ClientStopped $clientRootFull

$manifestPath = Join-Path $backupRootFull 'wdb-backup-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "WDB backup manifest is missing: $manifestPath"
}
$manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1) {
    throw "Unsupported WDB manifest schema: $($manifest.schemaVersion)"
}
if (-not ([string]$manifest.clientRoot).Equals($clientRootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
    -not ([string]$manifest.locale).Equals($Locale, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ClientRoot or Locale does not match the backup manifest.'
}

$wdbRoot = Get-NormalizedFullPath (Join-Path $clientRootFull 'Cache\WDB')
$targetPath = Get-NormalizedFullPath (Join-Path $wdbRoot $Locale)
Assert-PathUnderRoot -Path $targetPath -Root $wdbRoot
if (-not ([string]$manifest.originalWdbPath).Equals($targetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Manifest WDB target does not match the requested target.'
}

if ([string]$manifest.state -eq 'RESTORED') {
    if ([bool]$manifest.oldDirectoryPresent) {
        Assert-DirectoryMatchesManifest -Root $targetPath -ExpectedEntries $manifest.oldFiles
    }
    elseif (Test-Path -LiteralPath $targetPath) {
        throw "The original WDB was absent but the restored target now exists: $targetPath"
    }
    Write-Host "WDB cache is already restored and verified: $manifestPath"
    return
}
if ([string]$manifest.state -ne 'BACKED_UP') {
    throw "WDB restore refuses state $($manifest.state). Preserve all directories and inspect $($manifest.journalPath) before manual recovery."
}

$journalPath = [string]$manifest.journalPath
$coldPath = Get-NormalizedFullPath ([string]$manifest.coldDirectoryPath)
Assert-PathUnderRoot -Path $coldPath -Root $wdbRoot
if ([bool]$manifest.oldDirectoryPresent) {
    $backupCopy = Get-NormalizedFullPath ([string]$manifest.backupCopyPath)
    Assert-PathUnderRoot -Path $backupCopy -Root $backupRootFull
    Assert-DirectoryMatchesManifest -Root $backupCopy -ExpectedEntries $manifest.oldFiles
    if (Test-Path -LiteralPath $coldPath -PathType Container) {
        Assert-DirectoryMatchesManifest -Root $coldPath -ExpectedEntries $manifest.oldFiles
    }
}

$manifest.state = 'RESTORING'
$manifest.restoringUtc = [DateTime]::UtcNow.ToString('o')
Write-JsonAtomic -Path $manifestPath -Value $manifest

$generatedRecord = $null
if (Test-Path -LiteralPath $targetPath -PathType Container) {
    $generatedEntries = @(Get-DirectoryManifestEntries $targetPath)
    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
    $sameVolumeName = ".generated-during-test-$timestamp-$([Guid]::NewGuid().ToString('N'))"
    $sameVolumePath = Get-NormalizedFullPath (Join-Path $wdbRoot $sameVolumeName)
    $quarantineParent = Join-Path $backupRootFull 'generated-during-test'
    [void](New-Item -ItemType Directory -Force -Path $quarantineParent)
    $quarantinePath = Get-NormalizedFullPath (Join-Path $quarantineParent $timestamp)
    if ((Test-Path -LiteralPath $sameVolumePath) -or (Test-Path -LiteralPath $quarantinePath)) {
        throw 'Generated WDB quarantine target unexpectedly exists; no paths were cleaned.'
    }

    Add-OperationJournalEntry -JournalPath $journalPath -Operation 'RENAME_GENERATED_SAME_VOLUME' -Status 'PLANNED' -Source $targetPath -Destination $sameVolumePath
    Move-Item -LiteralPath $targetPath -Destination $sameVolumePath
    Add-OperationJournalEntry -JournalPath $journalPath -Operation 'RENAME_GENERATED_SAME_VOLUME' -Status 'COMPLETED' -Source $targetPath -Destination $sameVolumePath

    Add-OperationJournalEntry -JournalPath $journalPath -Operation 'MOVE_GENERATED_TO_QUARANTINE' -Status 'PLANNED' -Source $sameVolumePath -Destination $quarantinePath
    Move-Item -LiteralPath $sameVolumePath -Destination $quarantinePath
    Add-OperationJournalEntry -JournalPath $journalPath -Operation 'MOVE_GENERATED_TO_QUARANTINE' -Status 'COMPLETED' -Source $sameVolumePath -Destination $quarantinePath
    Assert-DirectoryMatchesManifest -Root $quarantinePath -ExpectedEntries $generatedEntries

    $generatedManifestPath = Join-Path $quarantinePath 'generated-wdb-manifest.json'
    $generatedManifest = [ordered]@{
        schemaVersion = 1
        capturedUtc = [DateTime]::UtcNow.ToString('o')
        sourceWdbPath = $targetPath
        quarantinePath = $quarantinePath
        files = @($generatedEntries)
    }
    Write-JsonAtomic -Path $generatedManifestPath -Value $generatedManifest
    $generatedRecord = [ordered]@{
        quarantinePath = $quarantinePath
        manifestPath = $generatedManifestPath
        files = @($generatedEntries)
    }
}

if ([bool]$manifest.oldDirectoryPresent) {
    if (Test-Path -LiteralPath $targetPath) {
        throw "Restore target conflict after quarantine: $targetPath"
    }
    if (Test-Path -LiteralPath $coldPath -PathType Container) {
        Add-OperationJournalEntry -JournalPath $journalPath -Operation 'RENAME_COLD_TO_ORIGINAL' -Status 'PLANNED' -Source $coldPath -Destination $targetPath
        Move-Item -LiteralPath $coldPath -Destination $targetPath
        Add-OperationJournalEntry -JournalPath $journalPath -Operation 'RENAME_COLD_TO_ORIGINAL' -Status 'COMPLETED' -Source $coldPath -Destination $targetPath
    }
    else {
        Add-OperationJournalEntry -JournalPath $journalPath -Operation 'COPY_BACKUP_TO_ORIGINAL' -Status 'PLANNED' -Source $backupCopy -Destination $targetPath -Detail 'Cold rename was missing; restoring from verified backup copy.'
        Copy-DirectoryExact -Source $backupCopy -Destination $targetPath
        Add-OperationJournalEntry -JournalPath $journalPath -Operation 'COPY_BACKUP_TO_ORIGINAL' -Status 'COMPLETED' -Source $backupCopy -Destination $targetPath
    }
    Assert-DirectoryMatchesManifest -Root $targetPath -ExpectedEntries $manifest.oldFiles
}

if ($null -ne $generatedRecord) {
    $records = @($manifest.generatedDuringTest)
    $records += $generatedRecord
    $manifest.generatedDuringTest = @($records)
}
$manifest.state = 'RESTORED'
$manifest.restoredUtc = [DateTime]::UtcNow.ToString('o')
Write-JsonAtomic -Path $manifestPath -Value $manifest
Write-Host "WDB cache restored and verified: $manifestPath"
