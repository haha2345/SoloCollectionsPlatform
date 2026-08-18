param(
    [Parameter(Mandatory=$true)]
    [string]$Archive,

    [Parameter(Mandatory=$true)]
    [string]$ListFile,

    [Parameter(Mandatory=$true)]
    [string]$OutputRoot,

    [Parameter(Mandatory=$true)]
    [string]$StormLib
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()

if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
    throw "Archive not found: $Archive"
}
if (-not (Test-Path -LiteralPath $ListFile -PathType Leaf)) {
    throw "List file not found: $ListFile"
}
if (-not (Test-Path -LiteralPath $StormLib -PathType Leaf)) {
    throw "StormLib.dll not found: $StormLib"
}

if (-not ('SoloCollections.StormBatch.Native' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace SoloCollections.StormBatch {
    public static class Native {
        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileOpenArchive(string archive, uint priority, uint flags, out IntPtr handle);

        [DllImport("$($StormLib.Replace('\','\\'))", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "SFileExtractFile")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileExtractFilePtr(IntPtr handle, [MarshalAs(UnmanagedType.LPStr)] string fileName,
            string outputPath, uint searchScope);

        [DllImport("$($StormLib.Replace('\','\\'))", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SFileCloseArchive(IntPtr handle);
    }
}
"@
}

function Assert-Storm {
    param([bool]$Result, [string]$Action)
    if (-not $Result) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Action failed, Win32Error=$code"
    }
}

function Normalize-MpqPath {
    param([string]$Value)
    $path = $Value.Trim().Replace('/', '\').TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($path) -or $path.Contains(':') -or $path.Split('\') -contains '..') {
        throw "Unsafe MPQ-internal path: $Value"
    }
    return $path
}

$root = [IO.Path]::GetFullPath($OutputRoot)
if (-not $root.EndsWith([IO.Path]::DirectorySeparatorChar)) {
    $root += [IO.Path]::DirectorySeparatorChar
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$files = Get-Content -LiteralPath $ListFile -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { Normalize-MpqPath $_ } | Select-Object -Unique

$handle = [IntPtr]::Zero
Assert-Storm ([SoloCollections.StormBatch.Native]::SFileOpenArchive([IO.Path]::GetFullPath($Archive), 0, 0, [ref]$handle)) "open $Archive"
try {
    foreach ($path in $files) {
        $output = [IO.Path]::GetFullPath((Join-Path $root $path))
        if (-not $output.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "MPQ output escaped root: $path"
        }
        $parent = Split-Path -Parent $output
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Assert-Storm ([SoloCollections.StormBatch.Native]::SFileExtractFilePtr($handle, $path, $output, 0)) "extract $path"
    }
    Write-Host "extracted $($files.Count) requested files from $([IO.Path]::GetFileName($Archive))"
}
finally {
    if ($handle -ne [IntPtr]::Zero) {
        [void][SoloCollections.StormBatch.Native]::SFileCloseArchive($handle)
    }
}
