# Power Manager

One small window for a Dell laptop: switch the battery charge mode without rebooting, using Dell Command | Configure (`cctk.exe`), and force Windows to sleep.

- **Window**: a small window shows the current limit (65% or 100%), with one button to switch it and a **Force Sleep** button
- **Full**: Standard charging to 100% (use before going unplugged)
- **Limit**: Custom charging, stops at 65% and resumes below 50% (configurable with `-Start` / `-Stop`)
- **Toggle**: switch between the two
- **Status**: show the current setting

## Requirements

- Dell laptop with [Dell Command | Configure](https://www.dell.com/support/kbdoc/en-us/000178000/dell-command-configure) installed
- No BIOS admin password set (otherwise `cctk.exe` refuses the change)
- PowerShell 7 (`pwsh`) to run the installer; the shortcut uses the built-in Windows PowerShell
- Admin rights once, to install

## Install

Clone or download this repo, then run:

```powershell
pwsh -File Install.ps1
```

Approve the single UAC prompt. The installer:

1. Copies `PowerManager.ps1` to `C:\Program Files\PowerManager` (only admins can edit it there).
2. Registers an on-demand scheduled task, `\PowerManager\Window`, that runs as you with highest privileges.
3. Creates one desktop shortcut, **Power Manager**, that starts that task.
4. Removes the earlier Battery Charge setups (its task, shortcut and Program Files folder, and the older two-icon tasks and shortcuts), if present.

After that, double-click **Power Manager**. There's **no UAC prompt**. A small window shows whether charging is capped at 65% or uncapped, along with the battery level. One button switches it: **Charge to 100%** when capped, **Cap at 65%** when uncapped. The change takes effect immediately, with no reboot.

**Force Sleep** puts the laptop to sleep straight away. It first checks `powercfg /requests` for apps that are keeping Windows awake (for example a browser playing video). If it finds any, it lists them and asks before closing them. Each app gets 10 seconds to close normally, and any still running after that are killed, so unsaved work in them is lost. Windows processes such as `svchost` and `explorer` are never closed. On a Modern Standby laptop, sleep is Modern Standby, so the laptop then hibernates according to its "Hibernate after" power setting.

Task Scheduler closes the window if it's left open for more than an hour.

To install again after editing the script (for example to change the 65% limit), run `Install.ps1` again.

## Uninstall

Run in an elevated PowerShell:

```powershell
Unregister-ScheduledTask -TaskPath '\PowerManager\' -TaskName Window -Confirm:$false
Remove-Item "$env:ProgramFiles\PowerManager" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Power Manager.lnk"
```

## Manual usage

From an elevated prompt, or let the script prompt for UAC itself:

```powershell
pwsh -File PowerManager.ps1 -Mode Window
pwsh -File PowerManager.ps1 -Mode Limit -Start 50 -Stop 65
pwsh -File PowerManager.ps1 -Mode Full
pwsh -File PowerManager.ps1 -Mode Status
```

Dell limits: `-Start` 50–95, `-Stop` 55–100, and `-Stop` must be at least 5 higher than `-Start`.
