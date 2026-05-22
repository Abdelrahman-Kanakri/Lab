# ============================================================
# Enroll-LabDevice.ps1
# Run via Enroll-LabDevice.bat (self-elevates).
#
# Designed for the two-account model:
#   - Lab-Admin (Administrators group, password "2026@admin") — YOU.
#     CREATED MANUALLY before this script runs (you must be logged in as
#     some admin to run an elevated script in the first place).
#     Ansible on the controller connects to the device as this user.
#   - INU       (Guests group,         password "2026")        — students.
#     Created BY THIS SCRIPT if missing (idempotent — won't touch an
#     existing INU's password, just ensures Guests-group membership).
#
# Step list:
#   1. Verify Lab-Admin exists + is in Administrators           (HARD FAIL if not)
#   2. Create INU if missing, ensure it's in Guests (not Users)
#   3. Delete every other non-built-in local account            (keeps you + INU)
#   4. Enable WinRM (Automatic startup, listening on TCP 5985)
#   5. Open firewall TCP 5985 inbound
#   6. Disable sleep / display-off / disk / hibernate / Fast Startup
#   7. Enable Wake-on-LAN on every UP physical NIC (best effort)
#
# Idempotent. Safe to re-run.
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

function Write-Step($n, $t, $m) { Write-Host "`n[$n/$t] $m" -ForegroundColor Yellow }
function Write-OK($m)            { Write-Host "  [OK] $m"      -ForegroundColor Green }
function Write-Item($m)          { Write-Host "       $m"      -ForegroundColor DarkGray }
function Write-Warn($m)          { Write-Host "  [WARN] $m"    -ForegroundColor DarkYellow }
function Write-Fail($m)          { Write-Host "  [!!] $m"      -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Lab Device - ENROLL                      " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$AdminUser = "Lab-Admin"
$GuestUser = "INU"
$TotalSteps = 7

# ============================================================
# STEP 1: Verify Lab-Admin exists and is in Administrators
# ============================================================
Write-Step 1 $TotalSteps "Verifying $AdminUser exists in Administrators..."

$la = Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue
if (-not $la) {
    Write-Fail "$AdminUser does not exist. Create it manually first:"
    Write-Item  "  net user $AdminUser 2026@admin /add"
    Write-Item  "  net localgroup Administrators $AdminUser /add"
    exit 1
}
$inAdmins = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object Name -match "\\$AdminUser$")
if (-not $inAdmins) {
    Write-Fail "$AdminUser exists but is NOT in Administrators. Add it first:"
    Write-Item  "  net localgroup Administrators $AdminUser /add"
    exit 1
}
Write-OK "$AdminUser present and in Administrators."

# ============================================================
# STEP 2: INU — create if missing, ensure Guests-only group membership
# Idempotent. If INU already exists, the password is left alone (in case
# you intentionally changed it). Only the group membership is enforced.
# ============================================================
Write-Step 2 $TotalSteps "Setting up $GuestUser as a Guest..."

$inu = Get-LocalUser -Name $GuestUser -ErrorAction SilentlyContinue
if (-not $inu) {
    try {
        $pass = ConvertTo-SecureString "2026" -AsPlainText -Force
        New-LocalUser -Name $GuestUser -Password $pass `
            -PasswordNeverExpires -AccountNeverExpires `
            -FullName "INU Guest" -Description "Lab guest account (created by enrollment script)" | Out-Null
        Write-OK "Created $GuestUser (password: 2026)"
    } catch {
        Write-Fail "Failed to create $GuestUser : $_"
        exit 1
    }
} else {
    Write-OK "$GuestUser already exists (password left unchanged)"
}

# Ensure in Guests
$inGuests = (Get-LocalGroupMember -Group "Guests" -ErrorAction SilentlyContinue | Where-Object Name -match "\\$GuestUser$")
if (-not $inGuests) {
    try {
        Add-LocalGroupMember -Group "Guests" -Member $GuestUser -ErrorAction Stop
        Write-OK "Added $GuestUser to Guests"
    } catch { Write-Fail "Add to Guests failed: $_" }
} else {
    Write-OK "$GuestUser already in Guests"
}

