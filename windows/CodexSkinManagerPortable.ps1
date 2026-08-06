[CmdletBinding()]
param(
  [switch]$SelfTest,
  [string]$SelfTestOutput,
  [string]$RenderPreview,
  [string]$RoundTripTestOutput,
  [string]$RoundTripScreenshotDirectory
)

$ErrorActionPreference = 'Stop'
$script:PackageRoot = $PSScriptRoot
$script:BundledRoot = Join-Path $script:PackageRoot 'dream-skin'
if (-not (Test-Path -LiteralPath $script:BundledRoot -PathType Container)) {
  $sourceBundle = Join-Path (Split-Path -Parent $script:PackageRoot) 'dream-skin'
  if (Test-Path -LiteralPath $sourceBundle -PathType Container) {
    $script:BundledRoot = $sourceBundle
  }
}
$script:BundledScripts = Join-Path $script:BundledRoot 'scripts'
$script:StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$script:SettingsPath = Join-Path $script:StateRoot 'manager-settings.json'
$script:EngineRoot = Join-Path $script:StateRoot 'engine'
$script:EngineScripts = Join-Path $script:EngineRoot 'scripts'
$script:LauncherPath = $env:CODEX_DREAM_SKIN_LAUNCHER
$script:ThemeItems = @()
$script:PreviewBitmap = $null
$script:BackgroundBitmap = $null
$script:ManagerMutex = $null
$script:ManagerMutexAcquired = $false
$script:ManagerShowEvent = $null

$interactiveManager = -not ($SelfTest -or $RenderPreview -or $RoundTripTestOutput)
if ($interactiveManager) {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $script:ManagerMutex = [System.Threading.Mutex]::new($false, "Local\ChatGPTDreamSkin.$sid.ManagerUI")
  try { $script:ManagerMutexAcquired = $script:ManagerMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $script:ManagerMutexAcquired = $true }
  $eventCreated = $false
  $script:ManagerShowEvent = [System.Threading.EventWaitHandle]::new(
    $false,
    [System.Threading.EventResetMode]::AutoReset,
    "Local\ChatGPTDreamSkin.$sid.ShowManager",
    [ref]$eventCreated
  )
  if (-not $script:ManagerMutexAcquired) {
    [void]$script:ManagerShowEvent.Set()
    $script:ManagerShowEvent.Dispose()
    $script:ManagerMutex.Dispose()
    exit 0
  }
}

function Get-DreamSkinManagerSettings {
  $defaults = [pscustomobject]@{
    schemaVersion = 2
    checkEveryCodexLaunch = $false
    autoStartSkinnedChatGPT = $true
    updateWatcherEnabled = $true
  }
  if (-not (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf)) { return $defaults }
  try {
    $saved = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saved.schemaVersion -and [int]$saved.schemaVersion -gt 0 -and
      $saved.checkEveryCodexLaunch -is [bool]) {
      if ($saved.autoStartSkinnedChatGPT -isnot [bool]) { $saved | Add-Member autoStartSkinnedChatGPT $true -Force }
      if ($saved.updateWatcherEnabled -isnot [bool]) { $saved | Add-Member updateWatcherEnabled $true -Force }
      return $saved
    }
  } catch {}
  return $defaults
}

function Save-DreamSkinManagerSettings {
  param(
    [Parameter(Mandatory = $true)][bool]$CheckEveryCodexLaunch,
    [Parameter(Mandatory = $true)][bool]$AutoStartSkinnedChatGPT,
    [Parameter(Mandatory = $true)][bool]$UpdateWatcherEnabled
  )
  if (-not (Test-Path -LiteralPath $script:StateRoot -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($script:StateRoot) | Out-Null
  }
  $settings = Get-DreamSkinManagerSettings
  $settings | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 2 -Force
  $settings | Add-Member -NotePropertyName checkEveryCodexLaunch `
    -NotePropertyValue $CheckEveryCodexLaunch -Force
  $settings | Add-Member autoStartSkinnedChatGPT $AutoStartSkinnedChatGPT -Force
  $settings | Add-Member updateWatcherEnabled $UpdateWatcherEnabled -Force
  Write-DreamSkinUtf8FileAtomically -Path $script:SettingsPath `
    -Content (($settings | ConvertTo-Json -Depth 5) + "`r`n")
}

# The visible manager window is hosted by powershell.exe. Give that host an
# explicit identity before WinForms creates its first window; otherwise Windows
# groups the window under PowerShell and replaces the bundled Karyl taskbar icon.
if (-not ('CodexDreamSkin.TaskbarIdentity' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexDreamSkin {
  public static class TaskbarIdentity {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    public static void Apply(string appId) {
      int result = SetCurrentProcessExplicitAppUserModelID(appId);
      if (result != 0) Marshal.ThrowExceptionForHR(result);
    }
  }
}
'@
}
[CodexDreamSkin.TaskbarIdentity]::Apply('CodexDreamSkin.Manager')

function Test-DreamSkinEnginePresent {
  return (Test-Path -LiteralPath (Join-Path $script:EngineScripts 'common-windows.ps1') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $script:EngineScripts 'theme-windows.ps1') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $script:EngineScripts 'set-window-icon.ps1') -PathType Leaf)
}

function Test-EngineInstalled {
  return (Test-DreamSkinEnginePresent) -and
    (Test-Path -LiteralPath (Join-Path $script:EngineRoot 'assets\manager-version-1.4.8.txt') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $script:EngineScripts 'watch-dream-skin-updates.ps1') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $script:EngineScripts 'uninstall-dream-skin-manager.ps1') -PathType Leaf)
}

function Test-DreamSkinUpdateWatcherDisabled {
  return Test-Path -LiteralPath (Join-Path $script:StateRoot 'update-watcher.disabled') -PathType Leaf
}

$script:ApiRoot = $script:BundledScripts
. (Join-Path $script:ApiRoot 'common-windows.ps1')
. (Join-Path $script:ApiRoot 'theme-windows.ps1')

function Get-ImageClone {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $stream = New-Object System.IO.MemoryStream(,$bytes)
  try {
    $source = [System.Drawing.Image]::FromStream($stream)
    try { return New-Object System.Drawing.Bitmap($source) } finally { $source.Dispose() }
  } finally { $stream.Dispose() }
}

function Get-BundledThemeItems {
  $directories = @(
    (Join-Path $script:PackageRoot 'themes\builtin-pastel-ragnarok-duo')
  )
  $items = @()
  foreach ($directory in $directories) {
    $loaded = Read-DreamSkinTheme -ThemeDirectory $directory -SkipImageMetadata
    $items += [pscustomobject]@{
      Id = "$($loaded.Theme.id)"
      Name = if ($loaded.Theme.name) { "$($loaded.Theme.name)" } else { Split-Path -Leaf $directory }
      Path = $directory
      Source = '内置'
    }
  }
  return $items
}

function Get-ThemeItems {
  $items = @()
  if (Test-DreamSkinEnginePresent) {
    foreach ($item in @(Get-DreamSkinSavedThemes -StateRoot $script:StateRoot -SkipImageMetadata)) {
      $items += [pscustomobject]@{ Id = $item.Id; Name = $item.Name; Path = $item.Path; Source = '已安装' }
    }
  } else {
    $items = @(Get-BundledThemeItems)
  }
  return @($items | Sort-Object Name)
}

function Test-ProtectedThemeId([string]$Id) {
  return $Id -eq 'builtin-pastel-ragnarok-duo'
}

