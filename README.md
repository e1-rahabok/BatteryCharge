# BatteryCharge

Switch a Dell laptop's battery charge mode without rebooting, using Dell Command | Configure (`cctk.exe`).

- **Full**: Standard charging to 100% (use before going unplugged)
- **Limit**: Custom charging, stops at 65% and resumes below 50% (configurable with `-Start` / `-Stop`)
- **Toggle**: switch between the two
- **Status**: show the current setting

## Requirements

- Dell laptop with [Dell Command | Configure](https://www.dell.com/support/kbdoc/en-us/000178000/dell-command-configure) installed
- No BIOS admin password set (otherwise `cctk.exe` refuses the change)
- PowerShell 7 (`pwsh`) to run the installer; the shortcuts use the built-in Windows PowerShell
- Admin rights once, to install

## Install

Clone or download this repo, then run:

```powershell
pwsh -File Install.ps1
```

Approve the single UAC prompt. The installer:

1. Copies `BatteryCharge.ps1` to `C:\Program Files\BatteryCharge` (only admins can edit it there).
2. Registers two on-demand scheduled tasks, `\BatteryCharge\Full` and `\BatteryCharge\Limit`, that run as you with highest privileges.
3. Creates two desktop shortcuts, **Battery 100% charge** and **Battery 65% limit**, that start those tasks.

After that, double-click an icon to switch modes. There's **no UAC prompt**, and a small popup confirms the new setting and the battery level. The change takes effect immediately, with no reboot.

To install again after editing the script (for example to change the 65% limit), run `Install.ps1` again.

## Uninstall

Run in an elevated PowerShell:

```powershell
Unregister-ScheduledTask -TaskPath '\BatteryCharge\' -TaskName Full, Limit -Confirm:$false
Remove-Item "$env:ProgramFiles\BatteryCharge" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Battery*.lnk"
```

## Manual usage

From an elevated prompt, or let the script prompt for UAC itself:

```powershell
pwsh -File BatteryCharge.ps1 -Mode Limit -Start 50 -Stop 65
pwsh -File BatteryCharge.ps1 -Mode Full
pwsh -File BatteryCharge.ps1 -Mode Status
```

Dell limits: `-Start` 50–95, `-Stop` 55–100, and `-Stop` must be at least 5 higher than `-Start`.
