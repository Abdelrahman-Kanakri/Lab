# ============================================================
# Enroll-LabDevice.ps1
# Run via Enroll-LabDevice.bat (self-elevates).
# Creates labadmin/2026, enables WinRM, opens firewall.
# Existing user accounts and lockdown policies are untouched.
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Error "Please run this script as Administrator."; exit 1
}

function Write-Step($n, $t, $m) { Write-Host "`n[$n/$t] $m" -ForegroundColor Yellow }
function Write-OK($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Item($m) { Write-Host "       $m" -ForegroundColor DarkGray }
function Write-Fail($m) { Write-Host "  [!!] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "    Lab Device - ENROLL                      " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$TotalSteps = 5

# ============================================================
# STEP 1: Create or update labadmin user
# ============================================================
Write-Step 1 $TotalSteps "Creating/updating labadmin user..."

$user = "labadmin"
$pass = ConvertTo-SecureString "2026" -AsPlainText -Force

try {
    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $user -Password $pass -PasswordNeverExpires $true
        Enable-LocalUser -Name $user
        Write-OK "Updated existing user: $user"
    } else {
        New-LocalUser -Name $user -Password $pass `
            -PasswordNeverExpires -AccountNeverExpires `
            -FullName "Lab Admin" -Description "Created by Enroll-LabDevice.ps1" | Out-Null
        Write-OK "Created user: $user"
    }
} catch {
    Write-Fail "User create/update failed: $_"
    exit 1
}

# ============================================================
# STEP 2: Add to Administrators group
# ============================================================
Write-Step 2 $TotalSteps "Adding labadmin to Administrators group..."

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
# STEP 3: Enable WinRM
# ============================================================
Write-Step 3 $TotalSteps "Enabling WinRM..."

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
# STEP 4: Firewall rule for WinRM
# ============================================================
Write-Step 4 $TotalSteps "Opening firewall port 5985..."

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
# STEP 5: Final state report
# ============================================================
Write-Step 5 $TotalSteps "Final state..."

Write-Host ""
Write-Host "  --- WinRM service ---" -ForegroundColor Cyan
Get-Service WinRM | Format-Table Name, Status, StartType -AutoSize

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