function Assert-EditableSavedTheme([object]$Item) {
  if (-not (Test-DreamSkinEnginePresent)) { throw '请先安装 Dream Skin。' }
  if ($null -eq $Item -or -not $Item.Path) { throw '请先选择一个主题。' }
  if (Test-ProtectedThemeId -Id "$($Item.Id)") { throw '内置主题受到保护，不能重命名或删除。' }
  $paths = Get-DreamSkinThemePaths -StateRoot $script:StateRoot
  $directory = [System.IO.Path]::GetFullPath("$($Item.Path)")
  if (-not (Test-DreamSkinThemePathWithin -Path $directory -Root $paths.Saved)) {
    throw '只能管理 Dream Skin 收藏目录中的主题。'
  }
  $null = Read-DreamSkinTheme -ThemeDirectory $directory
  return $directory
}

function Rename-SavedTheme([object]$Item, [string]$NewName) {
  $trimmed = $NewName.Trim()
  if (-not $trimmed -or $trimmed.Length -gt 80 -or $trimmed -match '[\u0000-\u001f]') {
    throw '主题名称必须包含 1 到 80 个可见字符。'
  }
  $duplicates = @(Get-DreamSkinSavedThemes -StateRoot $script:StateRoot -SkipImageMetadata |
    Where-Object { $_.Id -ne $Item.Id -and $_.Name -ieq $trimmed })
  if ($duplicates.Count -gt 0) { throw "已经存在同名主题：$trimmed" }
  $directory = Assert-EditableSavedTheme -Item $Item
  $saved = Read-DreamSkinTheme -ThemeDirectory $directory
  $savedTheme = $saved.Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $savedTheme.name = $trimmed
  Write-DreamSkinTheme -ThemeDirectory $directory -Theme $savedTheme

  $active = Get-ActiveThemeInfo
  if ($active -and "$($active.Theme.id)" -eq "$($Item.Id)") {
    $activeTheme = $active.Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $activeTheme.name = $trimmed
    Write-DreamSkinTheme -ThemeDirectory $active.Directory -Theme $activeTheme
  }
}

function Remove-SavedTheme([object]$Item) {
  $directory = Assert-EditableSavedTheme -Item $Item
  $active = Get-ActiveThemeInfo
  if ($active -and "$($active.Theme.id)" -eq "$($Item.Id)") {
    throw '不能删除当前正在使用的主题；请先切换到另一个主题。'
  }
  $savedThemes = @(Get-DreamSkinSavedThemes -StateRoot $script:StateRoot -SkipImageMetadata)
  if ($savedThemes.Count -le 1) { throw '至少需要保留一个主题。' }
  Assert-DreamSkinNoReparseComponents -Path $directory
  Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction Stop
}

function Get-ActiveThemeInfo {
  if (-not (Test-DreamSkinEnginePresent)) { return $null }
  try { return Read-DreamSkinTheme -ThemeDirectory (Join-Path $script:StateRoot 'active-theme') -SkipImageMetadata } catch { return $null }
}

function Invoke-WithDreamSkinLock {
  param([Parameter(Mandatory = $true)][scriptblock]$Action)
  $operationLock = Enter-DreamSkinOperationLock
  try { & $Action } finally { Exit-DreamSkinOperationLock -Mutex $operationLock }
}

function Seed-BundledThemes {
  $paths = Get-DreamSkinThemePaths -StateRoot $script:StateRoot
  Ensure-DreamSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  Ensure-DreamSkinManagedDirectory -Path $paths.Saved -Root $paths.Root
  foreach ($sourceDirectory in @(
      (Join-Path $script:PackageRoot 'themes\builtin-pastel-ragnarok-duo'))) {
    $loaded = Read-DreamSkinTheme -ThemeDirectory $sourceDirectory
    $id = "$($loaded.Theme.id)"
    if ($id -notmatch '^[A-Za-z0-9._-]{1,80}$') { throw "内置主题 ID 无效：$id" }
    $destination = Join-Path $paths.Saved $id
    Ensure-DreamSkinManagedDirectory -Path $destination -Root $paths.Root
    foreach ($fileName in @('theme.json', "$($loaded.Theme.image)")) {
      $target = Join-Path $destination $fileName
      Assert-DreamSkinNoReparseComponents -Path $target
      Copy-Item -LiteralPath (Join-Path $sourceDirectory $fileName) -Destination $target -Force
    }
    $null = Read-DreamSkinTheme -ThemeDirectory $destination
  }
  foreach ($retiredId in @(
      'builtin-karyl-starry-magic',
      'preset-arina-hashimoto',
      'preset-gothic-void-crusade')) {
    $retiredDirectory = Join-Path $paths.Saved $retiredId
    Assert-DreamSkinNoReparseComponents -Path $retiredDirectory
    if (Test-Path -LiteralPath $retiredDirectory -PathType Container) {
      if (-not (Test-DreamSkinThemePathWithin -Path $retiredDirectory -Root $paths.Saved)) {
        throw "拒绝删除主题收藏目录之外的路径：$retiredDirectory"
      }
      Remove-Item -LiteralPath $retiredDirectory -Recurse -Force -ErrorAction Stop
    }
  }
  Use-DreamSkinSavedTheme -ThemeDirectory (Join-Path $paths.Saved 'builtin-pastel-ragnarok-duo') -StateRoot $script:StateRoot | Out-Null
}

function New-DreamSkinDesktopShortcuts {
  $shell = New-Object -ComObject WScript.Shell
  $desktop = [Environment]::GetFolderPath('Desktop')
  $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  $pinnedTaskbar = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
  if ($script:LauncherPath -and (Test-Path -LiteralPath $script:LauncherPath -PathType Leaf)) {
    $managerShortcut = $shell.CreateShortcut((Join-Path $desktop 'ChatGPT 皮肤管理器.lnk'))
    $managerShortcut.TargetPath = $script:LauncherPath
    $managerShortcut.WorkingDirectory = Split-Path -Parent $script:LauncherPath
    $managerShortcut.IconLocation = "$script:LauncherPath,0"
    $managerShortcut.Description = '打开 ChatGPT Dream Skin 便携主题管理器'
    $managerShortcut.Save()
  }
  if (Test-EngineInstalled) {
    $shortcutFolders = @($desktop, $startMenu)
    $pinnedShortcut = Join-Path $pinnedTaskbar 'ChatGPT（带皮肤启动）.lnk'
    if (Test-Path -LiteralPath $pinnedShortcut -PathType Leaf) { $shortcutFolders += $pinnedTaskbar }
    foreach ($folder in $shortcutFolders) {
      $skinShortcut = $shell.CreateShortcut((Join-Path $folder 'ChatGPT（带皮肤启动）.lnk'))
      if ($script:LauncherPath -and (Test-Path -LiteralPath $script:LauncherPath -PathType Leaf)) {
        $skinShortcut.TargetPath = $script:LauncherPath
        $skinShortcut.Arguments = '--start-skin'
        $skinShortcut.WorkingDirectory = Split-Path -Parent $script:LauncherPath
        $skinShortcut.IconLocation = "$script:LauncherPath,0"
      } else {
        $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
        $skinShortcut.TargetPath = $powershell
        $skinShortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$(Join-Path $script:EngineScripts 'start-dream-skin.ps1')`" -PromptRestart"
        $skinShortcut.WorkingDirectory = $script:EngineRoot
      }
      $skinShortcut.Description = '无控制台窗口启动带皮肤的 ChatGPT'
      $skinShortcut.Save()
    }
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    if (-not (Test-Path -LiteralPath $startup -PathType Container)) {
      [System.IO.Directory]::CreateDirectory($startup) | Out-Null
    }
    foreach ($legacy in @('Codex Dream Skin 更新守护.lnk','ChatGPT Dream Skin 更新守护.lnk','ChatGPT（带皮肤自动启动）.lnk')) {
      Remove-Item -LiteralPath (Join-Path $startup $legacy) -Force -ErrorAction SilentlyContinue
    }
    $settings = Get-DreamSkinManagerSettings
    if ([bool]$settings.updateWatcherEnabled) {
      Remove-Item -LiteralPath (Join-Path $script:StateRoot 'update-watcher.disabled') -Force -ErrorAction SilentlyContinue
      $startupName = if ([bool]$settings.autoStartSkinnedChatGPT) { 'ChatGPT（带皮肤自动启动）.lnk' } else { 'ChatGPT Dream Skin 更新守护.lnk' }
      $watcherShortcut = $shell.CreateShortcut((Join-Path $startup $startupName))
      if ($script:LauncherPath -and (Test-Path -LiteralPath $script:LauncherPath -PathType Leaf)) {
        $watcherShortcut.TargetPath = $script:LauncherPath
        $watcherShortcut.Arguments = if ([bool]$settings.autoStartSkinnedChatGPT) { '--startup-skin' } else { '--watch-updates' }
        $watcherShortcut.WorkingDirectory = Split-Path -Parent $script:LauncherPath
        $watcherShortcut.IconLocation = "$script:LauncherPath,0"
      } else {
        $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
        $watcherShortcut.TargetPath = $powershell
        $watcherShortcut.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$(Join-Path $script:EngineScripts 'watch-dream-skin-updates.ps1')`""
        $watcherShortcut.WorkingDirectory = $script:EngineRoot
      }
      $watcherShortcut.Description = '登录后启动带皮肤的 ChatGPT，并随官方版本更新恢复主题'
      $watcherShortcut.Save()
    } else {
      if (-not (Test-Path -LiteralPath $script:StateRoot -PathType Container)) { [System.IO.Directory]::CreateDirectory($script:StateRoot) | Out-Null }
      [System.IO.File]::WriteAllText((Join-Path $script:StateRoot 'update-watcher.disabled'), '', (New-Object System.Text.UTF8Encoding($false)))
    }
  }
}

