[CmdletBinding()]
param(
  [ValidateRange(15, 300)][int]$IntervalSeconds = 30,
  [switch]$RunOnce
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$statePath = Join-Path $stateRoot 'state.json'
$watchStatePath = Join-Path $stateRoot 'update-watcher.json'
$settingsPath = Join-Path $stateRoot 'manager-settings.json'
$watchErrorPath = Join-Path $stateRoot 'update-watcher-error.log'
$stopPath = Join-Path $stateRoot 'update-watcher.stop'
$disabledMarker = Join-Path $stateRoot 'update-watcher.disabled'
$startScript = Join-Path $PSScriptRoot 'start-dream-skin.ps1'
$restoreScript = Join-Path $PSScriptRoot 'restore-dream-skin.ps1'
$verifyScript = Join-Path $PSScriptRoot 'verify-dream-skin.ps1'
$versionMarker = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\manager-version-1.4.8.txt'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$launcherPath = $env:CODEX_DREAM_SKIN_LAUNCHER
$script:watcherExitRequested = $false

if (Test-Path -LiteralPath $disabledMarker -PathType Leaf) { exit 0 }

function Read-UpdateWatcherState {
  if (-not (Test-Path -LiteralPath $watchStatePath -PathType Leaf)) {
    return [pscustomobject]@{}
  }
  try {
    return Get-Content -LiteralPath $watchStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{}
  }
}

function Write-UpdateWatcherState {
  param([Parameter(Mandatory = $true)][object]$State)
  Write-DreamSkinUtf8FileAtomically -Path $watchStatePath `
    -Content (($State | ConvertTo-Json -Depth 5) + "`r`n")
}

function Write-UpdateWatcherError {
  param([string]$Message)
  $content = "$(Get-Date -Format o) $Message`r`n"
  try { Write-DreamSkinUtf8FileAtomically -Path $watchErrorPath -Content $content } catch {}
}

function Read-DreamSkinManagerSettings {
  $defaults = [pscustomobject]@{ schemaVersion = 1; checkEveryCodexLaunch = $true }
  if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return $defaults }
  try {
    $saved = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saved.schemaVersion -and [int]$saved.schemaVersion -gt 0 -and
      $saved.checkEveryCodexLaunch -is [bool]) {
      return $saved
    }
  } catch {}
  return $defaults
}

function Start-HiddenDreamSkinScript {
  param(
    [Parameter(Mandatory = $true)][string]$Script,
    [AllowEmptyCollection()][string[]]$Arguments = @(),
    [switch]$Wait
  )
  $argumentLine = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ' +
    (ConvertTo-DreamSkinProcessArgument -Value $Script)
  if ($Arguments.Count -gt 0) { $argumentLine += ' ' + ($Arguments -join ' ') }
  $parameters = @{
    FilePath = $powershell
    ArgumentList = $argumentLine
    WindowStyle = 'Hidden'
    PassThru = $true
  }
  if ($Wait) { $parameters.Wait = $true }
  return Start-Process @parameters
}

function Get-CodexProcessKey {
  param([AllowEmptyCollection()][object[]]$Processes)
  return (@($Processes | ForEach-Object { [int]$_.ProcessId } | Sort-Object) -join ',')
}

function Show-UpdateWatcherQuestion {
  param([string]$Message, [string]$Title = 'ChatGPT Dream Skin 更新守护')
  return [System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning
  ) -eq [System.Windows.Forms.DialogResult]::Yes
}

function Open-DreamSkinManager {
  if ($launcherPath -and (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    Start-Process -FilePath $launcherPath -WindowStyle Normal | Out-Null
    return
  }
  [System.Windows.Forms.MessageBox]::Show(
    '找不到当前主题管理器入口，请从桌面的“ChatGPT 皮肤管理器”打开。',
    'ChatGPT Dream Skin 安全守护',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  ) | Out-Null
}

$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = [System.Threading.Mutex]::new($false, "Local\CodexDreamSkin.$sid.UpdateWatcher")
$acquired = $false
$notify = $null
$trayMenu = $null
try {
  try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { exit 0 }

  if (Test-Path -LiteralPath $stopPath -PathType Leaf) {
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
  }

  $notify = [System.Windows.Forms.NotifyIcon]::new()
  $iconPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\karyl-window.ico'
  if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
    $notify.Icon = [System.Drawing.Icon]::new($iconPath)
  } else {
    $notify.Icon = [System.Drawing.SystemIcons]::Application
  }
  $notify.Text = 'ChatGPT Dream Skin 安全守护（双击打开管理器）'
  $trayMenu = [System.Windows.Forms.ContextMenuStrip]::new()
  $openItem = [System.Windows.Forms.ToolStripMenuItem]::new('打开主题管理器')
  $openItem.Add_Click({ Open-DreamSkinManager })
  $statusItem = [System.Windows.Forms.ToolStripMenuItem]::new('Dream Skin 安全守护正在运行')
  $statusItem.Enabled = $false
  $exitItem = [System.Windows.Forms.ToolStripMenuItem]::new('完全退出更新守护')
  $exitItem.Add_Click({
    $script:watcherExitRequested = $true
    try {
      if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($stateRoot) | Out-Null
      }
      [System.IO.File]::WriteAllText(
        $stopPath,
        "stop`r`n",
        [System.Text.UTF8Encoding]::new($false)
      )
    } catch {}
  })
  [void]$trayMenu.Items.Add($openItem)
  [void]$trayMenu.Items.Add($statusItem)
  [void]$trayMenu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
  [void]$trayMenu.Items.Add($exitItem)
  $notify.ContextMenuStrip = $trayMenu
  $notify.Add_DoubleClick({ Open-DreamSkinManager })
  $notify.Visible = $true

  $watchState = Read-UpdateWatcherState
  $lastHealthCheck = [DateTime]::MinValue
  $healthFailures = 0

  do {
    [System.Windows.Forms.Application]::DoEvents()
    if ($script:watcherExitRequested -or (Test-Path -LiteralPath $stopPath -PathType Leaf)) { break }
    if (-not (Test-Path -LiteralPath $versionMarker -PathType Leaf)) { break }

    try {
      $codex = Get-DreamSkinCodexInstall
      $processes = @(Get-DreamSkinCodexProcesses -Codex $codex)
      $session = Read-DreamSkinState -Path $statePath
      $port = if ($null -ne $session -and $session.port) { [int]$session.port } else { 9335 }
      $identity = if ($processes.Count -gt 0) {
        Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $codex
      } else {
        $null
      }
      $healthy = $null -ne $identity -and $null -ne $session -and
        "$($session.browserId)" -ceq "$($identity.BrowserId)" -and
        "$($session.codexVersion)" -ceq "$($codex.Version)"

      $processKey = Get-CodexProcessKey -Processes $processes
      $promptKey = "$($codex.Version)|$processKey"
      $savedVersionDiffers = $null -ne $session -and
        "$($session.codexVersion)" -cne "$($codex.Version)"
      $lastSeenDiffers = $watchState.lastSeenVersion -and
        "$($watchState.lastSeenVersion)" -cne "$($codex.Version)"
      $managerSettings = Read-DreamSkinManagerSettings
      $checkThisLaunch = [bool]$managerSettings.checkEveryCodexLaunch -and -not $healthy
      $snoozed = $false
      if ($watchState.snoozeUntil) {
        try { $snoozed = [DateTime]::Parse("$($watchState.snoozeUntil)").ToUniversalTime() -gt [DateTime]::UtcNow } catch {}
      }
      $startErrorPath = Join-Path $stateRoot 'start-error.log'
      if (Test-Path -LiteralPath $startErrorPath -PathType Leaf) {
        try {
          $recentFailure = (Get-Item -LiteralPath $startErrorPath -Force).LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-30)
          if ($recentFailure) { $snoozed = $true }
        } catch {}
      }

      if ($processes.Count -gt 0 -and -not $healthy -and
        ($savedVersionDiffers -or $lastSeenDiffers -or $checkThisLaunch) -and
        "$($watchState.lastPromptKey)" -cne $promptKey -and -not $snoozed) {
        $reason = if ($savedVersionDiffers -or $lastSeenDiffers) {
          "检测到 Codex 已更新为 $($codex.Version)，当前是普通启动模式。"
        } else {
          '检测到 Codex 本次不是以带皮肤模式启动。'
        }
        $notify.BalloonTipTitle = 'Codex Dream Skin 需要恢复'
        $notify.BalloonTipText = "$reason 点击确认可一键恢复。"
        $notify.ShowBalloonTip(8000)
        $restart = Show-UpdateWatcherQuestion -Message (
          "$reason`r`n`r`n恢复皮肤需要重启 Codex，未发送的输入可能丢失。现在重启并恢复皮肤吗？"
        )
        $watchState | Add-Member -NotePropertyName lastPromptKey -NotePropertyValue $promptKey -Force
        $watchState | Add-Member -NotePropertyName snoozeUntil `
          -NotePropertyValue ([DateTime]::UtcNow.AddMinutes(5).ToString('o')) -Force
        Write-UpdateWatcherState -State $watchState
        if ($restart) {
          $attempt = Start-HiddenDreamSkinScript -Script $startScript -Arguments @('-RestartExisting') -Wait
          if ($attempt.ExitCode -ne 0) {
            $watchState | Add-Member -NotePropertyName snoozeUntil `
              -NotePropertyValue ([DateTime]::UtcNow.AddMinutes(30).ToString('o')) -Force
            Write-UpdateWatcherState -State $watchState
          }
        }
      }

      if ($healthy -and ([DateTime]::UtcNow - $lastHealthCheck).TotalMinutes -ge 10) {
        $lastHealthCheck = [DateTime]::UtcNow
        $probe = Start-HiddenDreamSkinScript -Script $verifyScript -Arguments @('-Port', "$port") -Wait
        if ($probe.ExitCode -eq 0) {
          $healthFailures = 0
          $watchState | Add-Member -NotePropertyName lastHealthyVersion `
            -NotePropertyValue "$($codex.Version)" -Force
        } else {
          $healthFailures++
        }

        $compatibilityKey = "$($codex.Version)|$($identity.BrowserId)"
        if ($healthFailures -ge 2 -and
          "$($watchState.lastCompatibilityWarningKey)" -cne $compatibilityKey) {
          $restore = Show-UpdateWatcherQuestion -Message (
            "新版 Codex 连续两次未通过皮肤兼容性检查。`r`n`r`n" +
            '为避免按钮或布局异常，是否关闭皮肤并恢复官方外观？主题收藏不会删除。'
          )
          $watchState | Add-Member -NotePropertyName lastCompatibilityWarningKey `
            -NotePropertyValue $compatibilityKey -Force
          Write-UpdateWatcherState -State $watchState
          if ($restore) {
            Start-HiddenDreamSkinScript -Script $restoreScript `
              -Arguments @('-RestoreBaseTheme', '-ForceRestart') | Out-Null
          }
        }
      }

      $lastWriteIsOld = $true
      if ($watchState.checkedAt) {
        try {
          $lastWriteIsOld =
            ([DateTime]::UtcNow - [DateTime]::Parse("$($watchState.checkedAt)").ToUniversalTime()).TotalMinutes -ge 10
        } catch {}
      }
      $watchStateChanged = "$($watchState.lastSeenVersion)" -cne "$($codex.Version)" -or
        "$($watchState.lastSeenPackage)" -cne "$($codex.PackageFullName)"
      if ($watchStateChanged -or $lastWriteIsOld) {
        $watchState | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 1 -Force
        $watchState | Add-Member -NotePropertyName lastSeenVersion `
          -NotePropertyValue "$($codex.Version)" -Force
        $watchState | Add-Member -NotePropertyName lastSeenPackage `
          -NotePropertyValue "$($codex.PackageFullName)" -Force
        $watchState | Add-Member -NotePropertyName checkedAt `
          -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        Write-UpdateWatcherState -State $watchState
      }
      Remove-Item -LiteralPath $watchErrorPath -Force -ErrorAction SilentlyContinue
    } catch {
      Write-UpdateWatcherError -Message $_.Exception.Message
    }

    if ($RunOnce) { break }
    for ($second = 0; $second -lt $IntervalSeconds; $second++) {
      [System.Windows.Forms.Application]::DoEvents()
      if ($script:watcherExitRequested -or (Test-Path -LiteralPath $stopPath -PathType Leaf)) { break }
      Start-Sleep -Seconds 1
    }
  } while (-not $script:watcherExitRequested -and -not (Test-Path -LiteralPath $stopPath -PathType Leaf))
} finally {
  if ($notify) {
    $notify.Visible = $false
    $notify.ContextMenuStrip = $null
    $notify.Dispose()
  }
  if ($trayMenu) { $trayMenu.Dispose() }
  if ($acquired) {
    try { $mutex.ReleaseMutex() } catch {}
  }
  $mutex.Dispose()
}
