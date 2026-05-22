# Harden-LabDevice.ps1
# Idempotent hardening run by playbook 11_harden_devices.yml.
# Steps:
#   1. Remove all scheduled tasks under \LabSchedule\
#   2. Disable sleep/display/disk/hibernate timeouts (AC + DC)
#   3. Disable hibernation (also kills Fast Startup)
#   4. Enable WoL on every UP physical NIC + stop Windows powering it down
# Prints a JSON-ish summary on the last line for the playbook to capture.

$ErrorActionPreference = 'Continue'

# --- 1. tasks ---
$removed = @()
$tasks = Get-ScheduledTask -TaskPath "\LabSchedule\" -ErrorAction SilentlyContinue
foreach ($t in $tasks) {
    try {
        Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
        $removed += $t.TaskName
    } catch { }
}
try {
    $sched = New-Object -ComObject Schedule.Service
    $sched.Connect()
    $sched.GetFolder("\").DeleteFolder("LabSchedule", 0)
} catch { }

# --- 2. powercfg timeouts ---
powercfg /change standby-timeout-ac 0    | Out-Null
powercfg /change monitor-timeout-ac 0    | Out-Null
powercfg /change disk-timeout-ac 0       | Out-Null
powercfg /change hibernate-timeout-ac 0  | Out-Null
powercfg /change standby-timeout-dc 0    | Out-Null
powercfg /change hibernate-timeout-dc 0  | Out-Null

# --- 3. hibernation off ---
powercfg -h off 2>&1 | Out-Null

# --- 4. WoL per NIC ---
$wol = @()
$nics = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
foreach ($n in $nics) {
    $row = [ordered]@{ nic = $n.Name; mac = $n.MacAddress; pm = $null; allowOff = $null }
    try {
        Set-NetAdapterPowerManagement -Name $n.Name `
            -WakeOnMagicPacket  Enabled `
            -DeviceSleepOnDisconnect Disabled `
            -SelectiveSuspend   Disabled `
            -ErrorAction Stop
        $row.pm = "ok"
    } catch { $row.pm = "fail" }
    try {
        $pm = Get-NetAdapterPowerManagement -Name $n.Name
        $pm.AllowComputerToTurnOffDevice = 'Disabled'
        $pm | Set-NetAdapterPowerManagement -ErrorAction Stop
        $row.allowOff = "disabled"
    } catch { $row.allowOff = "fail" }
    $advNames = @(
        'Wake on Magic Packet',
        'Wake on pattern match',
        'Wake from S5',
        'Energy Efficient Ethernet'
    )
    foreach ($pname in $advNames) {
        $val = if ($pname -eq 'Energy Efficient Ethernet') { 'Disabled' } else { 'Enabled' }
        try { Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName $pname -DisplayValue $val -ErrorAction Stop } catch { }
    }
    $wol += [pscustomobject]$row
}

# Persist a state file the controller can read back after the run
$summary = [ordered]@{
    when    = (Get-Date).ToString('o')
    host    = $env:COMPUTERNAME
    removed = $removed.Count
    nics    = $wol
}
$json = $summary | ConvertTo-Json -Compress -Depth 4
$json | Set-Content -Path "C:\ProgramData\HardenState.json" -Encoding UTF8 -Force
$json