function Stop-DreamSkinUpdateWatcher {
  $stopPath = Join-Path $script:StateRoot 'update-watcher.stop'
  if (-not (Test-Path -LiteralPath $script:StateRoot -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($script:StateRoot) | Out-Null
  }
  [System.IO.File]::WriteAllText($stopPath, "stop`r`n", (New-Object System.Text.UTF8Encoding($false)))
  Start-Sleep -Milliseconds 1200
}

function Start-DreamSkinUpdateWatcher {
  if (Test-DreamSkinUpdateWatcherDisabled) { return }
  $stopPath = Join-Path $script:StateRoot 'update-watcher.stop'
  Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
  if ($script:LauncherPath -and (Test-Path -LiteralPath $script:LauncherPath -PathType Leaf)) {
    Start-Process -FilePath $script:LauncherPath -ArgumentList '--watch-updates' -WindowStyle Hidden | Out-Null
    return
  }
  $watchScript = Join-Path $script:EngineScripts 'watch-dream-skin-updates.ps1'
  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  Start-Process -FilePath $powershell `
    -ArgumentList "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$watchScript`"" `
    -WindowStyle Hidden | Out-Null
}

function Install-OrRepairDreamSkin {
  $codex = Get-DreamSkinCodexInstall
  Stop-DreamSkinUpdateWatcher
  try {
    Stop-DreamSkinCodex -Codex $codex -AllowForce
    & (Join-Path $script:BundledScripts 'install-dream-skin.ps1') -NoShortcuts
    Invoke-WithDreamSkinLock { Seed-BundledThemes }
    New-DreamSkinDesktopShortcuts
  } finally {
    if (Test-EngineInstalled) { Start-DreamSkinUpdateWatcher }
  }
}

function Ensure-DreamSkinReady {
  param([switch]$Confirmed)
  if (Test-EngineInstalled) { return $true }
  if (-not $Confirmed) {
    $answer = [System.Windows.Forms.MessageBox]::Show($form,
      "首次使用会自动准备内置运行环境，不需要另装 Dream Skin 或 Node.js。`r`n准备过程需要关闭 Codex，请先保存未发送内容。是否继续？",
      '首次自动准备', 'YesNo', 'Warning')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
  }
  Install-OrRepairDreamSkin
  Refresh-ThemeList -SelectId 'builtin-pastel-ragnarok-duo'
  return $true
}

function Start-DreamSkinSession {
  param([switch]$RestartExisting)
  if (-not (Test-EngineInstalled)) { throw '请先点击《安装 / 修复 Dream Skin》。' }
  $startScript = Join-Path $script:EngineScripts 'start-dream-skin.ps1'
  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  $mode = if ($RestartExisting) { ' -RestartExisting' } else { ' -PromptRestart' }
  Start-Process -FilePath $powershell -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -File `"$startScript`"$mode" -WindowStyle Hidden | Out-Null
}

function Start-DreamSkinRestore {
  if (-not (Test-EngineInstalled)) { throw 'Dream Skin 尚未安装。' }
  $restoreScript = Join-Path $script:EngineScripts 'restore-dream-skin.ps1'
  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  Start-Process -FilePath $powershell -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -File `"$restoreScript`" -RestoreBaseTheme -PromptRestart" -WindowStyle Hidden | Out-Null
}

if ($SelfTest) {
  Add-Type -AssemblyName System.Drawing
  $required = @(
    'dream-skin\scripts\install-dream-skin.ps1',
    'dream-skin\scripts\start-dream-skin.ps1',
    'dream-skin\scripts\restore-dream-skin.ps1',
    'dream-skin\scripts\set-window-icon.ps1',
    'dream-skin\scripts\injector.mjs',
    'dream-skin\scripts\diagnose-shell.mjs',
    'dream-skin\assets\renderer-inject.js',
    'dream-skin\compatibility-baseline.json',
    'dream-skin\MAINTENANCE_PLAYBOOK.md',
    'dream-skin\runtime\node.exe',
    'dream-skin\runtime\LICENSE-node.txt',
    'assets\app-background.png',
    'assets\karyl-pixel.ico',
    'dream-skin\assets\karyl-window.ico',
    'dream-skin\assets\manager-version-1.4.7.txt',
    'dream-skin\scripts\watch-dream-skin-updates.ps1',
    'dream-skin\scripts\uninstall-dream-skin-manager.ps1'
  )
  foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:PackageRoot $relative) -PathType Leaf)) { throw "便携包缺少文件：$relative" }
  }
  $node = Get-DreamSkinNodeRuntime
  $checked = 0
  foreach ($item in @(Get-BundledThemeItems)) {
    $loaded = Read-DreamSkinTheme -ThemeDirectory $item.Path
    $bitmap = Get-ImageClone -Path $loaded.ImagePath
    try {
      if ($bitmap.Width -lt 1 -or $bitmap.Height -lt 1) { throw "主题图片尺寸无效：$($item.Name)" }
    } finally { $bitmap.Dispose() }
    $checked++
  }
  $result = [pscustomobject]@{
    Result = 'PASS'
    PackageVersion = '1.4.7'
    BundledThemes = $checked
    NodeVersion = $node.Version
    InstalledEngineDetected = [bool](Test-EngineInstalled)
  } | ConvertTo-Json -Depth 4
  if ($SelfTestOutput) {
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($SelfTestOutput), $result + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
  }
  $result
  exit 0
}

