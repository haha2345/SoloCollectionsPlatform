Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Resolve-RoundTwoPath {
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowMissing)
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "Wildcard paths are forbidden: $Path"
    }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ([System.IO.Path]::GetPathRoot($full) -eq 'C:\') {
        throw "C drive paths are forbidden: $full"
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) {
        throw "Required path does not exist: $full"
    }
    return $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Assert-RoundTwoWithin {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root, [switch]$AllowEqual)
    $candidate = Resolve-RoundTwoPath -Path $Path -AllowMissing
    $rootPath = Resolve-RoundTwoPath -Path $Root -AllowMissing
    if ($AllowEqual -and [string]::Equals($candidate, $rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    $prefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes declared root: path=$candidate root=$rootPath"
    }
}

function Get-RoundTwoSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally { $stream.Dispose() }
}

function Read-RoundTwoJson {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-RoundTwoJson {
    param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path, [int]$Depth = 30)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $text = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $text + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Get-RoundTwoTgaInfo {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 18) { throw "TGA is shorter than its header: $Path" }
    $width = [BitConverter]::ToUInt16($bytes, 12)
    $height = [BitConverter]::ToUInt16($bytes, 14)
    return [pscustomobject]@{
        ImageType = [int]$bytes[2]
        Width = [int]$width
        Height = [int]$height
        PixelDepth = [int]$bytes[16]
        AlphaBits = [int]($bytes[17] -band 0x0F)
        TopLeftOrigin = (($bytes[17] -band 0x20) -ne 0)
    }
}

function Assert-RoundTwoBaseMedia {
    param([Parameter(Mandatory)][string]$AddonRoot)

    $addon = Resolve-RoundTwoPath -Path $AddonRoot
    $mediaRoot = Resolve-RoundTwoPath -Path (Join-Path $addon 'Media')
    $manifestPath = Join-Path $mediaRoot 'assets.json'
    $manifest = Read-RoundTwoJson -Path $manifestPath
    if ([int]$manifest.schemaVersion -lt 2) { throw "Base media manifest schema is unsupported" }
    $required = $manifest.requiredForBaseUI
    $files = $manifest.files
    $optional = $manifest.optionalExternalFiles
    if ($null -eq $required -or $null -eq $files -or $null -eq $optional) {
        throw "Base media manifest must declare files, requiredForBaseUI and optionalExternalFiles"
    }

    $roles = @('launcher', 'mountPortrait', 'wardrobeSlotAtlas', 'roundHighlightAtlas')
    $declaredRoles = @($required.PSObject.Properties.Name | Sort-Object)
    if (@($declaredRoles).Count -ne $roles.Count -or @($roles | Where-Object { $_ -notin $declaredRoles }).Count -ne 0) {
        throw "Base media roles differ from the four production defaults"
    }

    foreach ($role in $roles) {
        $entry = $required.PSObject.Properties[$role].Value
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or
            [System.IO.Path]::IsPathRooted($relative) -or $relative -match '^(?i:Retail[\\/])') {
            throw "Unsafe or external-only base media path for ${role}: $relative"
        }
        if ($optional.PSObject.Properties[$relative]) { throw "Base media role cannot be optional: $role" }
        $expectedHash = ([string]$entry.sha256).ToUpperInvariant()
        if ($expectedHash -notmatch '^[A-F0-9]{64}$') { throw "Invalid base media hash for $role" }
        if ([string]$entry.fileType -ne 'TGA' -or [string]$entry.origin -ne 'top-left' -or [int]$entry.alphaBits -ne 8) {
            throw "Base media format contract failed for $role"
        }
        $declaredFile = $files.PSObject.Properties[$relative]
        if ($null -eq $declaredFile -or ([string]$declaredFile.Value).ToUpperInvariant() -ne $expectedHash) {
            throw "Base media file hash declaration differs for $role"
        }

        $path = Join-Path $mediaRoot $relative.Replace('/', '\')
        Assert-RoundTwoWithin -Path $path -Root $mediaRoot
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Base media file is missing: $role" }
        if ((Get-RoundTwoSha256 -Path $path).ToUpperInvariant() -ne $expectedHash) { throw "Base media hash mismatch: $role" }
        $tga = Get-RoundTwoTgaInfo -Path $path
        if ($tga.ImageType -ne 2 -or $tga.Width -ne [int]$entry.width -or $tga.Height -ne [int]$entry.height -or
            $tga.PixelDepth -ne 32 -or $tga.AlphaBits -ne 8 -or -not $tga.TopLeftOrigin) {
            throw "Base media TGA contract failed: $role"
        }
    }

    $templatesPath = Join-Path $addon 'UI\Templates.lua'
    $templates = Get-Content -LiteralPath $templatesPath -Raw -Encoding UTF8
    if ($templates -match 'MEDIA_ROOT\s*\.\.\s*"Retail\\') { throw "Production template still references Retail media" }
    foreach ($role in $roles) {
        $expected = ([string]$required.PSObject.Properties[$role].Value.path).Replace('/', '\\')
        $pattern = '(?m)^\s*' + [regex]::Escape($role) + '\s*=\s*MEDIA_ROOT\s*\.\.\s*"([^"]+)"'
        $match = [regex]::Match($templates, $pattern)
        if (-not $match.Success -or $match.Groups[1].Value -ne $expected) {
            throw "Production template does not resolve required base media role: $role"
        }
    }
    foreach ($lua in @(Get-ChildItem -LiteralPath $addon -Recurse -File -Filter '*.lua')) {
        if ((Get-Content -LiteralPath $lua.FullName -Raw -Encoding UTF8) -match 'Media\\Retail\\') {
            throw "Production Lua references Retail media: $($lua.FullName)"
        }
    }
}

