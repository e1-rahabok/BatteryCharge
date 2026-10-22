# One-time setup so the desktop icon opens the battery charge window without a UAC prompt.
#  - Copies BatteryCharge.ps1 to C:\Program Files\BatteryCharge (admin-only write, so the
#    elevated task can't be hijacked by editing the script).
#  - Registers a scheduled task (\BatteryCharge\Window) that runs as you with highest
#    privileges, on demand only.
#  - The desktop shortcut starts that task with Start-ScheduledTask, which needs no elevation.
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
# The window stays open until closed, so allow it an hour before Task Scheduler ends it.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew

$action = New-ScheduledTaskAction -Execute $ps -WorkingDirectory $dest `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Mode Window"
Register-ScheduledTask -TaskPath '\BatteryCharge\' -TaskName Window -Action $action `
    -Principal $principal -Settings $settings -Description 'Show and switch the battery charge limit' -Force | Out-Null

$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Battery Charge.lnk'))
# Starting a task needs no elevation; show why if it fails instead of failing silently.
$lnk.TargetPath = $ps
$lnk.Arguments = '-NoProfile -WindowStyle Hidden -Command "try { Start-ScheduledTask -TaskPath ''\BatteryCharge\'' ' +
    '-TaskName Window -ErrorAction Stop } catch { Add-Type -AssemblyName System.Windows.Forms; ' +
    '[void][System.Windows.Forms.MessageBox]::Show(''Could not start the Battery Charge task. Run Install.ps1 again.'' + ' +
    '[char]10 + [char]10 + $_.Exception.Message, ''Battery Charge'', ''OK'', ''Error'') }"'
$lnk.WorkingDirectory = $dest
$lnk.IconLocation = "$env:SystemRoot\System32\powercpl.dll,0"
$lnk.Description = 'Show and switch the battery charge limit'
$lnk.WindowStyle = 7   # minimized
$lnk.Save()

# Remove the earlier two-icon setup.
foreach ($old in 'Full', 'Limit') {
    Get-ScheduledTask -TaskPath '\BatteryCharge\' -TaskName $old -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false
}
Remove-Item (Join-Path $desktop 'Battery 100% charge.lnk'), (Join-Path $desktop 'Battery 65% limit.lnk') `
    -ErrorAction SilentlyContinue

# Remove the earlier per-user copy.
Remove-Item (Join-Path $env:LOCALAPPDATA 'BatteryCharge') -Recurse -Force -ErrorAction SilentlyContinue