if ($RoundTripTestOutput) {
  if (-not (Test-EngineInstalled)) { throw 'Dream Skin 尚未安装，无法进行主题往返测试。' }
  if (-not $RoundTripScreenshotDirectory) { throw '主题往返测试需要截图目录。' }
  $resultPath = [System.IO.Path]::GetFullPath($RoundTripTestOutput)
  $screenshotRoot = [System.IO.Path]::GetFullPath($RoundTripScreenshotDirectory)
  if (-not (Test-Path -LiteralPath $screenshotRoot -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($screenshotRoot) | Out-Null
  }
  $savedThemes = @(Get-DreamSkinSavedThemes -StateRoot $script:StateRoot -SkipImageMetadata)
  $karyl = @($savedThemes | Where-Object { $_.Name -eq 'Karyl Starry Magic' }) | Select-Object -First 1
  $pastel = @($savedThemes | Where-Object { $_.Name -eq 'Pastel Ragnarok Duo' }) | Select-Object -First 1
  if (-not $karyl -or -not $pastel) { throw '未找到凯露主题或默认双人主题。' }
  $activeBefore = Get-ActiveThemeInfo
  $testResult = [ordered]@{
    Result = 'FAIL'
    ActiveBefore = if ($activeBefore) { "$($activeBefore.Theme.name)" } else { $null }
    SessionRestarted = $false
    KarylThemeApplied = $false
    KarylVerificationExitCode = $null
    KarylVerificationOutput = @()
    KarylScreenshot = Join-Path $screenshotRoot 'karyl-live.png'
    PastelThemeRestored = $false
    PastelVerificationExitCode = $null
    PastelVerificationOutput = @()
    PastelScreenshot = Join-Path $screenshotRoot 'pastel-restored-live.png'
    ActiveAfter = $null
    Error = $null
  }
  try {
    Invoke-WithDreamSkinLock { Use-DreamSkinSavedTheme -ThemeDirectory $karyl.Path -StateRoot $script:StateRoot | Out-Null }
    & (Join-Path $script:EngineScripts 'start-dream-skin.ps1') -RestartExisting
    $testResult.SessionRestarted = $true
    Start-Sleep -Seconds 3
    $karylActive = Get-ActiveThemeInfo
    $testResult.KarylThemeApplied = [bool]($karylActive -and "$($karylActive.Theme.name)" -eq 'Karyl Starry Magic')
    $session = Get-DreamSkinLiveSessionContext -StateRoot $script:StateRoot
    if (-not $session) { throw '未找到正在运行的 Dream Skin 会话。' }
    $karylProbe = Invoke-DreamSkinNative -FilePath $session.NodePath -ArgumentList @(
      $session.Injector, '--verify', '--port', "$($session.Port)", '--browser-id', $session.BrowserId,
      '--timeout-ms', '30000', '--screenshot', $testResult.KarylScreenshot
    )
    $testResult.KarylVerificationExitCode = $karylProbe.ExitCode
    $testResult.KarylVerificationOutput = @($karylProbe.Output)
    if (-not $testResult.KarylThemeApplied -or $karylProbe.ExitCode -ne 0 -or
      -not (Test-Path -LiteralPath $testResult.KarylScreenshot -PathType Leaf)) {
      throw '凯露主题应用或实时验证失败。'
    }
  } catch {
    $testResult.Error = $_.Exception.Message
  } finally {
    try {
      Invoke-WithDreamSkinLock { Use-DreamSkinSavedTheme -ThemeDirectory $pastel.Path -StateRoot $script:StateRoot | Out-Null }
      Start-Sleep -Seconds 4
      $pastelActive = Get-ActiveThemeInfo
      $testResult.PastelThemeRestored = [bool]($pastelActive -and "$($pastelActive.Theme.name)" -eq 'Pastel Ragnarok Duo')
      $sessionAfter = Get-DreamSkinLiveSessionContext -StateRoot $script:StateRoot
      if (-not $sessionAfter) { throw '恢复后未找到正在运行的 Dream Skin 会话。' }
      $pastelProbe = Invoke-DreamSkinNative -FilePath $sessionAfter.NodePath -ArgumentList @(
        $sessionAfter.Injector, '--verify', '--port', "$($sessionAfter.Port)", '--browser-id', $sessionAfter.BrowserId,
        '--timeout-ms', '30000', '--screenshot', $testResult.PastelScreenshot
      )
      $testResult.PastelVerificationExitCode = $pastelProbe.ExitCode
      $testResult.PastelVerificationOutput = @($pastelProbe.Output)
      if (-not $testResult.PastelThemeRestored -or $pastelProbe.ExitCode -ne 0 -or
        -not (Test-Path -LiteralPath $testResult.PastelScreenshot -PathType Leaf)) {
        if (-not $testResult.Error) { $testResult.Error = '默认双人主题恢复或实时验证失败。' }
      }
    } catch {
      if (-not $testResult.Error) { $testResult.Error = $_.Exception.Message }
    }
    $activeAfter = Get-ActiveThemeInfo
    $testResult.ActiveAfter = if ($activeAfter) { "$($activeAfter.Theme.name)" } else { $null }
    if ($testResult.KarylThemeApplied -and $testResult.KarylVerificationExitCode -eq 0 -and
      $testResult.PastelThemeRestored -and $testResult.PastelVerificationExitCode -eq 0 -and
      $testResult.ActiveAfter -eq 'Pastel Ragnarok Duo') {
      $testResult.Result = 'PASS'
      $testResult.Error = $null
    }
    $json = [pscustomobject]$testResult | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($resultPath, $json + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
  }
  if ($testResult.Result -ne 'PASS') { exit 1 }
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$cream = [System.Drawing.Color]::FromArgb(255, 250, 232)
$purple = [System.Drawing.Color]::FromArgb(91, 56, 132)
$violet = [System.Drawing.Color]::FromArgb(125, 84, 171)
$rose = [System.Drawing.Color]::FromArgb(204, 119, 139)
$ink = [System.Drawing.Color]::FromArgb(62, 43, 73)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'ChatGPT Dream Skin 便携主题管理器'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 700)
$form.BackColor = $cream
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$iconPath = Join-Path $script:PackageRoot 'assets\karyl-pixel.ico'
if (Test-Path -LiteralPath $iconPath -PathType Leaf) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }

$managerTray = New-Object System.Windows.Forms.NotifyIcon
$managerTray.Icon = if ($form.Icon) { $form.Icon } else { [System.Drawing.SystemIcons]::Application }
$managerTray.Text = 'ChatGPT Dream Skin 主题管理器'
$managerTray.Visible = $false
$managerTrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$managerTrayOpen = [System.Windows.Forms.ToolStripMenuItem]::new('打开主题管理器')
$managerTrayExit = [System.Windows.Forms.ToolStripMenuItem]::new('退出主题管理器')
[void]$managerTrayMenu.Items.Add($managerTrayOpen)
[void]$managerTrayMenu.Items.Add($managerTrayExit)
$managerTray.ContextMenuStrip = $managerTrayMenu

function Show-DreamSkinManagerWindow {
  if ($form.IsDisposed) { return }
  $form.ShowInTaskbar = $true
  $form.Show()
  $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
  $form.Activate()
  $managerTray.Visible = $false
}

$managerTrayOpen.Add_Click({ Show-DreamSkinManagerWindow })
$managerTray.Add_DoubleClick({ Show-DreamSkinManagerWindow })
$managerTrayExit.Add_Click({ $form.Close() })
$form.Add_Resize({
  if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
    $form.ShowInTaskbar = $false
    $form.Hide()
    $managerTray.Visible = $true
  }
})

$managerWakeTimer = New-Object System.Windows.Forms.Timer
$managerWakeTimer.Interval = 400
$managerWakeTimer.Add_Tick({
  if ($script:ManagerShowEvent -and $script:ManagerShowEvent.WaitOne(0)) {
    Show-DreamSkinManagerWindow
  }
})
if ($interactiveManager) { $managerWakeTimer.Start() }

