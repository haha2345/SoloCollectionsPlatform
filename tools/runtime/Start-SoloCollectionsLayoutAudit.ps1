[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientPath,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+x\d+$')][string]$Resolution,
    [Parameter(Mandatory = $true)][ValidateRange(0.64, 1.0)][double]$UiScale,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][Security.SecureString]$Password,
    [string]$ExecutableName = 'Wow-SoloCam-PoC.exe',
    [string]$LoginScript = 'F:\1_projects\wow_projects\tools\dev\Start-WowLogin.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-AbsoluteNonCPath {
    param([string]$Path, [string]$Label)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        throw "$Label must be absolute: $Path"
    }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('C:\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must not use C drive: $full"
    }
    return $full
}

function Set-ConfigValue {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Name, [string]$Value)
    $pattern = '^\s*SET\s+' + [regex]::Escape($Name) + '\s+".*"\s*$'
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match $pattern) {
            $Lines[$index] = "SET $Name `"$Value`""
            return
        }
    }
    $Lines.Add("SET $Name `"$Value`"")
}

function Invoke-Reload {
    param([string]$ProcessName, [string]$CommandScript)
    & $CommandScript -Command '/reload' -ProcessName $ProcessName
    Start-Sleep -Seconds 7
}

$client = Assert-AbsoluteNonCPath $ClientPath 'ClientPath'
$evidence = Assert-AbsoluteNonCPath $EvidenceRoot 'EvidenceRoot'
$login = [System.IO.Path]::GetFullPath($LoginScript)
if (-not (Test-Path -LiteralPath $client -PathType Container)) { throw "Client missing: $client" }
if (-not (Test-Path -LiteralPath $evidence -PathType Container)) { throw "Evidence root missing: $evidence" }
if (-not (Test-Path -LiteralPath $login -PathType Leaf)) { throw "Login script missing: $login" }

$processName = [System.IO.Path]::GetFileNameWithoutExtension($ExecutableName)
$existing = Get-Process -Name $processName -ErrorAction SilentlyContinue
if ($existing) { throw "Audit client already running: $($existing.Id -join ',')" }

$profileName = $Resolution + '-ui' + $UiScale.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
$profileRoot = Join-Path $evidence $profileName
[System.IO.Directory]::CreateDirectory($profileRoot) | Out-Null
$configPath = Join-Path $client 'WTF\Config.wtf'
$savedVariables = Join-Path $client "WTF\Account\$($Account.ToUpperInvariant())\SavedVariables\SoloCollectionsLayoutAudit.lua"
$screenshots = Join-Path $client 'Screenshots'
$commandScript = Join-Path $PSScriptRoot 'Invoke-WowChatCommand.ps1'

