# Copies BatteryCharge.ps1 to %LOCALAPPDATA%\BatteryCharge and creates desktop shortcuts.
# Run once: pwsh -File Install.ps1   (no admin needed)

$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:LOCALAPPDATA 'BatteryCharge'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'BatteryCharge.ps1') $dest -Force
$script = Join-Path $dest 'BatteryCharge.ps1'

# App execution alias stays valid across Store updates of PowerShell 7.
$pwsh = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
if (-not (Test-Path $pwsh)) { $pwsh = (Get-Command pwsh).Source }

$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
$icon = "$env:SystemRoot\System32\powercpl.dll,0"

$shortcuts = @(
    @{ Name = 'Battery 100% charge'; Mode = 'Full';   Desc = 'Charge battery to 100% (before going unplugged)' }
    @{ Name = 'Battery 65% limit';   Mode = 'Limit';  Desc = 'Limit battery charge to 65% (when on AC)' }
)
foreach ($s in $shortcuts) {
    $lnk = $shell.CreateShortcut((Join-Path $desktop "$($s.Name).lnk"))
    $lnk.TargetPath = $pwsh
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Mode $($s.Mode)"
    $lnk.WorkingDirectory = $dest
    $lnk.IconLocation = $icon
    $lnk.Description = $s.Desc
    $lnk.WindowStyle = 7   # minimized
    $lnk.Save()
    "Created: $($s.Name)"
}