$backgroundPath = Join-Path $script:PackageRoot 'assets\app-background.png'
$script:BackgroundBitmap = Get-ImageClone -Path $backgroundPath
$form.BackgroundImage = $script:BackgroundBitmap
$form.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Zoom

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 92
$header.BackColor = [System.Drawing.Color]::FromArgb(228, 255, 248, 219)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Codex Dream Skin'
$title.ForeColor = $purple
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(25, 13)
$title.AutoSize = $true
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = '图片可选择、拖入或按 Ctrl+V 粘贴；只有点击应用主题时才会重启 Codex'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(104, 75, 112)
$subtitle.Location = New-Object System.Drawing.Point(28, 59)
$subtitle.AutoSize = $true
$header.Controls.Add($subtitle)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = '正在检测 Dream Skin…'
$installButton.Location = New-Object System.Drawing.Point(932, 24)
$installButton.Size = New-Object System.Drawing.Size(220, 46)
$installButton.Anchor = 'Top,Right'
$installButton.FlatStyle = 'Flat'
$installButton.BackColor = $rose
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$header.Controls.Add($installButton)

$settingsButton = New-Object System.Windows.Forms.Button
$settingsButton.Text = '设置'
$settingsButton.Location = New-Object System.Drawing.Point(820, 24)
$settingsButton.Size = New-Object System.Drawing.Size(100, 46)
$settingsButton.Anchor = 'Top,Right'
$settingsButton.FlatStyle = 'Flat'
$settingsButton.BackColor = $violet
$settingsButton.ForeColor = [System.Drawing.Color]::White
$settingsButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$header.Controls.Add($settingsButton)

$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Location = New-Object System.Drawing.Point(20, 112)
$leftPanel.Size = New-Object System.Drawing.Size(310, 560)
$leftPanel.Anchor = 'Top,Bottom,Left'
$leftPanel.BackColor = [System.Drawing.Color]::FromArgb(238, 255, 252, 241)
$leftPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($leftPanel)

$themeLabel = New-Object System.Windows.Forms.Label
$themeLabel.Text = '主题收藏'
$themeLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$themeLabel.ForeColor = $ink
$themeLabel.Location = New-Object System.Drawing.Point(16, 15)
$themeLabel.AutoSize = $true
$leftPanel.Controls.Add($themeLabel)

$themeList = New-Object System.Windows.Forms.ListBox
$themeList.Location = New-Object System.Drawing.Point(16, 52)
$themeList.Size = New-Object System.Drawing.Size(276, 390)
$themeList.Anchor = 'Top,Bottom,Left,Right'
$themeList.BorderStyle = 'FixedSingle'
$themeList.IntegralHeight = $false
$themeList.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$themeList.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 246)
$leftPanel.Controls.Add($themeList)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = '刷新主题列表'
$refreshButton.Location = New-Object System.Drawing.Point(16, 458)
$refreshButton.Size = New-Object System.Drawing.Size(276, 36)
$refreshButton.Anchor = 'Bottom,Left,Right'
$leftPanel.Controls.Add($refreshButton)

$renameButton = New-Object System.Windows.Forms.Button
$renameButton.Text = '重命名'
$renameButton.Location = New-Object System.Drawing.Point(16, 502)
$renameButton.Size = New-Object System.Drawing.Size(132, 40)
$renameButton.Anchor = 'Bottom,Left'
$leftPanel.Controls.Add($renameButton)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = '删除主题'
$deleteButton.Location = New-Object System.Drawing.Point(160, 502)
$deleteButton.Size = New-Object System.Drawing.Size(132, 40)
$deleteButton.Anchor = 'Bottom,Right'
$deleteButton.ForeColor = [System.Drawing.Color]::FromArgb(150, 45, 58)
$leftPanel.Controls.Add($deleteButton)

$previewPanel = New-Object System.Windows.Forms.Panel
$previewPanel.Location = New-Object System.Drawing.Point(350, 112)
$previewPanel.Size = New-Object System.Drawing.Size(810, 456)
$previewPanel.Anchor = 'Top,Bottom,Left,Right'
$previewPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 232, 218)
$previewPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($previewPanel)

$preview = New-Object System.Windows.Forms.PictureBox
$preview.Dock = 'Fill'
$preview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$preview.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 226)
$previewPanel.Controls.Add($preview)

$activeLabel = New-Object System.Windows.Forms.Label
$activeLabel.Location = New-Object System.Drawing.Point(352, 580)
$activeLabel.Size = New-Object System.Drawing.Size(805, 26)
$activeLabel.Anchor = 'Bottom,Left,Right'
$activeLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$activeLabel.ForeColor = $ink
$form.Controls.Add($activeLabel)

$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Location = New-Object System.Drawing.Point(352, 608)
$infoLabel.Size = New-Object System.Drawing.Size(805, 42)
$infoLabel.Anchor = 'Bottom,Left,Right'
$infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(92, 69, 101)
$form.Controls.Add($infoLabel)

function New-ActionButton([string]$Text, [int]$X, [int]$Width, [System.Drawing.Color]$Color) {
  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Location = New-Object System.Drawing.Point($X, 686)
  $button.Size = New-Object System.Drawing.Size($Width, 48)
  $button.Anchor = 'Bottom,Left'
  $button.FlatStyle = 'Flat'
  $button.BackColor = $Color
  $button.ForeColor = [System.Drawing.Color]::White
  return $button
}

$applyButton = New-ActionButton '应用所选主题' 350 148 $violet
$importButton = New-ActionButton '导入图片主题…' 508 148 $rose
$startButton = New-ActionButton '启动 / 重载皮肤' 666 158 $purple
$restoreButton = New-ActionButton '恢复官方外观' 834 148 ([System.Drawing.Color]::FromArgb(112, 96, 120))
$folderButton = New-ActionButton '重建桌面入口' 992 168 ([System.Drawing.Color]::FromArgb(166, 120, 82))
foreach ($button in @($applyButton, $importButton, $startButton, $restoreButton, $folderButton)) { $form.Controls.Add($button) }
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($importButton, '点击选择本地图片，也可将图片拖到窗口，或复制图片后按 Ctrl+V。导入不会重启 Codex。')
$toolTip.SetToolTip($previewPanel, '可将 PNG、JPG、JPEG 或 WebP 图片拖到这里导入。')

function Show-AppError([string]$Message) {
  [System.Windows.Forms.MessageBox]::Show($form, $Message, 'Codex Dream Skin', 'OK', 'Error') | Out-Null
}

function Update-Status {
  $managerSettings = Get-DreamSkinManagerSettings
  $launchCheckLabel = if ([bool]$managerSettings.checkEveryCodexLaunch) { '每次启动检测：开启' } else { '每次启动检测：关闭' }
  $watcherLabel = if (Test-DreamSkinUpdateWatcherDisabled) { '更新守护：已禁用' } else { '更新守护：已启用' }
  if (Test-EngineInstalled) {
    $active = Get-ActiveThemeInfo
    $activeLabel.Text = if ($active) { "当前主题：$($active.Theme.name)" } else { '当前主题：Dream Skin 已安装，尚未识别活动主题' }
    $running = Test-Path -LiteralPath (Join-Path $script:StateRoot 'state.json')
    $infoLabel.Text = if ($running) {
      "状态：皮肤运行记录已存在；$watcherLabel；$launchCheckLabel。"
    } else {
      "状态：Dream Skin 已安装；$watcherLabel；$launchCheckLabel。"
    }
    $installButton.Text = 'Dream Skin 已安装'
  } elseif (Test-DreamSkinEnginePresent) {
    $active = Get-ActiveThemeInfo
    $activeLabel.Text = if ($active) { "当前主题：$($active.Theme.name)" } else { '当前主题：已检测到 Dream Skin' }
    $infoLabel.Text = "状态：Dream Skin 已安装，可更新到当前版本；$launchCheckLabel。"
    $installButton.Text = '更新 Dream Skin'
  } else {
    $activeLabel.Text = '当前状态：尚未安装 Dream Skin（可先预览内置主题）'
    $infoLabel.Text = '点击右上角安装；会安全关闭 Codex，并把默认双人主题设为首次主题。'
    $installButton.Text = '安装 Dream Skin'
  }
}