Copy-Item -LiteralPath $configPath -Destination (Join-Path $profileRoot 'Config.before.wtf')
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in [System.IO.File]::ReadAllLines($configPath)) { $lines.Add($line) }
Set-ConfigValue $lines 'gxWindow' '1'
Set-ConfigValue $lines 'gxMaximize' '0'
Set-ConfigValue $lines 'gxResolution' $Resolution
Set-ConfigValue $lines 'useUiScale' '1'
Set-ConfigValue $lines 'uiScale' $UiScale.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
[System.IO.File]::WriteAllLines($configPath, $lines, [System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $configPath -Destination (Join-Path $profileRoot 'Config.applied.wtf')

if (Test-Path -LiteralPath $savedVariables -PathType Leaf) {
    Move-Item -LiteralPath $savedVariables -Destination (Join-Path $profileRoot 'SavedVariables.before.lua')
}
$beforeScreens = @{}
if (Test-Path -LiteralPath $screenshots -PathType Container) {
    Get-ChildItem -LiteralPath $screenshots -File | ForEach-Object { $beforeScreens[$_.FullName] = $true }
}

if (-not ('SoloCollectionsLayoutAudit.EnterKey' -as [type])) {
    $compileTemp = Join-Path $PSScriptRoot ('.layout-audit-compile-' + [Guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($compileTemp) | Out-Null
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    try {
        $env:TEMP = $compileTemp
        $env:TMP = $compileTemp
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
namespace SoloCollectionsLayoutAudit {
    public static class EnterKey {
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)] struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
            public ushort dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public uint dmFields;
            public int dmPositionX, dmPositionY;
            public uint dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
            public ushort dmLogPixels;
            public uint dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public uint dmICMMethod, dmICMIntent, dmMediaType, dmDitherType;
            public uint dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }
        static DEVMODE originalDisplayMode;
        static bool displayModeChanged;
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hWnd, int command);
        [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll", SetLastError=true)] static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("user32.dll", SetLastError=true)] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
        [DllImport("user32.dll", SetLastError=true)] static extern bool AdjustWindowRectEx(ref RECT rect, uint style, bool menu, uint exStyle);
        [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll", SetLastError=true)] static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll", SetLastError=true)] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll", CharSet=CharSet.Ansi)] static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE devMode);
        [DllImport("user32.dll", CharSet=CharSet.Ansi)] static extern int ChangeDisplaySettings(ref DEVMODE devMode, uint flags);
        public static void EnableDpiAwareness() { SetProcessDPIAware(); }
        public static bool EnsureDesktopAtLeast(int targetWidth, int targetHeight) {
            DEVMODE current = new DEVMODE();
            current.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(null, -1, ref current))
                throw new InvalidOperationException("Cannot read the current display mode.");
            if (current.dmPelsWidth >= targetWidth && current.dmPelsHeight >= targetHeight) return false;
            DEVMODE best = new DEVMODE();
            long bestArea = long.MaxValue;
            for (int index = 0; ; ++index) {
                DEVMODE candidate = new DEVMODE();
                candidate.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
                if (!EnumDisplaySettings(null, index, ref candidate)) break;
                if (candidate.dmPelsWidth < targetWidth || candidate.dmPelsHeight < targetHeight) continue;
                long area = (long)candidate.dmPelsWidth * candidate.dmPelsHeight;
                if (area < bestArea) { best = candidate; bestArea = area; }
            }
            if (bestArea == long.MaxValue)
                throw new InvalidOperationException("No display mode can contain the requested audit viewport.");
            originalDisplayMode = current;
            if (ChangeDisplaySettings(ref best, 4) != 0)
                throw new InvalidOperationException("Cannot switch to the temporary audit display mode.");
            displayModeChanged = true;
            Thread.Sleep(1500);
            DEVMODE applied = new DEVMODE();
            applied.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(null, -1, ref applied)
                || applied.dmPelsWidth < targetWidth || applied.dmPelsHeight < targetHeight) {
                RestoreDesktop();
                throw new InvalidOperationException("The temporary audit display mode did not become active.");
            }
            return true;
        }
        public static string CurrentDesktop() {
            DEVMODE current = new DEVMODE();
            current.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(null, -1, ref current)) return "UNKNOWN";
            return current.dmPelsWidth + "x" + current.dmPelsHeight;
        }
        public static void RestoreDesktop() {
            if (!displayModeChanged) return;
            ChangeDisplaySettings(ref originalDisplayMode, 0);
            displayModeChanged = false;
            Thread.Sleep(1000);
        }
        public static void ResizeClient(IntPtr window, int clientWidth, int clientHeight) {
            uint style = unchecked((uint)GetWindowLong(window, -16));
            uint exStyle = unchecked((uint)GetWindowLong(window, -20));
            style &= ~0x00CF0000u;
            SetWindowLong(window, -16, unchecked((int)style));
            RECT rect = new RECT { Left = 0, Top = 0, Right = clientWidth, Bottom = clientHeight };
            if (!AdjustWindowRectEx(ref rect, style, false, exStyle))
                throw new InvalidOperationException("Cannot calculate WoW window frame size.");
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (!SetWindowPos(window, IntPtr.Zero, rect.Left, rect.Top, width, height, 0x0060))
                throw new InvalidOperationException("Cannot resize WoW client area.");
            for (int attempt = 0; attempt < 3; ++attempt) {
                Thread.Sleep(250);
                RECT clientRect;
                RECT windowRect;
                if (!GetClientRect(window, out clientRect) || !GetWindowRect(window, out windowRect))
                    throw new InvalidOperationException("Cannot verify WoW client area.");
                int actualWidth = clientRect.Right - clientRect.Left;
                int actualHeight = clientRect.Bottom - clientRect.Top;
                if (actualWidth == clientWidth && actualHeight == clientHeight) return;
                int outerWidth = (windowRect.Right - windowRect.Left) + (clientWidth - actualWidth);
                int outerHeight = (windowRect.Bottom - windowRect.Top) + (clientHeight - actualHeight);
                if (!SetWindowPos(window, IntPtr.Zero, windowRect.Left, windowRect.Top, outerWidth, outerHeight, 0x0040))
                    throw new InvalidOperationException("Cannot refine WoW client area.");
            }
        }
        public static void Press(IntPtr window) {
            ShowWindowAsync(window, 9);
            if (!SetForegroundWindow(window)) throw new InvalidOperationException("Cannot focus WoW window.");
            Thread.Sleep(300);
            keybd_event(0x0D, 0, 0, UIntPtr.Zero);
            keybd_event(0x0D, 0, 2, UIntPtr.Zero);
        }
    }
}
'@
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        if (Test-Path -LiteralPath $compileTemp) { Remove-Item -LiteralPath $compileTemp -Recurse -Force }
    }
}

