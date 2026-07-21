<#
.SYNOPSIS
Backs up and cold-starts one explicit WoW 3.3.5 WDB locale directory.
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

$wdbRoot = Get-NormalizedFullPath (Join-Path $clientRootFull 'Cache\WDB')
$targetPath = Get-NormalizedFullPath (Join-Path $wdbRoot $Locale)
Assert-PathUnderRoot -Path $targetPath -Root $wdbRoot
if (-not (Test-Path -LiteralPath $wdbRoot -PathType Container)) {
    [void](New-Item -ItemType Directory -Force -Path $wdbRoot)
}
if ($backupRootFull.StartsWith($clientRootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'BackupRoot must not be inside ClientRoot.'
}

[void](New-Item -ItemType Directory -Force -Path $backupRootFull)
$manifestPath = Join-Path $backupRootFull 'wdb-backup-manifest.json'
$journalPath = Join-Path $backupRootFull 'wdb-operation-journal.jsonl'
$backupCopy = Join-Path $backupRootFull 'original-cache-copy'

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $existing = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
    if ([string]$existing.state -eq 'BACKED_UP') {
        if ([bool]$existing.oldDirectoryPresent) {
            Assert-DirectoryMatchesManifest -Root ([string]$existing.coldDirectoryPath) -ExpectedEntries $existing.oldFiles
            Assert-DirectoryMatchesManifest -Root ([string]$existing.backupCopyPath) -ExpectedEntries $existing.oldFiles
        }
        Write-Host "WDB backup is already prepared: $manifestPath"
        return
    }
    throw "BackupRoot already contains a non-reusable manifest in state $($existing.state): $manifestPath"
}

$oldDirectoryPresent = Test-Path -LiteralPath $targetPath -PathType Container
$oldFiles = @()
if ($oldDirectoryPresent) {
    $oldFiles = @(Get-DirectoryManifestEntries $targetPath)
    Copy-DirectoryExact -Source $targetPath -Destination $backupCopy
    Assert-DirectoryMatchesManifest -Root $backupCopy -ExpectedEntries $oldFiles
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$coldName = ".cold-test-$timestamp"
$coldPath = Get-NormalizedFullPath (Join-Path $wdbRoot $coldName)
if (Test-Path -LiteralPath $coldPath) {
    throw "Cold-test destination already exists: $coldPath"
}

$manifest = [ordered]@{
    schemaVersion = 1
    state = 'PREPARING'
    createdUtc = [DateTime]::UtcNow.ToString('o')
    backedUpUtc = $null
    restoringUtc = $null
    restoredUtc = $null
    clientRoot = $clientRootFull
    locale = $Locale
    originalWdbPath = $targetPath
    oldDirectoryPresent = [bool]$oldDirectoryPresent
    coldDirectoryName = $coldName
    coldDirectoryPath = $coldPath
    backupCopyPath = if ($oldDirectoryPresent) { $backupCopy } else { $null }
    oldFiles = @($oldFiles)
    generatedDuringTest = @()
    journalPath = $journalPath
}
Write-JsonAtomic -Path $manifestPath -Value $manifest

if ($oldDirectoryPresent) {
    Add-OperationJournalEntry -JournalPath $journalPath -Operation 'RENAME_OLD_TO_COLD' -Status 'PLANNED' -Source $targetPath -Destination $coldPath
    Move-Item -LiteralPath $targetPath -Destination $coldPath
    Add-OperationJournalEntry -JournalPath $journalPath -Operation 'RENAME_OLD_TO_COLD' -Status 'COMPLETED' -Source $targetPath -Destination $coldPath
    Assert-DirectoryMatchesManifest -Root $coldPath -ExpectedEntries $oldFiles
}

$manifest.state = 'BACKED_UP'
$manifest.backedUpUtc = [DateTime]::UtcNow.ToString('o')
Write-JsonAtomic -Path $manifestPath -Value $manifest
Write-Host "WDB cold-test state prepared: $manifestPath"
