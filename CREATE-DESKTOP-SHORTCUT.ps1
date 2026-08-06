# Content notice: this is AI-generated/AI-edited technical text, not a personal
# opinion or political/social statement.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$launcher = Join-Path $root 'START-CODEX-DREAM-SKIN.cmd'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
  throw "Launcher not found: $launcher"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Codex Dream Skin - Source.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $env:ComSpec
$shortcut.Arguments = "/d /c `"$launcher`""
$shortcut.WorkingDirectory = $root
$shortcut.Description = '打开 Codex Dream Skin 主题管理器（源码版）'
$shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,2"
$shortcut.Save()
Write-Host "Desktop shortcut created: $shortcutPath"
