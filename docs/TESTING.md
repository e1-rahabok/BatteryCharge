# Real-life test record

Power Manager 1.0.0 was tested by hand on a real laptop in daily use, not only in a lab or a virtual machine. The hibernate and standby results come from Windows' own event logs, recorded at the time; the others from direct checks on the installed app. You can check the same events on your laptop (see [Check it on your own laptop](#check-it-on-your-own-laptop)).

Tested on 22 October 2026.

## Test laptop

| | |
|---|---|
| Laptop | Dell Pro Max 16 Premium (MA16250), Intel Core Ultra 9 285H, 64 GB RAM |
| Windows | Windows 11 Pro 25H2, build 26200.9457 |
| Sleep type | Modern Standby (S0 low power idle), with hibernate available. Classic sleep (S3) isn't supported by this laptop. |
| Setup | Docked on a Dell Thunderbolt dock (power, Ethernet, external monitor), and carried in a backpack on battery |
| Charge limit tool | Dell Command \| Configure (`cctk.exe`) |

## The problem being fixed

Before Power Manager, the laptop stayed hot with the lid closed, on the dock and in a bag.

Windows' Modern Standby records how much of each standby period the chip spends in its real low-power state. Over the 10 days before testing:

| Where the laptop was | Standby periods of 30 min or more | Time in real low-power state |
|---|---|---|
| On battery, undocked | 23 | 96% |
| Plugged in, no external monitor | 11 | 40% |
| On the dock with an external monitor | 18 | 6% (13 of the 18 never got past "screen off") |

On the test day itself, all 9 standby periods on the dock spent **0%** of their time in the low-power state. The laptop was "asleep" but running at full power. Closing apps doesn't change that, which is why Power Manager uses hibernate (fully off) rather than sleep.

## Results

### 1. Install from the release zip: pass

- Downloaded `PowerManager.zip` through the public "latest release" link. It was byte-for-byte identical to the zip that was built.
- Unzipped it to a new folder and double-clicked `Install.cmd`. One admin prompt appeared.
- The scheduled task `\PowerManager\Window` and the **Power Manager** desktop shortcut were created. The installed script matched the release.
- The window opened from the task with no further admin prompt.

### 2. Window and charge limit reading: pass

- The window opened with the Bloom Glass design, rounded corners and shadow.
- It read the real BIOS setting through Dell Command | Configure and showed **Capped at 65%**, with the tick on the ring at 65%.

### 3. Battery health: pass

The window showed 94.6 Wh original, 94.6 Wh now, 8 cycles, 100% health. Two independent sources agreed:

| Source | Full charge capacity | Cycles |
|---|---|---|
| Power Manager (battery driver, `IOCTL_BATTERY_QUERY_INFORMATION`) | 94,559 mWh | 8 |
| Windows WMI (`BatteryFullChargedCapacity`, `BatteryCycleCount`) | 94,559 mWh | 8 |

The driver query took under 10 ms and needed no admin rights. The laptop is new, so design and full charge capacity are still equal.

### 4. Hibernate now button: pass

Clicked **Hibernate now** while docked, with everyday apps open.

| Measurement | Result |
|---|---|
| Power state entered | Hibernate (S4). Windows logged the trigger as an app request. |
| Time from click to fully off | about 26 seconds (8 s to prepare, 17.6 s to write about 7.8 GB of memory to the SSD) |
| Time off | 14 min 55 s |
| Woken by | Power button only. No wake timer and no device woke it. |
| Resume | Windows logged "resume from hibernate" (boot type 0x2), and the session came back with apps still open |
| Time to desktop | about 30 seconds |

### 5. Closing the lid, then carrying the laptop in a backpack: pass

Lid close set to Hibernate (see [Stop the laptop getting hot in a bag](../README.md#stop-the-laptop-getting-hot-in-a-bag)). Closed the lid while docked, unplugged, and carried the laptop in a backpack.

| Measurement | Result |
|---|---|
| Power state entered | Hibernate (S4). Windows logged the trigger as lid or power button. |
| Time from lid close to fully off | about 25 seconds (17.2 s to write about 7.4 GB of memory) |
| Time off, in the bag | 49 min 57 s |
| Woken by | Opening the lid, on battery. Nothing woke it during the trip. |
| Resume | Windows logged "resume from hibernate" (boot type 0x2), and the session came back with apps still open |
| Time to desktop | about 25 seconds |
| Heat | Not measured with a thermometer. The laptop was fully powered off (S4) for the whole trip, so it wasn't producing heat. Before, it stayed in standby at full power for up to an hour on battery. |

## Not yet tested by hand

- **Switching the charge limit from the new window.** It uses the same `cctk.exe` command as the earlier Battery Charge versions, but the button wasn't clicked again in this release.
- **Laptops other than the Dell above.** The "Not available" charge limit card and the worn-battery colours were checked by rendering the window with sample data, not on another laptop.
- **Other Windows 11 releases** (21H2 to 24H2). The app only uses long-standing Windows interfaces, but only 25H2 was tested.
- **PowerShell 7.** The window was rendered under PowerShell 7.6 to check it loads. The installed shortcut uses the built-in Windows PowerShell 5.1, which was used for all the tests above.

## Check it on your own laptop

Run these in PowerShell after a hibernate test.

Which power state the laptop entered (`TargetState=5` means hibernate. Reason `0` is the lid or power button, `4` is an app such as Hibernate now, and `13` is the automatic "Hibernate after" timer):

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 42 } -MaxEvents 5 |
    ForEach-Object { $d = ([xml]$_.ToXml()).Event.EventData.Data; "$($_.TimeCreated)  TargetState=$(($d | ? Name -eq TargetState).'#text')  Reason=$(($d | ? Name -eq Reason).'#text')" }
```

How long it was off, how long saving and restoring took, and what woke it:

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1 } -MaxEvents 1 |
    ForEach-Object { ([xml]$_.ToXml()).Event.EventData.Data | ? Name -in SleepTime, WakeTime, HiberWriteDuration, HiberReadDuration, BiosInitDuration, WakeSourceText | % { "$($_.Name) = $($_.'#text')" } }
```

Whether standby reaches low power on your laptop (the percentage of each standby period spent in the low-power state; low numbers mean the laptop stays warm in standby):

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 507 } -MaxEvents 10 |
    ForEach-Object { $d = @{}; ([xml]$_.ToXml()).Event.EventData.Data | % { $d[$_.Name] = $_.'#text' }
        if ([double]$d.DurationInUs -gt 0) { '{0}  {1,5:N1} min  {2,3:N0}% low power' -f $_.TimeCreated, ([double]$d.DurationInUs / 6e7), (100 * [double]$d.HwDripsResidencyInUs / [double]$d.DurationInUs) } }
```

Sleep times in the Power-Troubleshooter event are in UTC.