function Show-DreamSkinSettingsDialog {
  $settings = Get-DreamSkinManagerSettings
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = 'ChatGPT Dream Skin 设置'
  $dialog.StartPosition = 'CenterParent'
  $dialog.ClientSize = New-Object System.Drawing.Size(560, 390)
  $dialog.FormBorderStyle = 'FixedDialog'
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.Font = $form.Font
  $dialog.BackColor = [System.Drawing.Color]::FromArgb(255, 250, 242)
  if (Test-Path -LiteralPath $iconPath -PathType Leaf) { $dialog.Icon = New-Object System.Drawing.Icon($iconPath) }

  $dialogTitle = New-Object System.Windows.Forms.Label
  $dialogTitle.Text = '设置'
  $dialogTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 18, [System.Drawing.FontStyle]::Bold)
  $dialogTitle.ForeColor = $purple
  $dialogTitle.Location = New-Object System.Drawing.Point(24, 20)
  $dialogTitle.AutoSize = $true
  $dialog.Controls.Add($dialogTitle)

  $group = New-Object System.Windows.Forms.GroupBox
  $group.Text = '启动与更新'
  $group.Location = New-Object System.Drawing.Point(24, 70)
  $group.Size = New-Object System.Drawing.Size(512, 220)
  $dialog.Controls.Add($group)

  $launchCheck = New-Object System.Windows.Forms.CheckBox
  $launchCheck.Text = '每次启动 ChatGPT 时检查是否为带皮肤模式'
  $launchCheck.Checked = [bool]$settings.checkEveryCodexLaunch
  $launchCheck.Location = New-Object System.Drawing.Point(20, 30)
  $launchCheck.Size = New-Object System.Drawing.Size(460, 28)
  $group.Controls.Add($launchCheck)

  $description = New-Object System.Windows.Forms.Label
  $description.Text = '开启后，普通方式启动 ChatGPT 时会提示是否重启并恢复皮肤。'
  $description.ForeColor = [System.Drawing.Color]::FromArgb(104, 75, 112)
  $description.Location = New-Object System.Drawing.Point(20, 65)
  $description.Size = New-Object System.Drawing.Size(468, 30)
  $group.Controls.Add($description)

  $autoStart = New-Object System.Windows.Forms.CheckBox
  $autoStart.Text = '登录 Windows 后自动启动带皮肤的 ChatGPT'
  $autoStart.Checked = [bool]$settings.autoStartSkinnedChatGPT
  $autoStart.Location = New-Object System.Drawing.Point(20, 105)
  $autoStart.Size = New-Object System.Drawing.Size(460, 28)
  $group.Controls.Add($autoStart)

  $watchUpdates = New-Object System.Windows.Forms.CheckBox
  $watchUpdates.Text = '随 ChatGPT 官方版本更新自动修复皮肤兼容层'
  $watchUpdates.Checked = [bool]$settings.updateWatcherEnabled
  $watchUpdates.Location = New-Object System.Drawing.Point(20, 145)
  $watchUpdates.Size = New-Object System.Drawing.Size(460, 28)
  $group.Controls.Add($watchUpdates)

  $watchHint = New-Object System.Windows.Forms.Label
  $watchHint.Text = '自动启动依赖更新守护；关闭更新守护时不会创建任何开机启动项。'
  $watchHint.ForeColor = [System.Drawing.Color]::FromArgb(104, 75, 112)
  $watchHint.Location = New-Object System.Drawing.Point(20, 178)
  $watchHint.Size = New-Object System.Drawing.Size(468, 28)
  $group.Controls.Add($watchHint)

  $future = New-Object System.Windows.Forms.Label
  $future.Text = '以后新增的程序选项也会集中放在此设置窗口。'
  $future.ForeColor = [System.Drawing.Color]::FromArgb(127, 93, 62)
  $future.Location = New-Object System.Drawing.Point(28, 301)
  $future.AutoSize = $true
  $dialog.Controls.Add($future)

  $save = New-Object System.Windows.Forms.Button
  $save.Text = '保存'
  $save.DialogResult = 'OK'
  $save.Location = New-Object System.Drawing.Point(356, 342)
  $save.Size = New-Object System.Drawing.Size(84, 34)
  $dialog.Controls.Add($save)
  $dialog.AcceptButton = $save

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = '取消'
  $cancel.DialogResult = 'Cancel'
  $cancel.Location = New-Object System.Drawing.Point(452, 342)
  $cancel.Size = New-Object System.Drawing.Size(84, 34)
  $dialog.Controls.Add($cancel)
  $dialog.CancelButton = $cancel

  $result = $dialog.ShowDialog($form)
  $checked = $launchCheck.Checked
  $autoStartChecked = $autoStart.Checked
  $watchChecked = $watchUpdates.Checked
  $dialog.Dispose()
  if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    Save-DreamSkinManagerSettings -CheckEveryCodexLaunch $checked -AutoStartSkinnedChatGPT $autoStartChecked -UpdateWatcherEnabled $watchChecked
    New-DreamSkinDesktopShortcuts
    Update-Status
  }
}

function Show-SelectedPreview {
  $index = $themeList.SelectedIndex
  $editable = $index -ge 0 -and $index -lt $script:ThemeItems.Count -and
    (Test-DreamSkinEnginePresent) -and -not (Test-ProtectedThemeId -Id "$($script:ThemeItems[$index].Id)")
  $renameButton.Enabled = $editable
  $deleteButton.Enabled = $editable
  if ($index -lt 0 -or $index -ge $script:ThemeItems.Count) { return }
  try {
    $selected = $script:ThemeItems[$index]
    $loaded = Read-DreamSkinTheme -ThemeDirectory $selected.Path -SkipImageMetadata
    if ($script:PreviewBitmap) { $preview.Image = $null; $script:PreviewBitmap.Dispose(); $script:PreviewBitmap = $null }
    try {
    $script:PreviewBitmap = Get-ImageClone -Path $loaded.ImagePath
    $preview.Image = $script:PreviewBitmap
    $infoLabel.Text = "主题：$($selected.Name) · 来源：$($selected.Source) · 图片：$([System.IO.Path]::GetFileName($loaded.ImagePath))"
    } catch {
      $preview.Image = $null
      $infoLabel.Text = "主题：$($selected.Name) · 已成功导入；该图片格式无法在管理器中预览，但仍可正常应用。"
    }
  } catch { Show-AppError $_.Exception.Message }
}

function Refresh-ThemeList([string]$SelectId) {
  try {
    $script:ThemeItems = @(Get-ThemeItems)
    $themeList.BeginUpdate(); $themeList.Items.Clear(); $selectedIndex = -1
    for ($index = 0; $index -lt $script:ThemeItems.Count; $index++) {
      $item = $script:ThemeItems[$index]
      [void]$themeList.Items.Add("$($item.Name)  [$($item.Source)]")
      if ($SelectId -and $item.Id -eq $SelectId) { $selectedIndex = $index }
    }
    $themeList.EndUpdate()
    if ($selectedIndex -lt 0 -and $themeList.Items.Count -gt 0) { $selectedIndex = 0 }
    if ($selectedIndex -ge 0) { $themeList.SelectedIndex = $selectedIndex }
    if ($selectedIndex -lt 0) { $renameButton.Enabled = $false; $deleteButton.Enabled = $false }
    Update-Status
  } catch { Show-AppError $_.Exception.Message }
}

