# ============================================================
# Unlock-StudentDevice.ps1
# Removes all student restrictions set by Lock-StudentDevice.ps1
# Run via Run-Unlock.bat (as Administrator).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

function Write-Step($num, $total, $msg) { Write-Host "`n[$num/$total] $msg" -ForegroundColor Yellow }
function Write-OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Item($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

function Remove-Val([string]$path, [string]$name) {
    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    }
}
function Remove-KeyTree([string]$path) {
    if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Student Device - UNLOCK                  " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 7

# ============================================================
# STEP 1: Unblock Microsoft Store
# ============================================================
Write-Step 1 $TotalSteps "Unblocking Microsoft Store..."
$storePol = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
Remove-Val $storePol "RemoveWindowsStore"
Remove-Val $storePol "DisableStoreApps"
Remove-Val $storePol "AutoDownload"
Write-OK "Store re-enabled."

# ============================================================
# STEP 2: Unblock MSI + Add/Remove
# ============================================================
Write-Step 2 $TotalSteps "Unblocking MSI installers..."
$installer = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer"
Remove-Val $installer "DisableMSI"
Remove-Val $installer "DisablePatch"
Remove-Val $installer "DisableUserInstalls"
Set-ItemProperty -Path $installer -Name "EnableUserControl" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Remove-Val "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Uninstall" "NoAddRemovePrograms"
Remove-Val "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"  "NoAddRemovePrograms"
Write-OK "MSI and Add/Remove Programs re-enabled."

# ============================================================
# STEP 3: Remove Software Restriction Policy rules
# ============================================================
Write-Step 3 $TotalSteps "Removing exe-installer blocks..."
Remove-KeyTree "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer"
Write-OK "Software Restriction Policies cleared."

# ============================================================
# STEP 4: Unlock personalization + restore right-click wallpaper menu
# ============================================================
Write-Step 4 $TotalSteps "Unlocking personalization..."
Remove-Val "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" "NoChangingWallpaper"
Remove-Val "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" "NoHTMLWallPaper"

$sysPol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
foreach ($v in @("NoDispCPL","NoDispBackgroundPage","NoDispScrSavPage","NoDispAppearancePage",
                 "NoDispSettingsPage","NoColorChoice","NoSizeChoice","NoVisualStyleChoice","SetVisualStyle",
                 "Wallpaper","WallpaperStyle")) {
    Remove-Val $sysPol $v
}

$personalization = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
foreach ($v in @("NoChangingLockScreen","NoLockScreenSlideshow","NoChangingStartMenuBackground",
                 "PersonalColors_Background","LockScreenImage","DesktopImagePath","DesktopImageStyle")) {
    Remove-Val $personalization $v
}

# --- Restore right-click "Set as desktop background" context menu ---
if (-not (Test-Path "HKCR:\")) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
}
$contextMenuKeys = @(
    "HKCR:\SystemFileAssociations\image\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.jpg\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.jpeg\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.png\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.bmp\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.gif\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.webp\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.tif\shell\setdesktopwallpaper",
    "HKCR:\SystemFileAssociations\.tiff\shell\setdesktopwallpaper"
)
foreach ($cmKey in $contextMenuKeys) {
    if (Test-Path $cmKey) {
        Remove-ItemProperty -Path $cmKey -Name "ProgrammaticAccessOnly" -ErrorAction SilentlyContinue
    }
}
Write-OK "Personalization re-enabled."

# ============================================================
# STEP 5: Unlock password change + account pages
# ============================================================
Write-Step 5 $TotalSteps "Re-enabling password and account changes..."
Remove-Val $sysPol "DisableChangePassword"
Remove-Val "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility"
Write-OK "Password change re-enabled."

# ============================================================
# STEP 6: Re-enable registry editor
# ============================================================
Write-Step 6 $TotalSteps "Re-enabling system tools..."
Remove-Val $sysPol "DisableRegistryTools"
Remove-Val $sysPol "DisableTaskMgr"
Write-OK "Registry editor re-enabled."

# ============================================================
# STEP 7: Mark state + refresh
# ============================================================
Write-Step 7 $TotalSteps "Saving unlock state..."
$stateKey = "HKLM:\SOFTWARE\LabPolicy\StudentLock"
if (-not (Test-Path $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
Set-ItemProperty -Path $stateKey -Name "Locked"     -Value 0 -Type DWord -Force
Set-ItemProperty -Path $stateKey -Name "UnlockedAt" -Value (Get-Date).ToString("s") -Type String -Force

gpupdate /force | Out-Null
Write-OK "Group policy refreshed."

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Student Device is now UNLOCKED" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  You can now install apps, change wallpaper," -ForegroundColor Green
Write-Host "  change passwords, and use the Store." -ForegroundColor Green
Write-Host ""
Write-Host "  Remember to run Lock-StudentDevice.ps1 again" -ForegroundColor Yellow
Write-Host "  when you are done installing!" -ForegroundColor Yellow
Write-Host ""
