[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Command,
    [Parameter()][ValidateNotNullOrEmpty()][string]$ProcessName = 'Wow-SoloCam-PoC'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$process = Get-Process -Name $ProcessName -ErrorAction Stop |
    Sort-Object StartTime -Descending |
    Select-Object -First 1
if ($process.MainWindowHandle -eq [IntPtr]::Zero) {
    throw "WoW process has no main window: $($process.Id)"
}

if (-not ('SoloCollectionsRuntime.ChatKeyboard' -as [type])) {
    $compileTemp = Join-Path $PSScriptRoot ('.chat-command-compile-' + [Guid]::NewGuid().ToString('N'))
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    [void](New-Item -ItemType Directory -Path $compileTemp)
    try {
        $env:TEMP = $compileTemp
        $env:TMP = $compileTemp
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace SoloCollectionsRuntime
{
    public static class ChatKeyboard
    {
        private const int INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint KEYEVENTF_UNICODE = 0x0004;
        private const uint KEYEVENTF_SCANCODE = 0x0008;
        private const int SW_RESTORE = 9;
        private const ushort VK_CONTROL = 0x11;
        private const ushort VK_V = 0x56;
        private const ushort VK_RETURN = 0x0D;
        private const ushort SC_CONTROL = 0x1D;
        private const ushort SC_ENTER = 0x1C;
        private const ushort SC_V = 0x2F;

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT { public int type; public InputUnion data; }
        [StructLayout(LayoutKind.Explicit)]
        private struct InputUnion
        {
            [FieldOffset(0)] public KEYBDINPUT keyboard;
            [FieldOffset(0)] public MOUSEINPUT mouse;
            [FieldOffset(0)] public HARDWAREINPUT hardware;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort virtualKey;
            public ushort scanCode;
            public uint flags;
            public uint time;
            public UIntPtr extraInfo;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint flags;
            public uint time;
            public UIntPtr extraInfo;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct HARDWAREINPUT
        {
            public uint message;
            public ushort parameterLow;
            public ushort parameterHigh;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint inputCount, INPUT[] inputs, int inputSize);
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr windowHandle);
        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr windowHandle, int command);

        private static INPUT Key(ushort virtualKey, ushort scanCode, uint flags)
        {
            INPUT input = new INPUT();
            input.type = INPUT_KEYBOARD;
            input.data.keyboard.virtualKey = virtualKey;
            input.data.keyboard.scanCode = scanCode;
            input.data.keyboard.flags = flags;
            return input;
        }
        private static void Send(params INPUT[] inputs)
        {
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent != inputs.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not send keyboard input.");
        }
        private static void Press(ushort virtualKey)
        {
            Send(Key(virtualKey, 0, 0), Key(virtualKey, 0, KEYEVENTF_KEYUP));
        }
        private static INPUT Scan(ushort scanCode, uint flags)
        {
            return Key(0, scanCode, KEYEVENTF_SCANCODE | flags);
        }
        private static void PressScan(ushort scanCode)
        {
            Send(Scan(scanCode, 0), Scan(scanCode, KEYEVENTF_KEYUP));
        }
        public static void Paste()
        {
            Send(Scan(SC_CONTROL, 0), Scan(SC_V, 0),
                 Scan(SC_V, KEYEVENTF_KEYUP), Scan(SC_CONTROL, KEYEVENTF_KEYUP));
        }
        public static void OpenChat(IntPtr windowHandle)
        {
            ShowWindowAsync(windowHandle, SW_RESTORE);
            if (!SetForegroundWindow(windowHandle))
                throw new InvalidOperationException("Could not bring the WoW window to the foreground.");
            Thread.Sleep(300);
            PressScan(SC_ENTER);
        }
        public static void SubmitChat()
        {
            PressScan(SC_ENTER);
        }
    }
}
'@
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        if (Test-Path -LiteralPath $compileTemp -PathType Container) {
            Remove-Item -LiteralPath $compileTemp -Recurse -Force
        }
    }
}

Add-Type -AssemblyName System.Windows.Forms
try {
    [System.Windows.Forms.Clipboard]::SetText($Command)
    [SoloCollectionsRuntime.ChatKeyboard]::OpenChat($process.MainWindowHandle)
    Start-Sleep -Milliseconds 300
    [SoloCollectionsRuntime.ChatKeyboard]::Paste()
    Start-Sleep -Milliseconds 300
    [SoloCollectionsRuntime.ChatKeyboard]::SubmitChat()
}
finally {
    [System.Windows.Forms.Clipboard]::Clear()
}
"Submitted command to WoW PID $($process.Id)."