$process = $null
$displayChanged = $false
$auditDesktopMode = $null
$previousCompatLayer = $env:__COMPAT_LAYER
try {
    [SoloCollectionsLayoutAudit.EnterKey]::EnableDpiAwareness()
    $resolutionParts = $Resolution.Split('x')
    $displayChanged = [SoloCollectionsLayoutAudit.EnterKey]::EnsureDesktopAtLeast(
        [int]$resolutionParts[0],
        [int]$resolutionParts[1])
    $auditDesktopMode = [SoloCollectionsLayoutAudit.EnterKey]::CurrentDesktop()
    $env:__COMPAT_LAYER = 'HIGHDPIAWARE'
    & $login -ClientPath $client -ExecutableName $ExecutableName -Account $Account -Password $Password -LoginReadyDelaySeconds 3
    $env:__COMPAT_LAYER = $previousCompatLayer
    Start-Sleep -Seconds 7
    $process = Get-Process -Name $processName -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
    $process.Refresh()
    [SoloCollectionsLayoutAudit.EnterKey]::ResizeClient(
        $process.MainWindowHandle,
        [int]$resolutionParts[0],
        [int]$resolutionParts[1])
    Start-Sleep -Seconds 2
    [SoloCollectionsLayoutAudit.EnterKey]::Press($process.MainWindowHandle)
    Start-Sleep -Seconds 12
    Invoke-Reload $processName $commandScript
    Invoke-Reload $processName $commandScript
    if (-not (Test-Path -LiteralPath $savedVariables -PathType Leaf)) {
        throw "Layout audit SavedVariables were not written: $savedVariables"
    }
    Copy-Item -LiteralPath $savedVariables -Destination (Join-Path $profileRoot 'SoloCollectionsLayoutAudit.lua')
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $profileRoot 'Config.after-runtime.wtf')
}
finally {
    $env:__COMPAT_LAYER = $previousCompatLayer
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000) | Out-Null
    }
    if ($displayChanged) {
        [SoloCollectionsLayoutAudit.EnterKey]::RestoreDesktop()
    }
    $configBackup = Join-Path $profileRoot 'Config.before.wtf'
    if (Test-Path -LiteralPath $configBackup -PathType Leaf) {
        Copy-Item -LiteralPath $configBackup -Destination $configPath -Force
    }
}

Start-Sleep -Seconds 2
$newScreens = Get-ChildItem -LiteralPath $screenshots -File | Where-Object { -not $beforeScreens.ContainsKey($_.FullName) }
$screenIndex = 0
foreach ($screen in $newScreens) {
    $screenIndex++
    $extension = $screen.Extension.ToLowerInvariant()
    Move-Item -LiteralPath $screen.FullName -Destination (Join-Path $profileRoot ("audit-$screenIndex$extension"))
}

$result = [ordered]@{
    profile = $profileName
    resolution = $Resolution
    uiScale = $UiScale
    auditDesktopMode = $auditDesktopMode
    savedVariables = Join-Path $profileRoot 'SoloCollectionsLayoutAudit.lua'
    screenshots = $screenIndex
    completedUtc = [DateTime]::UtcNow.ToString('o')
}
[System.IO.File]::WriteAllText(
    (Join-Path $profileRoot 'run.json'),
    (($result | ConvertTo-Json -Depth 4) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false)
)
$result | ConvertTo-Json -Depth 4
