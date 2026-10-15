# One-time setup so the desktop icons switch the battery charge mode without a UAC prompt.
#  - Copies BatteryCharge.ps1 to C:\Program Files\BatteryCharge (admin-only write, so the
#    elevated task can't be hijacked by editing the script).
#  - Registers two scheduled tasks (\BatteryCharge\Full, \BatteryCharge\Limit) that run as
#    you with highest privileges, on demand only.
#  - Desktop shortcuts start those tasks via schtasks.exe, which needs no elevation.
# Run: pwsh -File Install.ps1   (asks for UAC once)

$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -Wait `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

$dest = Join-Path $env:ProgramFiles 'BatteryCharge'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'BatteryCharge.ps1') $dest -Force
$script = Join-Path $dest 'BatteryCharge.ps1'

# Windows PowerShell lives in System32 (admin-protected), unlike the Store pwsh alias.
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
$tasks = @(
    @{ Mode = 'Full';  Name = 'Battery 100% charge'; Desc = 'Charge battery to 100% (before going unplugged)' }
    @{ Mode = 'Limit'; Name = 'Battery 65% limit';   Desc = 'Limit battery charge to 65% (when on AC)' }
)
foreach ($t in $tasks) {
    $action = New-ScheduledTaskAction -Execute $ps -WorkingDirectory $dest `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Mode $($t.Mode)"
    Register-ScheduledTask -TaskPath '\BatteryCharge\' -TaskName $t.Mode -Action $action `
        -Principal $principal -Settings $settings -Description $t.Desc -Force | Out-Null

    $lnk = $shell.CreateShortcut((Join-Path $desktop "$($t.Name).lnk"))
    $lnk.TargetPath = "$env:SystemRoot\System32\schtasks.exe"
    $lnk.Arguments = "/run /tn `"\BatteryCharge\$($t.Mode)`""
    $lnk.WorkingDirectory = $dest
    $lnk.IconLocation = "$env:SystemRoot\System32\powercpl.dll,0"
    $lnk.Description = $t.Desc
    $lnk.WindowStyle = 7   # minimized
    $lnk.Save()
}

# Remove the earlier per-user copy.
Remove-Item (Join-Path $env:LOCALAPPDATA 'BatteryCharge') -Recurse -Force -ErrorAction SilentlyContinue
