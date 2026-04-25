# ============================================================
# Setup-SleepSchedule.ps1
# - Sets timezone to Jordan Standard Time (Amman, UTC+3)
# - Schedules wake from sleep at 08:00 Sat-Wed
# - Forces SLEEP at 16:00 every day (Sat-Fri)
# - Shutdown/restart remain available at all times
# Run via Run-ScheduleSetup.bat (as Administrator).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

# ---- CONFIG ----
$StartHour      = 8    # 08:00
$StartMinute    = 0
$SleepHour      = 16   # 16:00
$SleepMinute    = 0

# Active weekdays = wake + auto sleep (Saturday..Wednesday)
$ActiveDays  = @("Saturday","Sunday","Monday","Tuesday","Wednesday")
# Passive weekdays = auto sleep only (Thursday, Friday)
$PassiveDays = @("Thursday","Friday")

$TaskFolder = "\LabSchedule"
$TaskPrefix = "Lab-"

function Write-Step($n, $t, $m) { Write-Host "`n[$n/$t] $m" -ForegroundColor Yellow }
function Write-OK($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Item($m) { Write-Host "       $m" -ForegroundColor DarkGray }
function Write-Fail($m) { Write-Host "  [!!] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Lab Sleep Schedule - SETUP               " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 5

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

# CRITICAL: Restart Task Scheduler so it picks up the new timezone.
# Without this, tasks get registered with the OLD timezone offset.
Write-Item "Restarting Task Scheduler to apply timezone change..."
Restart-Service -Name "Schedule" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-OK "Task Scheduler restarted."

# Verify the system clock is correct before creating any tasks
$now = Get-Date
$tz  = (Get-TimeZone).Id
Write-Host ""
Write-Host "  ================================================" -ForegroundColor White
Write-Host "  VERIFY BEFORE CONTINUING:" -ForegroundColor White
Write-Host "    Current time : $($now.ToString('dddd, dd MMM yyyy  HH:mm:ss'))" -ForegroundColor White
Write-Host "    Timezone     : $tz" -ForegroundColor White
Write-Host "  ================================================" -ForegroundColor White
Write-Host ""
if ($tz -ne "Jordan Standard Time") {
    Write-Fail "Timezone is NOT Jordan Standard Time! Aborting."
    Write-Fail "Set it manually: Set-TimeZone -Id 'Jordan Standard Time'"
    exit 1
}
$checkTime = Read-Host "  Is the time above correct? (Y/N)"
if ($checkTime -ne "Y" -and $checkTime -ne "y") {
    Write-Fail "Time is incorrect. Fix the system clock first, then re-run."
    Write-Fail "Try: w32tm /resync /force   or set time manually in Settings."
    exit 1
}

# ============================================================
# STEP 2: Enable wake timers + configure power plan
# ============================================================
Write-Step 2 $TotalSteps "Configuring power plan for wake timers and sleep..."

# Allow wake timers on AC and DC
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null

# Disable hibernate (use sleep only — faster wake, wake timers work reliably)
powercfg /h off 2>$null

# Prevent automatic sleep during working hours (set idle sleep to 0 = never)
# The scheduled task will force sleep at 16:00 instead
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0 | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null
Write-OK "Wake timers enabled. Hibernate off. Idle sleep disabled."

Write-Item "NOTE: For auto-wake from sleep, wake timers handle this."
Write-Item "      Unlike shutdown, no BIOS setting is needed for sleep wake."

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
    -Description "Wake device from sleep at 08:00 on active weekdays (Sat-Wed)" -Force | Out-Null
Write-OK "Wake task created."

# ============================================================
# STEP 5: Create SLEEP task (16:00 daily)
# ============================================================
Write-Step 5 $TotalSteps "Creating 16:00 auto-sleep task (daily)..."

# Notify user, wait 60 seconds, then force sleep
$sleepCmd = @"
# Notify user
msg * /TIME:55 "Lab closing at 16:00 - device will go to sleep in 60 seconds. Save your work now."

Start-Sleep -Seconds 60

# Force sleep using SetSuspendState (Sleep = not hibernate)
# Parameters: Hibernate=$false, ForceCritical=$true, DisableWakeEvent=$false
Add-Type -Assembly System.Windows.Forms
[System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, `$true, `$false)
"@
$sleepCmdEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($sleepCmd))

$sleepAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $sleepCmdEncoded"
$sleepTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek ($ActiveDays + $PassiveDays) `
    -At ([datetime]("{0:D2}:{1:D2}" -f $SleepHour, $SleepMinute))
$sleepSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$sleepPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "$($TaskPrefix)AutoSleep-1600" -TaskPath $TaskFolder `
    -Action $sleepAction -Trigger $sleepTrigger -Settings $sleepSettings `
    -Principal $sleepPrincipal `
    -Description "Force sleep at 16:00 every day" -Force | Out-Null
Write-OK "Auto-sleep task created."

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Sleep Schedule ACTIVE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Timezone       : Jordan Standard Time (UTC+3)" -ForegroundColor Green
Write-Host ("  Wake (Sat-Wed) : {0:D2}:{1:D2}" -f $StartHour, $StartMinute) -ForegroundColor Green
Write-Host ("  Auto sleep     : {0:D2}:{1:D2} every day" -f $SleepHour, $SleepMinute) -ForegroundColor Green
Write-Host "  Shutdown/Restart: Available at all times" -ForegroundColor Green
Write-Host ""
Write-Host "  Advantages of sleep over shutdown:" -ForegroundColor Yellow
Write-Host "    - Wake timers work reliably (no BIOS needed)" -ForegroundColor Yellow
Write-Host "    - Device wakes in seconds, not minutes" -ForegroundColor Yellow
Write-Host "    - Uses almost zero power while sleeping" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Review tasks: Task Scheduler -> LabSchedule" -ForegroundColor Yellow
Write-Host "  Remove tasks: Run-ScheduleRemove.bat" -ForegroundColor Yellow
Write-Host ""
