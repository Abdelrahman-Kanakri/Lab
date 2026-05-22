# ============================================================
# Remove-ShutdownSchedule.ps1
# Removes all lab shutdown/wake scheduled tasks and
# restores the shutdown button in the UI.
# Run via Run-ScheduleRemove.bat (as Administrator).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Lab Shutdown Schedule - REMOVE           " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Remove all tasks under \LabSchedule\
Get-ScheduledTask -TaskPath "\LabSchedule\" -ErrorAction SilentlyContinue | ForEach-Object {
    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed: $($_.TaskName)" -ForegroundColor Green
}

# Remove the (now empty) folder
try {
    $scheduleService = New-Object -ComObject Schedule.Service
    $scheduleService.Connect()
    $root = $scheduleService.GetFolder("\")
    $root.DeleteFolder("LabSchedule", 0)
    Write-Host "  [OK] Removed LabSchedule task folder." -ForegroundColor Green
} catch {
    Write-Host "  [--] LabSchedule folder already gone." -ForegroundColor Gray
}

# Restore shutdown/restart buttons
$p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if (Test-Path $p) {
    Remove-ItemProperty -Path $p -Name 'NoClose' -ErrorAction SilentlyContinue
    Write-Host "  [OK] Restored Shutdown/Restart options in Start menu." -ForegroundColor Green
}

Write-Host ""
Write-Host "  Schedule removed. Timezone remains set to Jordan Standard Time." -ForegroundColor Yellow
Write-Host "  (Set-TimeZone -Id 'UTC' to change if needed.)" -ForegroundColor Yellow
Write-Host ""
