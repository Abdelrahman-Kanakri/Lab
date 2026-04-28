# ============================================================
# Enroll-LabDevice.ps1
# Run via Enroll-LabDevice.bat (self-elevates).
#
# What it does (in order):
#   1. Creates / updates a single local admin: INU / 2026
#   2. Deletes EVERY other non-built-in local user account
#      (Administrator, Guest, DefaultAccount, WDAGUtilityAccount stay)
#   3. Enables WinRM (Automatic startup)
#   4. Opens firewall TCP 5985
#
# After this script, the only usable local account on the device is INU.
# Profile folders under C:\Users\<name>\ are NOT removed; clean those by
# hand if you want the disk space back.
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
Write-Host "    Lab Device - ENROLL                      " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 6

# ============================================================
# STEP 1: Create or update INU
# ============================================================
Write-Step 1 $TotalSteps "Creating/updating INU user..."

$user = "INU"
$pass = ConvertTo-SecureString "2026" -AsPlainText -Force

try {
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $user -Password $pass -PasswordNeverExpires $true
        Enable-LocalUser -Name $user
        Write-OK "Updated existing user: $user"
    } else {
        New-LocalUser -Name $user -Password $pass `
            -PasswordNeverExpires -AccountNeverExpires `
            -FullName "INU Lab Admin" -Description "Created by Enroll-LabDevice.ps1" | Out-Null
        Write-OK "Created user: $user"
    }
} catch {
    Write-Fail "User create/update failed: $_"
    exit 1
}

# ============================================================
# STEP 2: Add INU to Administrators
# ============================================================
Write-Step 2 $TotalSteps "Adding $user to Administrators group..."

try {
    Add-LocalGroupMember -Group "Administrators" -Member $user -ErrorAction Stop
    Write-OK "Added to Administrators."
} catch {
    if ($_.Exception.Message -match "already") {
        Write-OK "Already in Administrators."
    } else {
        Write-Fail "Add to Administrators failed: $_"
    }
}

# ============================================================
# STEP 3: Delete every other local user
# Built-in accounts and the currently-running user are skipped.
# ============================================================
Write-Step 3 $TotalSteps "Removing all other local users..."

$builtIn = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')
$running = $env:USERNAME
$keep    = @($user) + $builtIn + @($running) | Sort-Object -Unique

$victims = Get-LocalUser | Where-Object { $keep -notcontains $_.Name }

if (-not $victims) {
    Write-OK "No other local users to remove."
} else {
    foreach ($v in $victims) {
        try {
            Remove-LocalUser -Name $v.Name -ErrorAction Stop
            Write-OK "Deleted: $($v.Name)"
        } catch {
            Write-Fail "Could not delete $($v.Name): $_"
        }
    }
}

if ($running -ne $user -and $builtIn -notcontains $running) {
    Write-Item "Skipped '$running' because the script is currently running as that user."
    Write-Item "Log out, sign in as $user, and re-run to remove '$running' as well."
}

# ============================================================
# STEP 4: Enable WinRM
# ============================================================
Write-Step 4 $TotalSteps "Enabling WinRM..."

try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    Write-OK "WinRM enabled and set to Automatic."
} catch {
    Write-Fail "WinRM enable failed: $_"
}

# ============================================================
# STEP 5: Firewall rule for WinRM
# ============================================================
Write-Step 5 $TotalSteps "Opening firewall port 5985..."

try {
    if (-not (Get-NetFirewallRule -Name "WinRM-HTTP-Lab" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "WinRM-HTTP-Lab" -DisplayName "WinRM HTTP (Lab)" `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 `
            -Profile Any | Out-Null
        Write-OK "Firewall rule added."
    } else {
        Write-OK "Firewall rule already present."
    }
} catch {
    Write-Fail "Firewall rule failed: $_"
}

# ============================================================
# STEP 6: Final state report
# ============================================================
Write-Step 6 $TotalSteps "Final state..."

Write-Host ""
Write-Host "  --- WinRM service ---" -ForegroundColor Cyan
Get-Service WinRM | Format-Table Name, Status, StartType -AutoSize

Write-Host "  --- Local users ---" -ForegroundColor Cyan
Get-LocalUser | Format-Table Name, Enabled -AutoSize

Write-Host "  --- Administrators ---" -ForegroundColor Cyan
Get-LocalGroupMember -Group "Administrators" | Format-Table Name -AutoSize

Write-Host "  --- This device ---" -ForegroundColor Cyan
Write-Host "  Hostname : $(hostname)"
$ips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet|VirtualBox|Hyper-V" }).IPAddress
Write-Host "  IPv4     : $($ips -join ', ')"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Device enrolled. Move USB to next." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
