[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PortableRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$stateRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'))
$managerCacheRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'CodexDreamSkinManager'))
$portableRootFull = [System.IO.Path]::GetFullPath($PortableRoot).TrimEnd('\')
$managerExe = Join-Path $portableRootFull 'Codex Dream Skin 主题管理器.exe'
$uninstallerExe = Join-Path $portableRootFull '卸载 Codex Dream Skin.exe'
$restoreScript = Join-Path $PSScriptRoot 'restore-dream-skin.ps1'
$stopPath = Join-Path $stateRoot 'update-watcher.stop'

function Assert-SafeExactDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Expected,
    [switch]$RequirePortableMarkers
  )
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
  $expectedFull = [System.IO.Path]::GetFullPath($Expected).TrimEnd('\')
  if ($full -ine $expectedFull) { throw "拒绝删除未经验证的目录：$full" }
  if ([System.IO.Path]::GetPathRoot($full).TrimEnd('\') -ieq $full) {
    throw "拒绝删除磁盘根目录：$full"
  }
  if ($full -ieq [Environment]::GetFolderPath('UserProfile') -or
    $full -ieq [Environment]::GetFolderPath('Desktop')) {
    throw "拒绝删除用户目录：$full"
  }
  if ($RequirePortableMarkers -and
    (-not (Test-Path -LiteralPath $managerExe -PathType Leaf) -or
      -not (Test-Path -LiteralPath $uninstallerExe -PathType Leaf))) {
    throw '便携程序目录缺少卸载安全标记，已停止删除。'
  }
  if (Test-Path -LiteralPath $full) {
    Assert-DreamSkinNoReparseComponents -Path $full
    foreach ($item in Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction Stop) {
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "目录包含符号链接或联接点，已停止删除：$($item.FullName)"
      }
    }
  }
}