function Show-ThemeNameDialog([string]$DefaultName, [string]$Title = '保存新主题', [string]$AcceptText = '保存') {
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = $Title; $dialog.StartPosition = 'CenterParent'; $dialog.ClientSize = New-Object System.Drawing.Size(430, 155)
  $dialog.FormBorderStyle = 'FixedDialog'; $dialog.MaximizeBox = $false; $dialog.MinimizeBox = $false; $dialog.Font = $form.Font
  $label = New-Object System.Windows.Forms.Label; $label.Text = '主题名称：'; $label.Location = New-Object System.Drawing.Point(18, 18); $label.AutoSize = $true; $dialog.Controls.Add($label)
  $box = New-Object System.Windows.Forms.TextBox; $box.Text = $DefaultName; $box.Location = New-Object System.Drawing.Point(18, 48); $box.Size = New-Object System.Drawing.Size(394, 30); $dialog.Controls.Add($box)
  $ok = New-Object System.Windows.Forms.Button; $ok.Text = $AcceptText; $ok.DialogResult = 'OK'; $ok.Location = New-Object System.Drawing.Point(242, 100); $ok.Size = New-Object System.Drawing.Size(80, 34); $dialog.Controls.Add($ok); $dialog.AcceptButton = $ok
  $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = '取消'; $cancel.DialogResult = 'Cancel'; $cancel.Location = New-Object System.Drawing.Point(332, 100); $cancel.Size = New-Object System.Drawing.Size(80, 34); $dialog.Controls.Add($cancel); $dialog.CancelButton = $cancel
  $dialog.Add_Shown({ $box.SelectAll(); $box.Focus() })
  $result = $dialog.ShowDialog($form); $name = $box.Text.Trim(); $dialog.Dispose()
  if ($result -ne [System.Windows.Forms.DialogResult]::OK -or -not $name) { return $null }
  return $name
}

function Test-SupportedThemeImagePath([string]$Path) {
  if (-not $Path) { return $false }
  try {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
      ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -in @('.png', '.jpg', '.jpeg', '.webp'))
  } catch { return $false }
}

function Import-DreamSkinImageSource([string]$ImagePath, [string]$DefaultName) {
  if (-not (Test-DreamSkinEnginePresent)) {
    Show-AppError '请先点击右上角安装 Dream Skin。导入图片本身不会启动或重启 Codex。'
    return
  }
  if (-not (Test-SupportedThemeImagePath -Path $ImagePath)) {
    Show-AppError '请选择 PNG、JPG、JPEG 或 WebP 图片。'
    return
  }
  if (-not $DefaultName) { $DefaultName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath) }
  $name = Show-ThemeNameDialog -DefaultName $DefaultName -Title '导入图片主题' -AcceptText '导入'
  if (-not $name) { return }
  try {
    $saved = $null
    $theme = [pscustomobject]@{
      schemaVersion = 1
      name = $name
      appearance = 'auto'
      art = [pscustomobject]@{ focusX = 0.5; focusY = 0.45; safeArea = 'auto'; taskMode = 'ambient' }
      palette = [pscustomobject]@{ accent = '#6F3CA5' }
    }
    Invoke-WithDreamSkinLock {
      $saved = Import-DreamSkinSavedTheme -ImagePath $ImagePath -Theme $theme -Name $name -StateRoot $script:StateRoot
    }
    Refresh-ThemeList -SelectId "$($saved.Theme.id)"
    [System.Windows.Forms.MessageBox]::Show($form,
      "已导入到主题收藏：$name`r`n`r`nCodex 没有重启，当前皮肤也没有改变。需要使用时，请选择主题并点击《应用所选主题》。",
      '导入成功', 'OK', 'Information') | Out-Null
  } catch { Show-AppError $_.Exception.Message }
}

function Import-DreamSkinClipboardImage {
  try {
    if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
      $paths = @([System.Windows.Forms.Clipboard]::GetFileDropList())
      $imagePath = @($paths | Where-Object { Test-SupportedThemeImagePath -Path $_ }) | Select-Object -First 1
      if (-not $imagePath) { throw '剪贴板中的文件不包含受支持的图片。' }
      Import-DreamSkinImageSource -ImagePath $imagePath -DefaultName ([System.IO.Path]::GetFileNameWithoutExtension($imagePath))
      return
    }
    if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
      throw '剪贴板中没有图片。请复制图片本身或复制一个图片文件后再按 Ctrl+V。'
    }
    $clipboardImage = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $clipboardImage) { throw '无法读取剪贴板图片。' }
    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'CodexDreamSkinClipboard'
    [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
    $temporaryImage = Join-Path $temporaryDirectory ('clipboard-' + [guid]::NewGuid().ToString('N') + '.png')
    try {
      $clipboardImage.Save($temporaryImage, [System.Drawing.Imaging.ImageFormat]::Png)
      Import-DreamSkinImageSource -ImagePath $temporaryImage -DefaultName ('剪贴板主题-' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
    } finally {
      $clipboardImage.Dispose()
      if (Test-Path -LiteralPath $temporaryImage -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryImage -Force -ErrorAction SilentlyContinue
      }
    }
  } catch { Show-AppError $_.Exception.Message }
}

$themeList.Add_SelectedIndexChanged({ Show-SelectedPreview })
$refreshButton.Add_Click({ Refresh-ThemeList })
$renameButton.Add_Click({
  $index = $themeList.SelectedIndex
  if ($index -lt 0 -or $index -ge $script:ThemeItems.Count) { Show-AppError '请先选择一个主题。'; return }
  $selected = $script:ThemeItems[$index]
  if (Test-ProtectedThemeId -Id "$($selected.Id)") { Show-AppError '内置主题受到保护，不能重命名。'; return }
  $name = Show-ThemeNameDialog -DefaultName $selected.Name -Title '重命名主题' -AcceptText '重命名'
  if (-not $name -or $name -ceq $selected.Name) { return }
  try {
    Invoke-WithDreamSkinLock { Rename-SavedTheme -Item $selected -NewName $name }
    Refresh-ThemeList -SelectId $selected.Id
    [System.Windows.Forms.MessageBox]::Show($form, "主题已重命名为：$name", '重命名成功', 'OK', 'Information') | Out-Null
  } catch { Show-AppError $_.Exception.Message }
})
$deleteButton.Add_Click({
  $index = $themeList.SelectedIndex
  if ($index -lt 0 -or $index -ge $script:ThemeItems.Count) { Show-AppError '请先选择一个主题。'; return }
  $selected = $script:ThemeItems[$index]
  if (Test-ProtectedThemeId -Id "$($selected.Id)") { Show-AppError '内置主题受到保护，不能删除。'; return }
  $answer = [System.Windows.Forms.MessageBox]::Show($form,
    "确定永久删除主题《$($selected.Name)》吗？`r`n此操作只删除该主题文件，不会修改 Codex、任务或登录信息。",
    '确认删除主题', 'YesNo', 'Warning')
  if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  try {
    if ($script:PreviewBitmap) { $preview.Image = $null; $script:PreviewBitmap.Dispose(); $script:PreviewBitmap = $null }
    Invoke-WithDreamSkinLock { Remove-SavedTheme -Item $selected }
    Refresh-ThemeList
    [System.Windows.Forms.MessageBox]::Show($form, "已删除主题：$($selected.Name)", '删除成功', 'OK', 'Information') | Out-Null
  } catch { Show-AppError $_.Exception.Message }
})

