Set-StrictMode -Version Latest

function Get-NormalizedFullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathRooted($Path)) {
        throw "Path must be fully qualified: $Path"
    }
    if ($Path -match '^[A-Za-z]:[^\\/]') {
        throw "Drive-relative paths are not allowed: $Path"
    }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Assert-PathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Root,
        [switch] $AllowRoot
    )

    $fullPath = Get-NormalizedFullPath $Path
    $fullRoot = Get-NormalizedFullPath $Root
    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    if ($AllowRoot -and $fullPath.Equals($fullRoot, $comparison)) {
        return
    }
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, $comparison)) {
        throw "Path escapes declared root: path=$fullPath root=$fullRoot"
    }
}

function Assert-FDrivePath {
    param([Parameter(Mandatory = $true)][string] $Path)

    $fullPath = Get-NormalizedFullPath $Path
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if (-not $root.Equals('F:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup and evidence output must stay on F: drive: $fullPath"
    }
}

function Assert-ClientStopped {
    param([Parameter(Mandatory = $true)][string] $ClientRoot)

    $fullRoot = Get-NormalizedFullPath $ClientRoot
    $candidateNames = @('Wow', 'Wow-SoloCam-PoC', 'Wow-CQM-SoloCam')
    $running = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($candidateNames -notcontains $process.ProcessName) {
            continue
        }
        $processPath = $null
        try { $processPath = $process.Path } catch { $processPath = $null }
        if ([string]::IsNullOrWhiteSpace($processPath)) {
            $running += "$($process.ProcessName) pid=$($process.Id)"
            continue
        }
        $fullProcessPath = Get-NormalizedFullPath $processPath
        $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
        if ($fullProcessPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $running += "$($process.ProcessName) pid=$($process.Id) path=$fullProcessPath"
        }
    }
    if ($running.Count -gt 0) {
        throw "The WoW client must be closed before changing WDB state: $($running -join '; ')"
    }
}

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string] $Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-DirectoryManifestEntries {
    param([Parameter(Mandatory = $true)][string] $Root)

    $fullRoot = Get-NormalizedFullPath $Root
    if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) {
        throw "Manifest root does not exist: $fullRoot"
    }
    $rootPrefixLength = $fullRoot.Length + 1
    $entries = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $fullRoot -File -Recurse -Force | Sort-Object FullName)) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "WDB manifest refuses reparse-point files: $($file.FullName)"
        }
        $relative = $file.FullName.Substring($rootPrefixLength).Replace([System.IO.Path]::DirectorySeparatorChar, [char]'/')
        $entries += [ordered]@{
            relativePath = $relative
            size = [int64]$file.Length
            sha256 = Get-Sha256Lower $file.FullName
        }
    }
    return @($entries)
}

function Assert-DirectoryMatchesManifest {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)] $ExpectedEntries
    )

    $actual = @(Get-DirectoryManifestEntries $Root)
    $expected = @($ExpectedEntries)
    if ($actual.Count -ne $expected.Count) {
        throw "WDB manifest file-count mismatch at ${Root}: expected=$($expected.Count) actual=$($actual.Count)"
    }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $want = $expected[$index]
        $got = $actual[$index]
        if ([string]$want.relativePath -cne [string]$got.relativePath -or
            [int64]$want.size -ne [int64]$got.size -or
            [string]$want.sha256 -cne [string]$got.sha256) {
            throw "WDB manifest mismatch at index $index under $Root"
        }
    }
}

function Copy-DirectoryExact {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    $sourceFull = Get-NormalizedFullPath $Source
    $destinationFull = Get-NormalizedFullPath $Destination
    if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) {
        throw "Copy source is missing: $sourceFull"
    }
    if (Test-Path -LiteralPath $destinationFull) {
        throw "Copy destination already exists: $destinationFull"
    }
    [void](New-Item -ItemType Directory -Path $destinationFull)
    $prefixLength = $sourceFull.Length + 1
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceFull -File -Recurse -Force)) {
        $relative = $file.FullName.Substring($prefixLength)
        $target = Join-Path $destinationFull $relative
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            [void](New-Item -ItemType Directory -Force -Path $parent)
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)] $Value
    )

    $fullPath = Get-NormalizedFullPath $Path
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    $temporary = $fullPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = ($Value | ConvertTo-Json -Depth 20).Replace("`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $fullPath -Force
}

function Add-OperationJournalEntry {
    param(
        [Parameter(Mandatory = $true)][string] $JournalPath,
        [Parameter(Mandatory = $true)][string] $Operation,
        [Parameter(Mandatory = $true)][string] $Status,
        [string] $Source,
        [string] $Destination,
        [string] $Detail
    )

    $entry = [ordered]@{
        schemaVersion = 1
        utc = [DateTime]::UtcNow.ToString('o')
        operation = $Operation
        status = $Status
        source = $Source
        destination = $Destination
        detail = $Detail
    }
    $line = ($entry | ConvertTo-Json -Compress) + "`n"
    $writer = New-Object System.IO.StreamWriter($JournalPath, $true, (New-Object System.Text.UTF8Encoding($false)))
    try { $writer.Write($line) } finally { $writer.Dispose() }
}
