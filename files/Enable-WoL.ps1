# Enable-WoL.ps1
# For every UP physical NIC, try to enable Wake-on-LAN via three independent
# mechanisms and report what worked. Writes a JSON summary to
# C:\ProgramData\WolState.json so the controller can read it back.
#
# Designed to be safe even on NICs that don't expose any of these knobs —
# every call is wrapped in try/catch.

$ErrorActionPreference = 'Continue'

$results = @()
$nics = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'

foreach ($n in $nics) {
    $row = [ordered]@{
        nic                  = $n.Name
        mac                  = $n.MacAddress
        magicPacket          = '-'
        allowComputerOffPM   = '-'
        advWakeMagicPacket   = '-'
        advWakeFromS5        = '-'
    }

    # 1. PowerShell cmdlet — works on NICs whose driver implements it
    try {
        Set-NetAdapterPowerManagement -Name $n.Name -WakeOnMagicPacket Enabled -ErrorAction Stop
        $row.magicPacket = 'enabled'
    } catch {
        $row.magicPacket = 'unsupported'
    }

    # 2. Uncheck "Allow the computer to turn off this device to save power"
    try {
        $pm = Get-NetAdapterPowerManagement -Name $n.Name -ErrorAction Stop
        $pm.AllowComputerToTurnOffDevice = 'Disabled'
        $pm | Set-NetAdapterPowerManagement -ErrorAction Stop
        $row.allowComputerOffPM = 'disabled'
    } catch {
        $row.allowComputerOffPM = 'unsupported'
    }

    # 3. Driver-level advanced properties (vendor-specific names)
    try {
        Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName 'Wake on Magic Packet' -DisplayValue 'Enabled' -ErrorAction Stop
        $row.advWakeMagicPacket = 'enabled'
    } catch { $row.advWakeMagicPacket = 'no-property' }

    try {
        Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName 'Wake from S5' -DisplayValue 'Enabled' -ErrorAction Stop
        $row.advWakeFromS5 = 'enabled'
    } catch { $row.advWakeFromS5 = 'no-property' }

    $results += [pscustomobject]$row
}

$summary = [ordered]@{
    when = (Get-Date).ToString('o')
    host = $env:COMPUTERNAME
    nics = $results
}
$json = $summary | ConvertTo-Json -Compress -Depth 4
$json | Set-Content -Path "C:\ProgramData\WolState.json" -Encoding UTF8 -Force
$json