function Get-RoundTwoPeInfo {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 512 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw "Not a PE file: $Path" }
    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($pe -lt 0 -or $pe + 256 -ge $bytes.Length -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x00004550) {
        throw "Invalid PE header: $Path"
    }
    $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
    $sections = [BitConverter]::ToUInt16($bytes, $pe + 6)
    $optionalSize = [BitConverter]::ToUInt16($bytes, $pe + 20)
    $optional = $pe + 24
    $magic = [BitConverter]::ToUInt16($bytes, $optional)
    $dataDirectory = if ($magic -eq 0x20B) { $optional + 112 } elseif ($magic -eq 0x10B) { $optional + 96 } else { throw "Unknown PE optional header: $Path" }
    $importRva = [BitConverter]::ToUInt32($bytes, $dataDirectory + 8)
    $sectionTable = $optional + $optionalSize
    $sectionRows = @()
    for ($index = 0; $index -lt $sections; $index++) {
        $offset = $sectionTable + 40 * $index
        $sectionRows += [pscustomobject]@{
            VirtualSize = [BitConverter]::ToUInt32($bytes, $offset + 8)
            VirtualAddress = [BitConverter]::ToUInt32($bytes, $offset + 12)
            RawSize = [BitConverter]::ToUInt32($bytes, $offset + 16)
            RawPointer = [BitConverter]::ToUInt32($bytes, $offset + 20)
        }
    }
    function Convert-Rva([uint32]$Rva) {
        foreach ($section in $sectionRows) {
            $span = [Math]::Max($section.VirtualSize, $section.RawSize)
            if ($Rva -ge $section.VirtualAddress -and $Rva -lt $section.VirtualAddress + $span) {
                return [int]($section.RawPointer + ($Rva - $section.VirtualAddress))
            }
        }
        throw "PE RVA is outside sections: $Rva"
    }
    $imports = @()
    if ($importRva -ne 0) {
        $descriptor = Convert-Rva $importRva
        while ($descriptor + 20 -le $bytes.Length) {
            $nameRva = [BitConverter]::ToUInt32($bytes, $descriptor + 12)
            if ($nameRva -eq 0) { break }
            $nameOffset = Convert-Rva $nameRva
            $end = $nameOffset
            while ($end -lt $bytes.Length -and $bytes[$end] -ne 0) { $end++ }
            $imports += [System.Text.Encoding]::ASCII.GetString($bytes, $nameOffset, $end - $nameOffset).ToLowerInvariant()
            $descriptor += 20
        }
    }
    return [pscustomobject]@{
        Machine = ('0x{0:X4}' -f $machine)
        IsX64 = ($machine -eq 0x8664)
        Imports = @($imports | Sort-Object -Unique)
    }
}

function Get-RoundTwoTrackedFiles {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Prefix)
    $output = & git -C $Repo ls-files -z -- $Prefix
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed: $Repo" }
    return @(([string]$output) -split "`0" | Where-Object { $_ })
}

