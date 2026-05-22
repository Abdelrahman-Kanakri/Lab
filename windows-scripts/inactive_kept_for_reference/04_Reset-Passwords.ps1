# ============================================================
# Reset-Passwords.ps1
# Resets ALL enabled local user passwords to "2026".
# Run via Run-ResetPasswords.bat (as Administrator).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

# ---- CONFIG ----
$UnifiedPassword = "2026"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Password Reset - All Local Users         " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This will reset ALL enabled local user"     -ForegroundColor Yellow
Write-Host "  passwords to: $UnifiedPassword"             -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "  Type YES to proceed, or anything else to cancel"
if ($confirm -ne "YES") {
    Write-Host ""
    Write-Host "  Cancelled. No passwords were changed." -ForegroundColor Green
    exit 0
}

Write-Host ""

$securePassword = ConvertTo-SecureString $UnifiedPassword -AsPlainText -Force
$users = Get-LocalUser | Where-Object { $_.Enabled -eq $true }

if ($users.Count -eq 0) {
    Write-Host "  [!!] No enabled local users found." -ForegroundColor Red
    exit 1
}

$success = 0
$failed  = 0

foreach ($user in $users) {
    try {
        Set-LocalUser -Name $user.Name -Password $securePassword -PasswordNeverExpires $true -ErrorAction Stop
        Write-Host "  [OK] $($user.Name)" -ForegroundColor Green
        $success++
    } catch {
        Write-Host "  [!!] $($user.Name): $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Password Reset Complete" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Password set to : $UnifiedPassword" -ForegroundColor Green
Write-Host "  Users reset     : $success" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed          : $failed" -ForegroundColor Red
}
Write-Host "  Password expiry : Never" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