function Remove-ManagedShortcut {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $target = "$($shortcut.TargetPath)"
    $arguments = "$($shortcut.Arguments)"
    $isManagerTarget = $target -and (Test-DreamSkinPathEqual -Left $target -Right $managerExe)
    $isUninstallerTarget = $target -and (Test-DreamSkinPathEqual -Left $target -Right $uninstallerExe)
    $isLegacyEngineTarget = $target -match '(?i)powershell(?:\.exe)?$' -and
      $arguments.IndexOf($stateRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
      $arguments -match '(?i)(start|restore|tray|watch)-dream-skin'
    if ($isManagerTarget -or $isUninstallerTarget -or $isLegacyEngineTarget) {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
  } catch {
    throw "无法安全检查或删除快捷方式：$Path。$($_.Exception.Message)"
  }
}

function Stop-ManagedPowerShellProcesses {
  try {
    $candidates = @(Get-CimInstance Win32_Process `
      -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop)
    foreach ($candidate in $candidates) {
      if ([int]$candidate.ProcessId -eq $PID -or -not $candidate.CommandLine) { continue }
      $commandLine = "$($candidate.CommandLine)"
      $isManager = $commandLine.IndexOf(
        'CodexSkinManagerPortable.ps1',
        [System.StringComparison]::OrdinalIgnoreCase) -ge 0
      $isOurCache = $commandLine.IndexOf(
        $managerCacheRoot,
        [System.StringComparison]::OrdinalIgnoreCase) -ge 0
      if ($isManager -and $isOurCache) {
        Stop-Process -Id ([int]$candidate.ProcessId) -Force -ErrorAction Stop
      }
    }
  } catch {
    throw "无法安全关闭主题管理器进程：$($_.Exception.Message)"
  }
}

function Wait-UpdateWatcherExit {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $watcherMutex = [System.Threading.Mutex]::new($false, "Local\CodexDreamSkin.$sid.UpdateWatcher")
  $acquiredWatcher = $false
  try {
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
      try {
        $acquiredWatcher = $watcherMutex.WaitOne(250)
      } catch [System.Threading.AbandonedMutexException] {
        $acquiredWatcher = $true
      }
      if ($acquiredWatcher) { return }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw '更新守护未在 45 秒内安全退出，已停止卸载。'
  } finally {
    if ($acquiredWatcher) {
      try { $watcherMutex.ReleaseMutex() } catch {}
    }
    $watcherMutex.Dispose()
  }
}

function Wait-PortableLaunchersExit {
  $deadline = [DateTime]::UtcNow.AddSeconds(12)
  do {
    $remaining = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
      $path = $null
      try { $path = $process.Path } catch {}
      if (-not $path) { continue }
      if ((Test-DreamSkinPathEqual -Left $path -Right $managerExe) -or
        (Test-DreamSkinPathEqual -Left $path -Right $uninstallerExe)) {
        $remaining += $process
      }
    }
    if ($remaining.Count -eq 0) { return }
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)
  throw '卸载启动程序仍在运行，未删除便携程序目录。'
}

try {
  Assert-SafeExactDirectory -Path $portableRootFull -Expected $portableRootFull -RequirePortableMarkers
  Assert-SafeExactDirectory -Path $stateRoot -Expected (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin')
  Assert-SafeExactDirectory -Path $managerCacheRoot -Expected (Join-Path $env:LOCALAPPDATA 'CodexDreamSkinManager')

  if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($stateRoot) | Out-Null
  }
  [System.IO.File]::WriteAllText($stopPath, "stop`r`n", (New-Object System.Text.UTF8Encoding($false)))
  Wait-UpdateWatcherExit
  Stop-ManagedPowerShellProcesses

  $backup = Join-Path $stateRoot 'config.before-dream-skin.toml'
  $config = Join-Path $env:USERPROFILE '.codex\config.toml'
  if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -and
    (Test-Path -LiteralPath $config -PathType Leaf)) {
    $configContent = [System.IO.File]::ReadAllText($config, (New-Object System.Text.UTF8Encoding($false, $true)))
    if ($configContent.Contains($script:DreamSkinManagedLightCodeTheme) -or
      $configContent.Contains($script:DreamSkinManagedLightChromeTheme)) {
      throw '缺少安装前配置备份，无法证明可以安全恢复 Codex 外观；已保留所有文件等待人工处理。'
    }
  }
  if (Test-Path -LiteralPath $restoreScript -PathType Leaf) {
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
      & $restoreScript -Uninstall -RestoreBaseTheme -ForceRestart
    } elseif (Test-Path -LiteralPath (Join-Path $stateRoot 'state.json') -PathType Leaf) {
      & $restoreScript -Uninstall -ForceRestart
    }
  }

  $desktop = [Environment]::GetFolderPath('Desktop')
  $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  $productStartMenu = Join-Path $startMenu 'Codex Dream Skin'
  $chatGptProductStartMenu = Join-Path $startMenu 'ChatGPT Dream Skin'
  $startup = Join-Path $startMenu 'Startup'
  $pinnedTaskbar = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
  foreach ($shortcutPath in @(
      (Join-Path $desktop 'Codex 皮肤管理器.lnk'),
      (Join-Path $desktop 'Codex（带皮肤启动）.lnk'),
      (Join-Path $desktop 'ChatGPT 皮肤管理器.lnk'),
      (Join-Path $desktop 'ChatGPT（带皮肤启动）.lnk'),
      (Join-Path $desktop 'Codex Dream Skin.lnk'),
      (Join-Path $desktop 'Codex Dream Skin - Restore.lnk'),
      (Join-Path $desktop 'Codex Dream Skin - Tray.lnk'),
      (Join-Path $startMenu 'Codex（带皮肤启动）.lnk'),
      (Join-Path $startMenu 'Codex 皮肤管理器.lnk'),
      (Join-Path $startMenu 'ChatGPT（带皮肤启动）.lnk'),
      (Join-Path $startMenu 'ChatGPT 皮肤管理器.lnk'),
      (Join-Path $startMenu 'Codex Dream Skin.lnk'),
      (Join-Path $startMenu 'Codex Dream Skin - Tray.lnk'),
      (Join-Path $productStartMenu 'Codex 皮肤管理器.lnk'),
      (Join-Path $productStartMenu 'Codex（带皮肤启动）.lnk'),
      (Join-Path $productStartMenu '卸载 Codex Dream Skin.lnk'),
      (Join-Path $chatGptProductStartMenu 'ChatGPT 皮肤管理器.lnk'),
      (Join-Path $chatGptProductStartMenu 'ChatGPT（带皮肤启动）.lnk'),
      (Join-Path $chatGptProductStartMenu '卸载 Codex Dream Skin.lnk'),
      (Join-Path $startup 'Codex Dream Skin 更新守护.lnk'),
      (Join-Path $startup 'ChatGPT Dream Skin 更新守护.lnk'),
      (Join-Path $startup 'ChatGPT（带皮肤自动启动）.lnk'),
      (Join-Path $pinnedTaskbar 'Codex（带皮肤启动）.lnk'),
      (Join-Path $pinnedTaskbar 'ChatGPT（带皮肤启动）.lnk'))) {
    Remove-ManagedShortcut -Path $shortcutPath
  }
  if ((Test-Path -LiteralPath $productStartMenu -PathType Container) -and
    @(Get-ChildItem -LiteralPath $productStartMenu -Force -ErrorAction Stop).Count -eq 0) {
    Remove-Item -LiteralPath $productStartMenu -Force -ErrorAction Stop
  }
  if ((Test-Path -LiteralPath $chatGptProductStartMenu -PathType Container) -and
    @(Get-ChildItem -LiteralPath $chatGptProductStartMenu -Force -ErrorAction Stop).Count -eq 0) {
    Remove-Item -LiteralPath $chatGptProductStartMenu -Force -ErrorAction Stop
  }

  if (-not (Test-Path -LiteralPath $env:TEMP -PathType Container)) {
    throw '系统临时目录不可用，无法安全释放程序目录。'
  }
  Set-Location -LiteralPath $env:TEMP
  Start-Sleep -Milliseconds 800
  if (Test-Path -LiteralPath $stateRoot -PathType Container) {
    Assert-SafeExactDirectory -Path $stateRoot -Expected (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin')
    Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction Stop
  }
  if (Test-Path -LiteralPath $managerCacheRoot -PathType Container) {
    Assert-SafeExactDirectory -Path $managerCacheRoot -Expected (Join-Path $env:LOCALAPPDATA 'CodexDreamSkinManager')
    Remove-Item -LiteralPath $managerCacheRoot -Recurse -Force -ErrorAction Stop
  }

  Wait-PortableLaunchersExit
  Assert-SafeExactDirectory -Path $portableRootFull -Expected $portableRootFull -RequirePortableMarkers
  Remove-Item -LiteralPath $portableRootFull -Recurse -Force -ErrorAction Stop

  [System.Windows.Forms.MessageBox]::Show(
    'Codex Dream Skin 已完全卸载，Codex 外观已恢复。未修改其他系统设置或用户文件。',
    '卸载完成',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  ) | Out-Null
} catch {
  [System.Windows.Forms.MessageBox]::Show(
    "卸载未能安全完成，已停止后续删除：`r`n$($_.Exception.Message)",
    'Codex Dream Skin 卸载失败',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error
  ) | Out-Null
  exit 1
}
