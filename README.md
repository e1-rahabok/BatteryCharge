# BatteryCharge

Switch a Dell laptop's battery charge mode without rebooting, using Dell Command | Configure (`cctk.exe`).

- **Window**: a small window shows the current limit (65% or 100%), with one button to switch it
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
2. Registers an on-demand scheduled task, `\BatteryCharge\Window`, that runs as you with highest privileges.
3. Creates one desktop shortcut, **Battery Charge**, that starts that task.
4. Removes the older two-icon setup (the `Full`/`Limit` tasks and their shortcuts), if present.

After that, double-click **Battery Charge**. There's **no UAC prompt**. A small window shows whether charging is capped at 65% or uncapped, along with the battery level. One button switches it: **Charge to 100%** when capped, **Cap at 65%** when uncapped. The change takes effect immediately, with no reboot.

Task Scheduler closes the window if it's left open for more than an hour.

To install again after editing the script (for example to change the 65% limit), run `Install.ps1` again.

## Uninstall

Run in an elevated PowerShell:

```powershell
Unregister-ScheduledTask -TaskPath '\BatteryCharge\' -TaskName Window -Confirm:$false
Remove-Item "$env:ProgramFiles\BatteryCharge" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Battery Charge.lnk"
```

## Manual usage

From an elevated prompt, or let the script prompt for UAC itself:

```powershell
pwsh -File BatteryCharge.ps1 -Mode Window
pwsh -File BatteryCharge.ps1 -Mode Limit -Start 50 -Stop 65
pwsh -File BatteryCharge.ps1 -Mode Full
pwsh -File BatteryCharge.ps1 -Mode Status
```

Dell limits: `-Start` 50–95, `-Stop` 55–100, and `-Stop` must be at least 5 higher than `-Start`.