$installButton.Add_Click({
  $answer = [System.Windows.Forms.MessageBox]::Show($form,
    "安装或修复时需要关闭 Codex。请先保存或发送尚未提交的输入。`r`n`r`n程序不会修改 WindowsApps，也不会删除任务、登录信息或插件。是否继续？",
    '确认安装 / 修复', 'YesNo', 'Warning')
  if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  try {
    $form.UseWaitCursor = $true; $form.Enabled = $false; [System.Windows.Forms.Application]::DoEvents()
    Install-OrRepairDreamSkin
    Refresh-ThemeList -SelectId 'builtin-pastel-ragnarok-duo'
    [System.Windows.Forms.MessageBox]::Show($form, '运行环境已准备完成，并已创建两个桌面入口。以后请从《ChatGPT（带皮肤启动）》打开 ChatGPT。', '准备成功', 'OK', 'Information') | Out-Null
    Start-DreamSkinSession -RestartExisting
  } catch { Show-AppError $_.Exception.Message } finally { $form.Enabled = $true; $form.UseWaitCursor = $false }
})

$settingsButton.Add_Click({
  try { Show-DreamSkinSettingsDialog } catch { Show-AppError $_.Exception.Message }
})

$applyButton.Add_Click({
  $index = $themeList.SelectedIndex
  if ($index -lt 0 -or $index -ge $script:ThemeItems.Count) { Show-AppError '请先选择一个主题。'; return }
  $selectedName = $script:ThemeItems[$index].Name
  $answer = [System.Windows.Forms.MessageBox]::Show($form,
    "应用主题会自动准备运行环境，并重启 Codex 以保证皮肤立即生效。`r`n请先保存未发送内容。是否继续？",
    '确认应用主题', 'YesNo', 'Warning')
  if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  try {
    $form.UseWaitCursor = $true; $form.Enabled = $false; [System.Windows.Forms.Application]::DoEvents()
    if (-not (Ensure-DreamSkinReady -Confirmed)) { return }
    New-DreamSkinDesktopShortcuts
    $selected = @(Get-ThemeItems | Where-Object { $_.Name -eq $selectedName }) | Select-Object -First 1
    if (-not $selected) { throw "准备完成后未找到主题：$selectedName" }
    Invoke-WithDreamSkinLock { Use-DreamSkinSavedTheme -ThemeDirectory $selected.Path -StateRoot $script:StateRoot | Out-Null }
    Update-Status
    Start-DreamSkinSession -RestartExisting
    [System.Windows.Forms.MessageBox]::Show($form, "已切换到：$($selected.Name)`r`nCodex 正在以皮肤模式重新启动。", '切换成功', 'OK', 'Information') | Out-Null
  } catch { Show-AppError $_.Exception.Message } finally { $form.Enabled = $true; $form.UseWaitCursor = $false }
})

$importButton.Add_Click({
  $open = New-Object System.Windows.Forms.OpenFileDialog
  $open.Title = '选择主题图片'; $open.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.webp|所有文件|*.*'; $open.Multiselect = $false
  if ($open.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { $open.Dispose(); return }
  $imagePath = $open.FileName; $open.Dispose()
  Import-DreamSkinImageSource -ImagePath $imagePath -DefaultName ([System.IO.Path]::GetFileNameWithoutExtension($imagePath))
})

$form.AllowDrop = $true
$previewPanel.AllowDrop = $true
$preview.AllowDrop = $true
$importButton.AllowDrop = $true
$form.KeyPreview = $true
$dragEnterHandler = {
  param($sender, $e)
  if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
    $paths = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
    if (@($paths | Where-Object { Test-SupportedThemeImagePath -Path $_ }).Count -gt 0) {
      $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
      return
    }
  }
  $e.Effect = [System.Windows.Forms.DragDropEffects]::None
}
$dragDropHandler = {
  param($sender, $e)
  try {
    $paths = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
    $imagePath = @($paths | Where-Object { Test-SupportedThemeImagePath -Path $_ }) | Select-Object -First 1
    if (-not $imagePath) { throw '拖入的内容中没有 PNG、JPG、JPEG 或 WebP 图片。' }
    Import-DreamSkinImageSource -ImagePath $imagePath -DefaultName ([System.IO.Path]::GetFileNameWithoutExtension($imagePath))
  } catch { Show-AppError $_.Exception.Message }
}
foreach ($dropTarget in @($form, $previewPanel, $preview, $importButton)) {
  $dropTarget.Add_DragEnter($dragEnterHandler)
  $dropTarget.Add_DragDrop($dragDropHandler)
}
$form.Add_KeyDown({
  param($sender, $e)
  if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::V) {
    $e.SuppressKeyPress = $true
    Import-DreamSkinClipboardImage
  }
})

$startButton.Add_Click({
  try {
    if (-not (Ensure-DreamSkinReady)) { return }
    New-DreamSkinDesktopShortcuts
    Start-DreamSkinSession -RestartExisting
    $infoLabel.Text = 'Codex 正在以皮肤模式重新启动。'
  } catch { Show-AppError $_.Exception.Message }
})
$restoreButton.Add_Click({
  if (-not (Test-EngineInstalled)) { Show-AppError 'Dream Skin 尚未安装。'; return }
  $answer = [System.Windows.Forms.MessageBox]::Show($form, '这会关闭皮肤并恢复 Codex 官方外观，但会保留所有主题以便日后切回。是否继续？', '确认恢复', 'YesNo', 'Question')
  if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) { try { Start-DreamSkinRestore; $infoLabel.Text = '已请求恢复官方外观；主题收藏仍然保留。' } catch { Show-AppError $_.Exception.Message } }
})
$folderButton.Add_Click({
  try {
    if (-not (Ensure-DreamSkinReady)) { return }
    New-DreamSkinDesktopShortcuts
    [System.Windows.Forms.MessageBox]::Show($form, '已在桌面创建《ChatGPT 皮肤管理器》和《ChatGPT（带皮肤启动）》两个入口。', '桌面入口已创建', 'OK', 'Information') | Out-Null
  } catch { Show-AppError $_.Exception.Message }
})

$form.Add_FormClosed({
  $managerWakeTimer.Stop(); $managerWakeTimer.Dispose()
  $managerTray.Visible = $false; $managerTray.ContextMenuStrip = $null; $managerTray.Dispose()
  $managerTrayMenu.Dispose()
  if ($script:PreviewBitmap) { $script:PreviewBitmap.Dispose(); $script:PreviewBitmap = $null }
  if ($script:BackgroundBitmap) { $form.BackgroundImage = $null; $script:BackgroundBitmap.Dispose(); $script:BackgroundBitmap = $null }
  if ($script:ManagerShowEvent) { $script:ManagerShowEvent.Dispose(); $script:ManagerShowEvent = $null }
  if ($script:ManagerMutexAcquired -and $script:ManagerMutex) { try { $script:ManagerMutex.ReleaseMutex() } catch {} }
  if ($script:ManagerMutex) { $script:ManagerMutex.Dispose(); $script:ManagerMutex = $null }
})
$form.Add_Shown({ Refresh-ThemeList })

if ($RenderPreview) {
  $form.Show(); [System.Windows.Forms.Application]::DoEvents(); Refresh-ThemeList -SelectId 'builtin-pastel-ragnarok-duo'; [System.Windows.Forms.Application]::DoEvents()
  $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
  try { $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height))); $bitmap.Save([System.IO.Path]::GetFullPath($RenderPreview), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose(); $form.Close() }
  exit 0
}

Update-Status
[void]$form.ShowDialog()
