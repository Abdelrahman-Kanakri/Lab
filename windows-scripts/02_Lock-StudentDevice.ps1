# ============================================================
# Lock-StudentDevice.ps1
# Applies strict lab/student restrictions machine-wide.
# Works for ALL users regardless of account name.
# Run via Run-Lock.bat (as Administrator).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

function Write-Step($num, $total, $msg) { Write-Host "`n[$num/$total] $msg" -ForegroundColor Yellow }
function Write-OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green    }
function Write-Item($msg) { Write-Host "       $msg" -ForegroundColor DarkGray }

function Ensure-Key([string]$path) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
}
function Set-Reg([string]$path, [string]$name, $value, [string]$type = "DWord") {
    Ensure-Key $path
    Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -Force
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Student Device - LOCK                    " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 8

# ============================================================
# STEP 1: Block Microsoft Store
# ============================================================
Write-Step 1 $TotalSteps "Blocking Microsoft Store..."

Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" "RemoveWindowsStore" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" "DisableStoreApps"   1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" "AutoDownload"       2
Write-OK "Store disabled."

# ============================================================
# STEP 2: Block MSI installers + Add/Remove Programs
# ============================================================
Write-Step 2 $TotalSteps "Blocking MSI installers..."

# DisableMSI = 2 means "Always disabled" (even for admins)
# Use 1 if you want admins to still install. We use 2 for max lockdown.
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" "DisableMSI"       2
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" "DisablePatch"     1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" "DisableUserInstalls" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" "EnableUserControl" 0

Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Uninstall" "NoAddRemovePrograms" 1
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"  "NoAddRemovePrograms" 1
Write-OK "MSI installs and Add/Remove Programs blocked."

# ============================================================
# STEP 3: Block .EXE installers via Software Restriction Policies
# ============================================================
Write-Step 3 $TotalSteps "Blocking .exe execution from user-writable locations..."

$srpRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
Ensure-Key $srpRoot
Ensure-Key "$srpRoot\0\Paths"          # Disallowed rules
Ensure-Key "$srpRoot\262144\Paths"     # Unrestricted rules

# Default = Unrestricted (262144). We keep this so the OS runs normally,
# and add PATH RULES to disallow exe execution from risky folders.
Set-Reg $srpRoot "DefaultLevel"     262144
Set-Reg $srpRoot "TransparentEnabled" 1
Set-Reg $srpRoot "PolicyScope"      0
Set-Reg $srpRoot "ExecutableTypes"  "ADE,ADP,BAS,BAT,CHM,CMD,COM,CPL,CRT,EXE,HLP,HTA,INF,INS,ISP,LNK,MDB,MDE,MSC,MSI,MSP,MST,OCX,PCD,PIF,REG,SCR,SHS,URL,VB,WSC" "MultiString"

# Blocked paths (Disallowed = level 0)
$blockedPaths = @(
    "%USERPROFILE%\Downloads\*.exe",
    "%USERPROFILE%\Downloads\*.msi",
    "%USERPROFILE%\Desktop\*.exe",
    "%USERPROFILE%\Desktop\*.msi",
    "%USERPROFILE%\AppData\Local\Temp\*.exe",
    "%USERPROFILE%\AppData\Local\Temp\*.msi",
    "%USERPROFILE%\AppData\Roaming\*.exe",
    "%TEMP%\*.exe",
    "%TEMP%\*.msi",
    "C:\Users\*\Downloads\*.exe",
    "C:\Users\*\Downloads\*.msi",
    "C:\Users\Public\Downloads\*.exe"
)

$guid = 0
foreach ($p in $blockedPaths) {
    $ruleKey = "$srpRoot\0\Paths\{00000000-0000-0000-0000-$("{0:D12}" -f $guid)}"
    Ensure-Key $ruleKey
    Set-Reg $ruleKey "ItemData"    $p "ExpandString"
    Set-Reg $ruleKey "SaferFlags"  0
    Set-Reg $ruleKey "Description" "Lab lockdown: block installers from user-writable path"
    $guid++
}
Write-OK "Installer execution blocked in user-writable paths."

# ============================================================
# STEP 4: Reset wallpaper and lock screen to Windows default
# ============================================================
Write-Step 4 $TotalSteps "Resetting wallpaper and lock screen to defaults..."

$defaultWallpaper = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
$defaultLockScreen = "C:\Windows\Web\Screen\img100.jpg"

# --- Reset wallpaper for EVERY user profile on the device ---
$profileList = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @("Public","Default","Default User","All Users") }
foreach ($prof in $profileList) {
    # Find the user's registry hive and load it if not already mounted
    $ntuser = Join-Path $prof.FullName "NTUSER.DAT"
    $sid = $null
    try {
        $sidObj = (New-Object System.Security.Principal.NTAccount($prof.Name)).Translate(
            [System.Security.Principal.SecurityIdentifier])
        $sid = $sidObj.Value
    } catch { }

    if ($sid -and (Test-Path "Registry::HKEY_USERS\$sid")) {
        # Hive already loaded (user is logged in or current)
        $hive = "Registry::HKEY_USERS\$sid"
        Set-ItemProperty "$hive\Control Panel\Desktop" -Name "Wallpaper"      -Value $defaultWallpaper -ErrorAction SilentlyContinue
        Set-ItemProperty "$hive\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10"              -ErrorAction SilentlyContinue
        Write-Item "Reset wallpaper for: $($prof.Name) (live)"
    } elseif (Test-Path $ntuser) {
        # Load the offline hive, patch it, unload
        $tempKey = "HKU_TEMP_$($prof.Name)"
        reg load "HKU\$tempKey" $ntuser 2>$null | Out-Null
        if (Test-Path "Registry::HKEY_USERS\$tempKey\Control Panel\Desktop") {
            Set-ItemProperty "Registry::HKEY_USERS\$tempKey\Control Panel\Desktop" -Name "Wallpaper"      -Value $defaultWallpaper -ErrorAction SilentlyContinue
            Set-ItemProperty "Registry::HKEY_USERS\$tempKey\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10"              -ErrorAction SilentlyContinue
            Write-Item "Reset wallpaper for: $($prof.Name) (offline hive)"
        }
        [gc]::Collect()
        reg unload "HKU\$tempKey" 2>$null | Out-Null
    }

    # Remove any cached wallpaper images stored by Windows
    $transcodedPath = Join-Path $prof.FullName "AppData\Roaming\Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path $transcodedPath) { Remove-Item $transcodedPath -Force -ErrorAction SilentlyContinue }
    $cachedFiles = Join-Path $prof.FullName "AppData\Roaming\Microsoft\Windows\Themes\CachedFiles"
    if (Test-Path $cachedFiles) { Remove-Item "$cachedFiles\*" -Force -Recurse -ErrorAction SilentlyContinue }
}

