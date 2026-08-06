[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$CodexExe,
  [Parameter(Mandatory = $true)][string]$IconPath,
  [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$codexPath = [System.IO.Path]::GetFullPath($CodexExe)
$iconFile = [System.IO.Path]::GetFullPath($IconPath)
if (-not (Test-Path -LiteralPath $codexPath -PathType Leaf)) { throw 'Codex executable was not found.' }
if (-not (Test-Path -LiteralPath $iconFile -PathType Leaf) -or
  [System.IO.Path]::GetExtension($iconFile) -ine '.ico') {
  throw 'The taskbar icon must be an existing ICO file.'
}

if (-not ('CodexDreamSkin.WindowIcon' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexDreamSkin {
  public static class WindowIcon {
    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x0010;
    private const uint LR_SHARED = 0x8000;
    private const uint WM_SETICON = 0x0080;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadImage(IntPtr instance, string name, uint type,
      int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessage(IntPtr window, uint message,
      IntPtr parameter, IntPtr value);

    public static bool Apply(IntPtr window, string iconPath) {
      if (window == IntPtr.Zero) return false;
      IntPtr small = LoadImage(IntPtr.Zero, iconPath, IMAGE_ICON, 16, 16,
        LR_LOADFROMFILE | LR_SHARED);
      IntPtr large = LoadImage(IntPtr.Zero, iconPath, IMAGE_ICON, 32, 32,
        LR_LOADFROMFILE | LR_SHARED);
      if (small == IntPtr.Zero || large == IntPtr.Zero) return false;
      SendMessage(window, WM_SETICON, IntPtr.Zero, small);
      SendMessage(window, WM_SETICON, new IntPtr(1), large);
      SendMessage(window, WM_SETICON, new IntPtr(2), small);
      return true;
    }
  }
}
'@
}

$deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(2, [Math]::Min(30, $TimeoutSeconds)))
$applied = $false
do {
  foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue)) {
    $candidatePath = $null
    try { $candidatePath = [System.IO.Path]::GetFullPath("$($candidate.ExecutablePath)") } catch {}
    if (-not $candidatePath -or $candidatePath -ine $codexPath) { continue }
    try {
      $process = Get-Process -Id ([int]$candidate.ProcessId) -ErrorAction Stop
      $process.Refresh()
      if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
        $applied = [CodexDreamSkin.WindowIcon]::Apply($process.MainWindowHandle, $iconFile) -or $applied
      }
    } catch {}
  }
  if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 500 }
} while ([DateTime]::UtcNow -lt $deadline)

if (-not $applied) { exit 1 }
