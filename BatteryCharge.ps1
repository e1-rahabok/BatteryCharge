<#
.SYNOPSIS
  Switch the Dell battery charge mode without rebooting, using Dell Command | Configure (cctk.exe).

.PARAMETER Mode
  Full   - Standard charging, charges to 100% (use before going unplugged)
  Limit  - Custom charging, stops at -Stop (default 65%) and resumes below -Start (default 50%)
  Toggle - Switch between Full and Limit
  Status - Show the current setting only

.NOTES
  Needs admin rights; the script re-launches itself elevated (UAC prompt) when needed.
  Dell limits: Start 50-95, Stop 55-100, Stop must be at least 5 above Start.
#>
param(
    [ValidateSet('Full', 'Limit', 'Toggle', 'Status')]
    [string]$Mode = 'Toggle',
    [ValidateRange(50, 95)]  [int]$Start = 50,
    [ValidateRange(55, 100)] [int]$Stop = 65,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$cctk = 'C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe'

Add-Type -AssemblyName System.Windows.Forms
function Show-Result([string]$Text, [string]$Icon = 'Information') {
    if (-not $Quiet) {
        [void][System.Windows.Forms.MessageBox]::Show($Text, 'Battery Charge', 'OK', $Icon)
    }
    Write-Output $Text
}

# Re-launch elevated if needed.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-Start', $Start, '-Stop', $Stop)
    if ($Quiet) { $argList += '-Quiet' }
    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -WindowStyle Hidden
    } catch {
        Show-Result "Admin rights are required and the UAC prompt was cancelled." 'Warning'
    }
    exit
}

if (-not (Test-Path $cctk)) {
    Show-Result "Dell Command | Configure not found at:`n$cctk" 'Error'; exit 1
}
if ($Stop - $Start -lt 5) {
    Show-Result "Stop ($Stop) must be at least 5 higher than Start ($Start)." 'Error'; exit 1
}

function Get-ChargeCfg {
    $line = & $cctk --PrimaryBattChargeCfg 2>&1 | Select-String 'PrimaryBattChargeCfg=' | Select-Object -First 1
    if ($line) { ($line.ToString() -split '=', 2)[1].Trim() } else { 'Unknown' }
}

function Get-BatteryText {
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return '' }
    $state = switch ($b.BatteryStatus) { 1 { 'on battery' } 2 { 'on AC' } 6 { 'charging' } 3 { 'fully charged' } default { "status $($b.BatteryStatus)" } }
    "Battery now: $($b.EstimatedChargeRemaining)% ($state)"
}

$current = Get-ChargeCfg
if ($Mode -eq 'Status') {
    Show-Result "Charge mode: $current`n$(Get-BatteryText)"; exit 0
}
if ($Mode -eq 'Toggle') {
    $Mode = if ($current -like 'Custom*') { 'Full' } else { 'Limit' }
}

$value = if ($Mode -eq 'Full') { 'Standard' } else { "Custom:$Start-$Stop" }
$output = & $cctk "--PrimaryBattChargeCfg=$value" 2>&1 | Out-String
$code = $LASTEXITCODE
$new = Get-ChargeCfg

if ($code -ne 0) {
    Show-Result "Failed to set charge mode (cctk exit $code).`n`n$($output.Trim())" 'Error'; exit $code
}

$msg = if ($Mode -eq 'Full') {
    "Charging to 100% enabled (Standard).`nRun 'Battery 65% limit' when back on AC."
} else {
    "Charge limit set: stops at $Stop%, resumes below $Start%."
}
Show-Result "$msg`n`nBIOS setting: $new`n$(Get-BatteryText)"
