# ============================================================
# Setup-ShutdownSchedule.ps1
# - Sets timezone to Jordan Standard Time (Amman, UTC+3)
# - Schedules wake/startup at 08:00 Sat-Wed
# - Blocks manual shutdown 08:00-16:00 Sat-Wed
# - Forces shutdown at 16:00 every day (Sat-Fri)
# Run via Run-ScheduleSetup.bat (as Administrator).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

# ---- CONFIG ----
$StartHour      = 8    # 08:00
$StartMinute    = 0
$ShutdownHour   = 16   # 16:00
$ShutdownMinute = 0

# Active weekdays = startup + block-shutdown + auto shutdown (Saturday..Wednesday)
$ActiveDays  = @("Saturday","Sunday","Monday","Tuesday","Wednesday")
# Passive weekdays = auto shutdown only (Thursday, Friday)
$PassiveDays = @("Thursday","Friday")

$TaskFolder = "\LabSchedule"
$TaskPrefix = "Lab-"

function Write-Step($n, $t, $m) { Write-Host "`n[$n/$t] $m" -ForegroundColor Yellow }
function Write-OK($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Item($m) { Write-Host "       $m" -ForegroundColor DarkGray }
function Write-Fail($m) { Write-Host "  [!!] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Lab Shutdown Schedule - SETUP            " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 6

# ============================================================
# STEP 1: Timezone + time sync
# ============================================================
Write-Step 1 $TotalSteps "Setting timezone to Jordan Standard Time (Amman)..."
try {
    Set-TimeZone -Id "Jordan Standard Time" -ErrorAction Stop
    Write-OK "Timezone set to Jordan Standard Time (UTC+3)."
} catch {
    Write-Fail "Could not set timezone: $_"
}

Write-Item "Syncing time with Windows Time service..."
Start-Service -Name w32time -ErrorAction SilentlyContinue
w32tm /config /update /manualpeerlist:"time.windows.com,0x9" /syncfromflags:MANUAL | Out-Null
w32tm /resync /force 2>$null | Out-Null
Write-OK "Time synced."

# ============================================================
# STEP 2: Enable wake timers + set power plan for wake
# ============================================================
Write-Step 2 $TotalSteps "Configuring power plan for wake timers..."

# Allow wake timers on AC and DC
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null

# Don't hibernate (wake timers don't fire from full off)
# Allow sleep instead
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 1800  | Out-Null  # 30 min
powercfg /setactive SCHEME_CURRENT | Out-Null
Write-OK "Wake timers enabled."

Write-Item "NOTE: To auto-power-on from fully OFF state, you must enable"
Write-Item "      'RTC Alarm' / 'Wake on RTC' in the device BIOS/UEFI."
Write-Item "      Windows alone cannot power on from S5 (full shutdown)."

# ============================================================
# STEP 3: Ensure folder exists and remove old tasks
# ============================================================
Write-Step 3 $TotalSteps "Removing any existing lab schedule tasks..."

Get-ScheduledTask -TaskPath "$TaskFolder\" -ErrorAction SilentlyContinue | ForEach-Object {
    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    Write-Item "Removed old task: $($_.TaskName)"
}
Write-OK "Old tasks cleared."

# ============================================================
# STEP 4: Create WAKE task (08:00 Sat-Wed)
# ============================================================
Write-Step 4 $TotalSteps "Creating 08:00 wake task (Sat-Wed)..."

$wakeAction  = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c exit 0"
$wakeTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $ActiveDays `
    -At ([datetime]("{0:D2}:{1:D2}" -f $StartHour, $StartMinute))
$wakeSettings = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfIdle:$false
$wakePrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "$($TaskPrefix)Wake-0800" -TaskPath $TaskFolder `
    -Action $wakeAction -Trigger $wakeTrigger -Settings $wakeSettings -Principal $wakePrincipal `
    -Description "Wake device at 08:00 on active weekdays (Sat-Wed)" -Force | Out-Null
Write-OK "Wake task created."

# ============================================================
# STEP 5: Create SHUTDOWN-LOCK task (block manual shutdown 08:00-16:00 Sat-Wed)
# ============================================================
Write-Step 5 $TotalSteps "Creating block-shutdown task (08:00 Sat-Wed)..."

# At 08:00 Sat-Wed: enable NoClose policy (hides shutdown/restart in UI)
$lockCmd = @"
`$p='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if(-not(Test-Path `$p)){New-Item `$p -Force|Out-Null}
Set-ItemProperty -Path `$p -Name 'NoClose' -Value 1 -Type DWord -Force
"@
$lockCmdEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($lockCmd))

$lockAction  = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $lockCmdEncoded"
$lockTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $ActiveDays `
    -At ([datetime]("{0:D2}:{1:D2}" -f $StartHour, $StartMinute))
$lockSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
$lockPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "$($TaskPrefix)BlockShutdown-0800" -TaskPath $TaskFolder `
    -Action $lockAction -Trigger $lockTrigger -Settings $lockSettings -Principal $lockPrincipal `
    -Description "Hide Shutdown/Restart options at 08:00 (Sat-Wed)" -Force | Out-Null
Write-OK "Block-shutdown task created."

# ============================================================
# STEP 6: Create AUTO-SHUTDOWN task (16:00 daily)
# ============================================================
Write-Step 6 $TotalSteps "Creating 16:00 auto-shutdown task (daily)..."

# First un-hide shutdown (so the forced shutdown via OS works cleanly),
# then call shutdown /s /f /t 0
$shutdownCmd = @"
`$p='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if(Test-Path `$p){Remove-ItemProperty -Path `$p -Name 'NoClose' -ErrorAction SilentlyContinue}
Start-Sleep -Seconds 2
shutdown.exe /s /f /t 60 /c 'Scheduled lab shutdown at 16:00 - saving your work now. Device will power off in 60 seconds.'
"@
$shutdownCmdEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($shutdownCmd))

$shutdownAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $shutdownCmdEncoded"
$shutdownTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek ($ActiveDays + $PassiveDays) `
    -At ([datetime]("{0:D2}:{1:D2}" -f $ShutdownHour, $ShutdownMinute))
$shutdownSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$shutdownPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "$($TaskPrefix)AutoShutdown-1600" -TaskPath $TaskFolder `
    -Action $shutdownAction -Trigger $shutdownTrigger -Settings $shutdownSettings `
    -Principal $shutdownPrincipal `
    -Description "Force shutdown at 16:00 every day" -Force | Out-Null
Write-OK "Auto-shutdown task created."

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Shutdown Schedule ACTIVE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Timezone      : Jordan Standard Time (UTC+3)" -ForegroundColor Green
Write-Host ("  Wake (Sat-Wed): {0:D2}:{1:D2}" -f $StartHour, $StartMinute) -ForegroundColor Green
Write-Host ("  Block UI      : {0:D2}:{1:D2} (Sat-Wed)" -f $StartHour, $StartMinute) -ForegroundColor Green
Write-Host ("  Shutdown      : {0:D2}:{1:D2} every day" -f $ShutdownHour, $ShutdownMinute) -ForegroundColor Green
Write-Host ""
Write-Host "  Review tasks: Task Scheduler -> Task Scheduler Library -> LabSchedule" -ForegroundColor Yellow
Write-Host "  Reminder    : Enable 'RTC Wake Alarm' in BIOS for auto power-on." -ForegroundColor Yellow
Write-Host ""
