param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('create','add','extract','compact')]
    [string]$Command,

    [Parameter(Mandatory=$true)]
    [string]$Archive,

    [string]$SourceRoot,
    [string]$IncludeListFile,
    [string]$ArchiveFile,
    [string]$OutputPath,
    [string]$ArchivePrefix = '',
    [int]$MaxFiles = 4096,
    [Parameter(Mandatory=$true)]
    [string]$StormLib
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()

if (-not (Test-Path -LiteralPath $StormLib)) {
    throw "StormLib.dll not found: $StormLib"
}

if (-not ('StormMpq.Native' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace StormMpq {
    public static class Native {
        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileCreateArchive(string szMpqName, uint dwCreateFlags, uint dwMaxFileCount, out IntPtr phMpq);

        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileOpenArchive(string szMpqName, uint dwPriority, uint dwFlags, out IntPtr phMpq);

        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "SFileAddFile")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileAddFilePtr(IntPtr hMpq, string szFileName, [MarshalAs(UnmanagedType.LPStr)] string szArchivedName, uint dwFlags);

        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Ansi, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileCompactArchive(IntPtr hMpq, string szListFile, bool bReserved);

        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "SFileExtractFile")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileExtractFilePtr(IntPtr hMpq, [MarshalAs(UnmanagedType.LPStr)] string szToExtract, string szExtracted, uint dwSearchScope);

        [DllImport("$($StormLib.Replace('\','\\'))", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileCloseArchive(IntPtr hMpq);
    }
}
"@
}

function Assert-StormResult {
    param([bool]$Result, [string]$Action)
    if (-not $Result) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Action failed, Win32Error=$code"
    }
}

function Normalize-MpqPath {
    param([string]$Path)
    return $Path.Replace('/', '\').TrimStart('\')
}

function Get-RelativePathCompat {
    param([string]$BasePath, [string]$ChildPath)
    $baseUriPath = $BasePath
    if (-not $baseUriPath.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $baseUriPath += [IO.Path]::DirectorySeparatorChar
    }
    $baseUri = [Uri]::new($baseUriPath)
    $childUri = [Uri]::new($ChildPath)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
}

$archiveFull = [IO.Path]::GetFullPath($Archive)

switch ($Command) {
    'create' {
        if (Test-Path -LiteralPath $archiveFull) {
            Remove-Item -LiteralPath $archiveFull -Force
        }
        $parent = Split-Path -Parent $archiveFull
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent | Out-Null
        }
        $handle = [IntPtr]::Zero
        Assert-StormResult ([StormMpq.Native]::SFileCreateArchive($archiveFull, 0, [uint32]$MaxFiles, [ref]$handle)) "create $archiveFull"
        Assert-StormResult ([StormMpq.Native]::SFileCloseArchive($handle)) "close $archiveFull"
        Write-Host "created $archiveFull"
    }
    'add' {
        if (-not $SourceRoot) {
            throw 'SourceRoot is required for add'
        }
        $sourceFull = [IO.Path]::GetFullPath($SourceRoot)
        if (-not (Test-Path -LiteralPath $sourceFull)) {
            throw "SourceRoot not found: $sourceFull"
        }
        $handle = [IntPtr]::Zero
        Assert-StormResult ([StormMpq.Native]::SFileOpenArchive($archiveFull, 0, 0, [ref]$handle)) "open $archiveFull"
        try {
            if ($IncludeListFile) {
                $includeFull = [IO.Path]::GetFullPath($IncludeListFile)
                if (-not (Test-Path -LiteralPath $includeFull -PathType Leaf)) {
                    throw "IncludeListFile not found: $includeFull"
                }
                $sourcePrefix = $sourceFull.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                $seen = @{}
                $files = foreach ($line in Get-Content -LiteralPath $includeFull -Encoding UTF8) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $relative = Normalize-MpqPath $line
                    if ($seen.ContainsKey($relative.ToLowerInvariant())) { continue }
                    $candidate = [IO.Path]::GetFullPath((Join-Path $sourceFull $relative))
                    if (-not $candidate.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                        throw "IncludeListFile path escapes SourceRoot: $relative"
                    }
                    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                        throw "IncludeListFile source file is missing: $relative"
                    }
                    $seen[$relative.ToLowerInvariant()] = $true
                    [pscustomobject]@{ FullName=$candidate; Relative=$relative }
                }
            }
            else {
                $files = foreach ($file in Get-ChildItem -LiteralPath $sourceFull -Recurse -File) {
                    [pscustomobject]@{ FullName=$file.FullName; Relative=(Get-RelativePathCompat $sourceFull $file.FullName) }
                }
            }
            $replaceExisting = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]0x80000000), 0)
            $mpqPaths = New-Object System.Collections.Generic.List[string]
            foreach ($file in $files) {
                $relative = $file.Relative
                if ([string]::IsNullOrEmpty($ArchivePrefix)) {
                    $mpqPath = Normalize-MpqPath $relative
                } else {
                    $mpqPath = Normalize-MpqPath (Join-Path $ArchivePrefix $relative)
                }
                Assert-StormResult ([StormMpq.Native]::SFileAddFilePtr($handle, $file.FullName, $mpqPath, $replaceExisting)) "add $mpqPath"
                $mpqPaths.Add($mpqPath) | Out-Null
            }
            if ($mpqPaths.Count -gt 0) {
                $listFile = Join-Path ([IO.Path]::GetTempPath()) ("stormmpq-listfile-" + [Guid]::NewGuid().ToString("N") + ".txt")
                try {
                    [IO.File]::WriteAllLines($listFile, $mpqPaths, [Text.Encoding]::ASCII)
                    Assert-StormResult ([StormMpq.Native]::SFileAddFilePtr($handle, $listFile, "(listfile)", $replaceExisting)) "add (listfile)"
                }
                finally {
                    Remove-Item -LiteralPath $listFile -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "added $($files.Count) files to $archiveFull"
        }
        finally {
            [void][StormMpq.Native]::SFileCloseArchive($handle)
        }
    }
    'extract' {
        if (-not $ArchiveFile) {
            throw 'ArchiveFile is required for extract'
        }
        if (-not $OutputPath) {
            throw 'OutputPath is required for extract'
        }
        $mpqPath = Normalize-MpqPath $ArchiveFile
        $outputFull = [IO.Path]::GetFullPath($OutputPath)
        $parent = Split-Path -Parent $outputFull
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent | Out-Null
        }
        $handle = [IntPtr]::Zero
        Assert-StormResult ([StormMpq.Native]::SFileOpenArchive($archiveFull, 0, 0, [ref]$handle)) "open $archiveFull"
        try {
            Assert-StormResult ([StormMpq.Native]::SFileExtractFilePtr($handle, $mpqPath, $outputFull, 0)) "extract $mpqPath"
            Write-Host "extracted $mpqPath to $outputFull"
        }
        finally {
            [void][StormMpq.Native]::SFileCloseArchive($handle)
        }
    }
    'compact' {
        $handle = [IntPtr]::Zero
        Assert-StormResult ([StormMpq.Native]::SFileOpenArchive($archiveFull, 0, 0, [ref]$handle)) "open $archiveFull"
        try {
            Assert-StormResult ([StormMpq.Native]::SFileCompactArchive($handle, $null, $false)) "compact $archiveFull"
            Write-Host "compacted $archiveFull"
        }
        finally {
            [void][StormMpq.Native]::SFileCloseArchive($handle)
        }
    }
}
