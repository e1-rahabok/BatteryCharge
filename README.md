# BatteryCharge

Switch a Dell laptop's battery charge mode without rebooting, using Dell Command | Configure (`cctk.exe`).

- **Full**: Standard charging to 100% (use before going unplugged)
- **Limit**: Custom charging, stops at 65% and resumes below 50% (configurable with `-Start` / `-Stop`)
- **Toggle**: switch between the two
- **Status**: show the current setting

## Requirements

- Dell laptop with [Dell Command | Configure](https://www.dell.com/support/kbdoc/en-us/000178000/dell-command-configure) installed
- PowerShell 7 (`pwsh`)
- Admin rights (the script re-launches itself elevated)

## Install

```powershell
pwsh -File Install.ps1
```

Copies the script to `%LOCALAPPDATA%\BatteryCharge` and creates two desktop shortcuts: **Battery 100% charge** and **Battery 65% limit**.

## Usage

```powershell
pwsh -File BatteryCharge.ps1 -Mode Limit -Start 50 -Stop 65
pwsh -File BatteryCharge.ps1 -Mode Status
```
