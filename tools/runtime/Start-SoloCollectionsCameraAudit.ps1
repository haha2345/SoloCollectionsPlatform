[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientPath,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][Security.SecureString]$Password,
    [string]$ExecutableName = 'Wow-SoloCam-PoC.exe',
    [Parameter(Mandatory = $true)][string]$LoginScript
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-AbsoluteNonCPath([string]$Path, [string]$Label) {
    if (-not [System.IO.Path]::IsPathRooted($Path)) { throw "$Label must be absolute: $Path" }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must not use C drive: $full" }
    return $full
}

$client = Assert-AbsoluteNonCPath $ClientPath 'ClientPath'
$evidence = Assert-AbsoluteNonCPath $EvidenceRoot 'EvidenceRoot'
$processName = [IO.Path]::GetFileNameWithoutExtension($ExecutableName)
$login = [IO.Path]::GetFullPath($LoginScript)
if (-not (Test-Path -LiteralPath $client -PathType Container)) { throw "Client missing: $client" }
if (-not (Test-Path -LiteralPath $evidence -PathType Container)) { throw "Evidence root missing: $evidence" }
if (-not (Test-Path -LiteralPath $login -PathType Leaf)) { throw "Login script missing: $login" }
if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { throw "$processName is already running" }

$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runRoot = Join-Path $evidence $runId
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$sourceAddon = Join-Path $PSScriptRoot 'SoloCollectionsCameraAudit'
$targetAddon = Join-Path $client 'Interface\AddOns\SoloCollectionsCameraAudit'
$saved = Join-Path $client "WTF\Account\$($Account.ToUpperInvariant())\SavedVariables\SoloCollectionsCameraAudit.lua"
$screenshots = Join-Path $client 'Screenshots'
$previousAddon = Join-Path $runRoot 'previous-addon'
$previousSaved = Join-Path $runRoot 'previous-SavedVariables.lua'
if (Test-Path -LiteralPath $targetAddon -PathType Container) { Copy-Item -LiteralPath $targetAddon -Destination $previousAddon -Recurse }
if (Test-Path -LiteralPath $saved -PathType Leaf) { Copy-Item -LiteralPath $saved -Destination $previousSaved }
if (Test-Path -LiteralPath $targetAddon) { Remove-Item -LiteralPath $targetAddon -Recurse -Force }
Copy-Item -LiteralPath $sourceAddon -Destination $targetAddon -Recurse
[IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
[IO.File]::WriteAllText($saved, "SoloCollectionsCameraAuditDB = { requested = true }`r`n", [Text.UTF8Encoding]::new($false))
$beforeScreens = @{}
if (Test-Path -LiteralPath $screenshots) { Get-ChildItem -LiteralPath $screenshots -File | ForEach-Object { $beforeScreens[$_.FullName] = $true } }

if (-not ('SoloCollectionsCameraAudit.EnterKey' -as [type])) {
    $compileTemp = Join-Path $runRoot '.compile'
    [IO.Directory]::CreateDirectory($compileTemp) | Out-Null
    $oldTemp = $env:TEMP; $oldTmp = $env:TMP
    try {
        $env:TEMP = $compileTemp; $env:TMP = $compileTemp
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
namespace SoloCollectionsCameraAudit {
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
    } finally { $env:TEMP = $oldTemp; $env:TMP = $oldTmp }
}

$process = $null
try {
    & $login -ClientPath $client -ExecutableName $ExecutableName -Account $Account -Password $Password -LoginReadyDelaySeconds 3
    Start-Sleep -Seconds 7
    $process = Get-Process -Name $processName -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1
    [SoloCollectionsCameraAudit.EnterKey]::Press($process.MainWindowHandle)
    Start-Sleep -Seconds 92
    & (Join-Path $PSScriptRoot 'Invoke-WowChatCommand.ps1') -Command '/reload' -ProcessName $processName | Out-Null
    Start-Sleep -Seconds 9
    & (Join-Path $PSScriptRoot 'Invoke-WowChatCommand.ps1') -Command '/reload' -ProcessName $processName | Out-Null
    Start-Sleep -Seconds 9
    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) { throw "Camera audit SavedVariables missing: $saved" }
    Copy-Item -LiteralPath $saved -Destination (Join-Path $runRoot 'SoloCollectionsCameraAudit.lua')
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force; $process.WaitForExit(5000) | Out-Null }
    if (Test-Path -LiteralPath $targetAddon) { Remove-Item -LiteralPath $targetAddon -Recurse -Force }
    if (Test-Path -LiteralPath $previousAddon) { Copy-Item -LiteralPath $previousAddon -Destination $targetAddon -Recurse }
    if (Test-Path -LiteralPath $previousSaved) { Copy-Item -LiteralPath $previousSaved -Destination $saved -Force }
    elseif (Test-Path -LiteralPath $saved) { Remove-Item -LiteralPath $saved -Force }
}

$newScreens = Get-ChildItem -LiteralPath $screenshots -File | Where-Object { -not $beforeScreens.ContainsKey($_.FullName) } | Sort-Object LastWriteTime
$index = 0
foreach ($screen in $newScreens) {
    $index++
    Move-Item -LiteralPath $screen.FullName -Destination (Join-Path $runRoot ("camera-{0:D2}{1}" -f $index, $screen.Extension.ToLowerInvariant()))
}
$result = [ordered]@{ runId = $runId; runRoot = $runRoot; screenshots = $index; savedVariables = Join-Path $runRoot 'SoloCollectionsCameraAudit.lua'; completedUtc = [DateTime]::UtcNow.ToString('o') }
[IO.File]::WriteAllText((Join-Path $runRoot 'run.json'), (($result | ConvertTo-Json -Depth 4) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 4