# Also reset for the currently running session
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "Wallpaper"      -Value $defaultWallpaper -ErrorAction SilentlyContinue
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10"              -ErrorAction SilentlyContinue
RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters 1 True 2>$null

# --- Reset lock screen via GPO to default ---
$personalization = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
Ensure-Key $personalization
if (Test-Path $defaultLockScreen) {
    Set-Reg $personalization "LockScreenImage" $defaultLockScreen "String"
    Write-Item "Lock screen set to: $defaultLockScreen"
} else {
    # Fallback: try alternate default path
    $altLock = "C:\Windows\Web\Screen\img105.jpg"
    if (Test-Path $altLock) {
        Set-Reg $personalization "LockScreenImage" $altLock "String"
        Write-Item "Lock screen set to: $altLock"
    } else {
        Write-Item "No default lock screen image found - using current Windows default."
        Remove-ItemProperty -Path $personalization -Name "LockScreenImage" -ErrorAction SilentlyContinue
    }
}
Write-OK "Wallpaper and lock screen reset to Windows defaults."


# ============================================================
# STEP 5: Block personalization + right-click wallpaper change
# ============================================================
Write-Step 5 $TotalSteps "Blocking all personalization changes..."

# --- Block via Group Policy: force the default wallpaper ---
# This is the strongest method: even right-click > Set as background won't stick
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "DesktopImagePath" $defaultWallpaper "String"
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "DesktopImageStyle" 10

$actDesk = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
Set-Reg $actDesk "NoChangingWallpaper" 1
Set-Reg $actDesk "NoHTMLWallPaper"     1

