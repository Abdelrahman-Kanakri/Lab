# ============================================================
# 08_Switch-ToINU.ps1
# Run via 08_Switch-ToINU.bat (self-elevates).
#
# Purpose: migrate a lab device from "labadmin" to "INU".
#   1. Ensure INU exists (password 2026, in Administrators)
#   2. Delete labadmin (only if it is NOT the current user)
#
# Safe to re-run. Skips cleanly if labadmin is already gone or
# if INU already exists with the right state.
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

function Write-Step($n, $t, $m) { Write-Host "`n[$n/$t] $m" -ForegroundColor Yellow }
function Write-OK($m)            { Write-Host "  [OK] $m"      -ForegroundColor Green }
function Write-Item($m)          { Write-Host "       $m"      -ForegroundColor DarkGray }
function Write-Fail($m)          { Write-Host "  [!!] $m"      -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   Lab Device - SWITCH labadmin -> INU       " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 3
$running = $env:USERNAME

# ============================================================
# STEP 1: Ensure INU exists, password 2026, in Administrators
# ============================================================
Write-Step 1 $TotalSteps "Ensuring INU user..."

$user = "INU"
$pass = ConvertTo-SecureString "2026" -AsPlainText -Force

try {
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $user -Password $pass -PasswordNeverExpires $true
        Enable-LocalUser -Name $user
        Write-OK "INU exists; password reset to 2026."
    } else {
        New-LocalUser -Name $user -Password $pass `
            -PasswordNeverExpires -AccountNeverExpires `
            -FullName "INU Lab Admin" -Description "Created by Switch-ToINU.ps1" | Out-Null
        Write-OK "Created user: INU"
    }
} catch {
    Write-Fail "INU create/update failed: $_"; exit 1
}

try {
    Add-LocalGroupMember -Group "Administrators" -Member $user -ErrorAction Stop
    Write-OK "INU added to Administrators."
} catch {
    if ($_.Exception.Message -match "already") {
        Write-OK "INU already in Administrators."
    } else {
        Write-Fail "Add to Administrators failed: $_"
    }
}

# ============================================================
# STEP 2: Delete labadmin (refuse if current user)
# ============================================================
Write-Step 2 $TotalSteps "Removing labadmin..."

$target = "labadmin"

if ($running -ieq $target) {
    Write-Fail "Cannot delete '$target' — it is the currently signed-in user."
    Write-Item "Sign out of $target, sign in as INU (or any other admin),"
    Write-Item "then re-run this script."
    exit 1
}

$la = Get-LocalUser -Name $target -ErrorAction SilentlyContinue
if (-not $la) {
    Write-OK "labadmin does not exist on this device. Nothing to delete."
} else {
    try {
        Remove-LocalUser -Name $target -ErrorAction Stop
        Write-OK "Deleted local user: $target"
    } catch {
        Write-Fail "Could not delete $target : $_"; exit 1
    }

    # Best-effort profile folder cleanup (won't fail the script)
    $profile = "C:\Users\$target"
    if (Test-Path $profile) {
        try {
            Remove-Item -Path $profile -Recurse -Force -ErrorAction Stop
            Write-OK "Removed profile folder: $profile"
        } catch {
            Write-Item "Profile folder $profile still present (in use or locked); remove manually if needed."
        }
    }
}

# ============================================================
# STEP 3: Final state
# ============================================================
Write-Step 3 $TotalSteps "Final state..."

Write-Host ""
Write-Host "  --- Local users ---" -ForegroundColor Cyan
Get-LocalUser | Format-Table Name, Enabled -AutoSize

Write-Host "  --- Administrators ---" -ForegroundColor Cyan
Get-LocalGroupMember -Group "Administrators" | Format-Table Name -AutoSize

Write-Host "  Currently signed in as: $running"
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   Switch complete. Move USB to next." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