# Remove from Users (default group on creation) so true guest restrictions apply
$inUsers = (Get-LocalGroupMember -Group "Users" -ErrorAction SilentlyContinue | Where-Object Name -match "\\$GuestUser$")
if ($inUsers) {
    try {
        Remove-LocalGroupMember -Group "Users" -Member $GuestUser -ErrorAction Stop
        Write-OK "Removed $GuestUser from Users (Guests-only now)"
    } catch { Write-Fail "Remove from Users failed: $_" }
}

# Make sure INU is in NO Administrators group, ever
$inAdmins = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object Name -match "\\$GuestUser$")
if ($inAdmins) {
    try {
        Remove-LocalGroupMember -Group "Administrators" -Member $GuestUser -ErrorAction Stop
        Write-OK "Removed $GuestUser from Administrators (was wrongly elevated)"
    } catch { Write-Fail "Remove from Administrators failed: $_" }
}

# ============================================================
# STEP 3: Delete every other local user
# Keep: built-ins, Lab-Admin, INU, currently-running user.
# ============================================================
Write-Step 3 $TotalSteps "Removing all other local users..."

$builtIn = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')
$running = $env:USERNAME
$keep    = @($AdminUser, $GuestUser) + $builtIn + @($running) | Sort-Object -Unique

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

if ($running -ne $AdminUser -and $running -ne $GuestUser -and $builtIn -notcontains $running) {
    Write-Item "Skipped '$running' (you're signed in as that account). Sign out and re-run as $AdminUser to remove it."
}

# ============================================================
# STEP 4: Enable WinRM (so the controller's ansible can reach us)
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
# STEP 6: Harden — no sleep, no hibernate, no Fast Startup
# Why: a sleeping device can't be reached and a hibernated/Fast-Startup-
# shutdown device can't WoL because the NIC stays half-asleep.
# ============================================================
Write-Step 6 $TotalSteps "Disabling sleep / hibernate / Fast Startup..."

try {
    powercfg /change standby-timeout-ac 0    | Out-Null
    powercfg /change monitor-timeout-ac 0    | Out-Null
    powercfg /change disk-timeout-ac 0       | Out-Null
    powercfg /change hibernate-timeout-ac 0  | Out-Null
    powercfg /change standby-timeout-dc 0    | Out-Null
    powercfg /change hibernate-timeout-dc 0  | Out-Null
    Write-OK "Power timeouts set to Never."
} catch { Write-Fail "powercfg timeouts failed: $_" }

try {
    powercfg -h off 2>&1 | Out-Null
    Write-OK "Hibernation + Fast Startup disabled."
} catch { Write-Fail "powercfg -h off failed: $_" }

# ============================================================
# STEP 7: Wake-on-LAN — best effort across NIC + driver
# ============================================================
Write-Step 7 $TotalSteps "Enabling Wake-on-LAN on physical NICs..."

$nics = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
if (-not $nics) {
    Write-Item "No UP physical NICs found."
} else {
    foreach ($n in $nics) {
        $okBits = @()
        try {
            Set-NetAdapterPowerManagement -Name $n.Name -WakeOnMagicPacket Enabled -ErrorAction Stop
            $okBits += "magic-packet"
        } catch { }
        try {
            $pm = Get-NetAdapterPowerManagement -Name $n.Name
            $pm.AllowComputerToTurnOffDevice = 'Disabled'
            $pm | Set-NetAdapterPowerManagement -ErrorAction Stop
            $okBits += "no-power-off"
        } catch { }
        foreach ($pname in @('Wake on Magic Packet','Wake on pattern match','Wake from S5')) {
            try {
                Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName $pname -DisplayValue 'Enabled' -ErrorAction Stop
                $okBits += "drv:$pname"
            } catch { }
        }
        if ($okBits) {
            Write-OK ("$($n.Name) ($($n.MacAddress)): " + ($okBits -join ', '))
        } else {
            Write-Item "$($n.Name) ($($n.MacAddress)): no software path accepted (likely needs BIOS WoL enable)"
        }
    }
}

# ============================================================
# Final state report
# ============================================================
Write-Host ""
Write-Host "  --- WinRM service ---" -ForegroundColor Cyan
Get-Service WinRM | Format-Table Name, Status, StartType -AutoSize

Write-Host "  --- Local users (only Lab-Admin + INU + built-ins should remain) ---" -ForegroundColor Cyan
Get-LocalUser | Format-Table Name, Enabled -AutoSize

Write-Host "  --- Administrators (should contain only Lab-Admin + Administrator built-in) ---" -ForegroundColor Cyan
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