$sysPol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-Reg $sysPol "NoDispCPL"             1   # hide Display CPL
Set-Reg $sysPol "NoDispBackgroundPage"  1
Set-Reg $sysPol "NoDispScrSavPage"      1
Set-Reg $sysPol "NoDispAppearancePage"  1
Set-Reg $sysPol "NoDispSettingsPage"    1
Set-Reg $sysPol "NoColorChoice"         1
Set-Reg $sysPol "NoSizeChoice"          1
Set-Reg $sysPol "NoVisualStyleChoice"   1
Set-Reg $sysPol "SetVisualStyle"        ""   "String"
Set-Reg $sysPol "Wallpaper"            $defaultWallpaper "String"
Set-Reg $sysPol "WallpaperStyle"       "10"              "String"

Set-Reg $personalization "NoChangingLockScreen"          1
Set-Reg $personalization "NoLockScreenSlideshow"         1
Set-Reg $personalization "NoChangingStartMenuBackground" 1
Set-Reg $personalization "PersonalColors_Background"     "#0078D7" "String"

# --- Block right-click "Set as desktop background" context menu ---
# This removes the shell verb from image file types
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
# Mount HKCR if not available as PSDrive
if (-not (Test-Path "HKCR:\")) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
}
foreach ($cmKey in $contextMenuKeys) {
    if (Test-Path $cmKey) {
        # Don't delete - just add ProgrammaticAccessOnly so it's hidden from context menu
        Set-ItemProperty -Path $cmKey -Name "ProgrammaticAccessOnly" -Value "" -Type String -Force -ErrorAction SilentlyContinue
        Write-Item "Hidden: $cmKey"
    }
}

# Also block via the main image shell handler
$mainImageShell = "HKCR:\SystemFileAssociations\image\shell\setdesktopwallpaper"
if (Test-Path $mainImageShell) {
    Set-ItemProperty -Path $mainImageShell -Name "ProgrammaticAccessOnly" -Value "" -Type String -Force -ErrorAction SilentlyContinue
}
Write-OK "Personalization locked. Right-click 'Set as background' hidden."

# ============================================================
# STEP 6: Block password change + account changes
# ============================================================
Write-Step 6 $TotalSteps "Blocking password and account changes..."

Set-Reg $sysPol "DisableChangePassword"  1
Set-Reg $sysPol "DisableLockWorkstation" 0   # allow lock but not password change
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoLogoff" 0

# Hide "Users" and "Family" settings page
Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" `
    "hide:otherusers;yourinfo;signinoptions;family-group;workplace;emailandaccounts;sync;windowsanywhere" "String"
Write-OK "Password change and account settings disabled."

# ============================================================
# STEP 7: Block Control Panel / Settings misuse + Registry + CMD for standard users
# ============================================================
Write-Step 7 $TotalSteps "Restricting system tools..."

# Keep Control Panel accessible but hide specific dangerous applets
Set-Reg $sysPol "DisableRegistryTools" 1   # block regedit for non-admins
# Note: Task Manager stays enabled so users can still close apps.
# If you also want to block it, uncomment:
# Set-Reg $sysPol "DisableTaskMgr" 1
Write-OK "Registry editor blocked for standard users."

# ============================================================
# STEP 8: Mark state + refresh policies
# ============================================================
Write-Step 8 $TotalSteps "Saving lock state..."

$stateKey = "HKLM:\SOFTWARE\LabPolicy\StudentLock"
Set-Reg $stateKey "Locked"   1
Set-Reg $stateKey "LockedAt" (Get-Date).ToString("s") "String"

gpupdate /force | Out-Null
Write-OK "Group policy refreshed."

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Student Device is now LOCKED" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  - Wallpaper:          RESET TO DEFAULT" -ForegroundColor Green
Write-Host "  - Lock screen:        RESET TO DEFAULT" -ForegroundColor Green
Write-Host "  - Store:              BLOCKED" -ForegroundColor Green
Write-Host "  - MSI installers:     BLOCKED" -ForegroundColor Green
Write-Host "  - EXE from Downloads: BLOCKED" -ForegroundColor Green
Write-Host "  - Personalization:    BLOCKED" -ForegroundColor Green
Write-Host "  - Right-click bg:     BLOCKED" -ForegroundColor Green
Write-Host "  - Password change:    BLOCKED" -ForegroundColor Green
Write-Host "  - Registry editor:    BLOCKED" -ForegroundColor Green
Write-Host ""
Write-Host "  Run Unlock-StudentDevice.ps1 to re-enable installs." -ForegroundColor Yellow
Write-Host "  A sign-out or restart is recommended for all changes to take effect." -ForegroundColor Yellow
Write-Host ""
