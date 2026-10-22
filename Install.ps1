# One-time setup so the desktop icon opens the Power Manager window without a UAC prompt.
#  - Copies PowerManager.ps1 to C:\Program Files\PowerManager (admin-only write, so the
#    elevated task can't be hijacked by editing the script).
#  - Registers a scheduled task (\PowerManager\Window) that runs as you with highest
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

$dest = Join-Path $env:ProgramFiles 'PowerManager'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'PowerManager.ps1') $dest -Force
$script = Join-Path $dest 'PowerManager.ps1'

# Windows PowerShell lives in System32 (admin-protected), unlike the Store pwsh alias.
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
# The window stays open until closed, so allow it an hour before Task Scheduler ends it.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew

$action = New-ScheduledTaskAction -Execute $ps -WorkingDirectory $dest `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Mode Window"
Register-ScheduledTask -TaskPath '\PowerManager\' -TaskName Window -Action $action `
    -Principal $principal -Settings $settings -Description 'Switch the battery charge limit and force sleep' -Force | Out-Null

$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Power Manager.lnk'))
# Starting a task needs no elevation; show why if it fails instead of failing silently.
$lnk.TargetPath = $ps
$lnk.Arguments = '-NoProfile -WindowStyle Hidden -Command "try { Start-ScheduledTask -TaskPath ''\PowerManager\'' ' +
    '-TaskName Window -ErrorAction Stop } catch { Add-Type -AssemblyName System.Windows.Forms; ' +
    '[void][System.Windows.Forms.MessageBox]::Show(''Could not start the Power Manager task. Run Install.ps1 again.'' + ' +
    '[char]10 + [char]10 + $_.Exception.Message, ''Power Manager'', ''OK'', ''Error'') }"'
$lnk.WorkingDirectory = $dest
$lnk.IconLocation = "$env:SystemRoot\System32\powercpl.dll,0"
$lnk.Description = 'Switch the battery charge limit and force sleep'
$lnk.WindowStyle = 7   # minimized
$lnk.Save()

# Remove the earlier Battery Charge setups: the one-window task and the older two-icon tasks,
# their shortcuts, the Program Files copy and the per-user copy.
foreach ($old in 'Window', 'Full', 'Limit') {
    Get-ScheduledTask -TaskPath '\BatteryCharge\' -TaskName $old -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false
}
$taskService = New-Object -ComObject Schedule.Service
$taskService.Connect()
try { $taskService.GetFolder('\').DeleteFolder('BatteryCharge', 0) } catch {}   # fails if absent or not empty
Remove-Item (Join-Path $desktop 'Battery Charge.lnk'), (Join-Path $desktop 'Battery 100% charge.lnk'),
    (Join-Path $desktop 'Battery 65% limit.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:ProgramFiles 'BatteryCharge'), (Join-Path $env:LOCALAPPDATA 'BatteryCharge') `
    -Recurse -Force -ErrorAction SilentlyContinue