function Assert-RoundTwoCleanTracked {
    param([Parameter(Mandatory)][string]$Repo)
    $status = (& git -C $Repo status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { throw "git status failed: $Repo" }
    if ($status) { throw "Tracked working tree must be clean: $Repo" }
}

function Get-RoundTwoCommit {
    param([Parameter(Mandatory)][string]$Repo)
    $commit = (& git -C $Repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw "Cannot resolve commit: $Repo" }
    return $commit
}

function Assert-RoundTwoProfile {
    param([Parameter(Mandatory)][object]$Profile)
    foreach ($name in @('serverRoot','worldserverExeTarget','worldserverWorkingDirectory','runtimeModuleConfig','addonRoot','clientRoot','soloCamDllTarget','backupRoot')) {
        if (-not $Profile.PSObject.Properties[$name]) { throw "Deployment profile missing $name" }
        [void](Resolve-RoundTwoPath -Path ([string]$Profile.$name) -AllowMissing)
    }
    foreach ($name in @('worldserverDependencyTargets','assetPatchTargets','wdbRoots')) {
        if (-not $Profile.PSObject.Properties[$name]) { throw "Deployment profile missing $name" }
    }
    $serverRoot = Resolve-RoundTwoPath -Path ([string]$Profile.serverRoot) -AllowMissing
    Assert-RoundTwoWithin -Path ([string]$Profile.worldserverExeTarget) -Root $serverRoot
    Assert-RoundTwoWithin -Path ([string]$Profile.worldserverWorkingDirectory) -Root $serverRoot -AllowEqual
    Assert-RoundTwoWithin -Path ([string]$Profile.runtimeModuleConfig) -Root $serverRoot
    $clientRoot = Resolve-RoundTwoPath -Path ([string]$Profile.clientRoot) -AllowMissing
    Assert-RoundTwoWithin -Path ([string]$Profile.addonRoot) -Root $clientRoot
    Assert-RoundTwoWithin -Path ([string]$Profile.soloCamDllTarget) -Root $clientRoot
    foreach ($entry in @($Profile.worldserverDependencyTargets)) { Assert-RoundTwoWithin -Path ([string]$entry.target) -Root $serverRoot }
    foreach ($entry in @($Profile.assetPatchTargets)) { Assert-RoundTwoWithin -Path ([string]$entry.target) -Root $clientRoot }
    foreach ($entry in @($Profile.wdbRoots)) { Assert-RoundTwoWithin -Path ([string]$entry) -Root $clientRoot }
    $mode = [string]$Profile.serverControl.mode
    if ($mode -notin @('WINDOWS_SERVICE','EXTERNAL_COMMAND','MANUAL')) { throw "Unsupported serverControl mode: $mode" }
}

function Invoke-RoundTwoServerControl {
    param([Parameter(Mandatory)][object]$Profile, [Parameter(Mandatory)][ValidateSet('Stop','Start')]$Action)
    $control = $Profile.serverControl
    switch ([string]$control.mode) {
        'MANUAL' {
            if ($Action -eq 'Start') { return }
            $target = Resolve-RoundTwoPath -Path ([string]$Profile.worldserverExeTarget) -AllowMissing
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                try { $stream = [System.IO.File]::Open($target, 'Open', 'ReadWrite', 'None'); $stream.Dispose() }
                catch { throw "MANUAL mode requires worldserver to be stopped and executable unlockable: $target" }
            }
        }
        'WINDOWS_SERVICE' {
            $service = Get-CimInstance Win32_Service -Filter "Name='$([string]$control.serviceName)'"
            if (-not $service) { throw "Configured service was not found" }
            $serviceExe = ([regex]::Match([string]$service.PathName, '^(?:"([^"]+)"|(\S+))')).Groups | Where-Object { $_.Value -and $_.Value -ne $service.PathName } | Select-Object -First 1 -ExpandProperty Value
            if (-not $serviceExe) { $serviceExe = ([string]$service.PathName).Trim('"') }
            if (-not [string]::Equals([System.IO.Path]::GetFullPath($serviceExe), [System.IO.Path]::GetFullPath([string]$Profile.worldserverExeTarget), [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Service executable does not match worldserverExeTarget"
            }
            if ($Action -eq 'Stop') { Stop-Service -Name ([string]$control.serviceName) -ErrorAction Stop }
            else { Start-Service -Name ([string]$control.serviceName) -ErrorAction Stop }
            $targetStatus = if ($Action -eq 'Stop') { 'Stopped' } else { 'Running' }
            (Get-Service -Name ([string]$control.serviceName)).WaitForStatus($targetStatus, [TimeSpan]::FromSeconds(60))
        }
        'EXTERNAL_COMMAND' {
            $entry = if ($Action -eq 'Stop') { $control.stop } else { $control.start }
            $script = Resolve-RoundTwoPath -Path ([string]$entry.script)
            if ((Get-RoundTwoSha256 $script) -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "Server control script hash mismatch" }
            $working = Resolve-RoundTwoPath -Path ([string]$entry.workingDirectory)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "$Action server command failed: $LASTEXITCODE" }
        }
    }
}
