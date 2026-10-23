# Known issues

## External monitors on a Thunderbolt dock not detected after wake or hibernate

**Status:** under investigation (last updated 23 October 2026). A test is running; see [Next steps](#next-steps).

### Symptoms

- After the laptop wakes from standby or resumes from hibernate on the dock, the external monitors stay blank or aren't detected.
- Replugging the dock's Thunderbolt cable doesn't help, and the behaviour is erratic.
- Only a restart brings the monitors back.

Most of the time it fixes itself at the next wake, so you may only notice the occasional bad case.

### Where it was seen

| | |
|---|---|
| Laptop | Dell Pro Max 16 Premium (MA16250), Windows 11 Pro 25H2 (build 26200.9457), BIOS 1.13.1 |
| Thunderbolt ports | 2 × Thunderbolt 5 (a separate Intel "Barlow Ridge" chip) and 1 × Thunderbolt 4 (built into the Intel Core Ultra processor) |
| Port layout | The two Thunderbolt 5 ports are side by side, next to the HDMI port. The single Thunderbolt 4 port is on the opposite side of the laptop. Both Thunderbolt 5 ports are on the same chip, so moving a cable between them doesn't change the controller. |
| Dock | Dell WD22TB4 Thunderbolt 4 dock, on a Thunderbolt 5 port |
| Monitors | Dell U4320Q and LG UltraFine, both through the dock |
| Graphics | Intel Arc Pro 140T (drives the dock's monitors) and NVIDIA RTX PRO 2000 |

### Analysis

**1. The dock's monitor link fails to rebuild during power transitions.**

Every time the laptop wakes or enters standby, Windows' USB4 connection manager rebuilds the DisplayPort connection that runs through the Thunderbolt cable to the dock. Sometimes the rebuild fails. Windows logs it in the System log (source `Microsoft-Windows-USB-USB4DeviceRouter-EventLogs`, event ID 2):

> A monitor attached to your hub or dock could not be enumerated by the USB4 Connection Manager. This may be expected if the dock or system does not have sufficient resources or bandwidth to support the monitor. ReasonCode1:0x2

The event details show the laptop's DisplayPort input wasn't available (`DpInRouterDepth=255`, `DpInLocalCapabilities=0`, `IsRebuilding=true`), as if it was still held by the previous connection.

**2. It started before hibernate was used, so hibernate isn't the cause.**

| Period | Monitor-link failures |
|---|---|
| 8–17 October | 0 |
| 18–23 October | 8 (18 Oct ×3, 19 Oct, 21 Oct, 22 Oct ×2, 23 Oct) |

Six of the eight happened before this laptop ever hibernated (first hibernate: 22 October, 19:49). They happened around ordinary standby and wake. Hibernate is one more power transition, so it can trigger the failure too.

**3. On 23 October it got stuck and only a restart fixed it.**

| Time | Event |
|---|---|
| 22:34 (previous night) | Lid closed on battery, off the dock, so the laptop hibernated. The dock was connected while it was off. |
| 07:29:13 | Resumed from hibernate. The monitor link came up. |
| 07:29:48 | Windows entered standby 35 seconds later. |
| **07:30:01** | **Monitor link failed to rebuild** (event ID 2). |
| 07:32:44 | The link reported OK again, but the monitors didn't work. |
| 07:33–09:07 | The dock cable was replugged several times. **Windows made no new monitor-link attempt at all**: no USB4 event, unlike every other connect in the previous two weeks. |
| 09:03 | When the dock was unplugged, its USB hub took 26 seconds to detach (Kernel-PnP watchdog events 900 and 933). |
| 09:09 | Restart. The monitors came back, and the link set up normally at 09:09:56. |

The laptop's Thunderbolt controller was left in a state that only a restart cleared.

**4. Firmware and drivers are current, so an update won't fix it.**

The dock's components, checked with Dell's updater (`/componentsvers`), all match Dell's latest WD22TB4 package, 01.01.13.01 (March 2026):

| Dock component | Version on the dock | Latest package |
|---|---|---|
| MST hub (drives both monitors) | 05.07.08 | 05.07.08 |
| Gen1 USB hub | 01.25 | 01.25 |
| Gen2 USB hub | 01.66 | 01.66 |
| Dock Thunderbolt firmware (NVM) | 41.81 | 41.81 |
| Dock controller (EC) | 01.01.00.16 | 01.01.00.16 |

The dock reports an older *package* label (01.01.03.01) because it keeps the label from its last full install. Compare the components, not the package label. The laptop BIOS (1.13.1) is newer than any version on Dell's public pages.

**5. Ruled out:**

- **Fast Startup:** turned off.
- **Unexpected shutdowns:** none (no Kernel-Power 41 events).
- **Unexpected wakes:** nothing woke the laptop.
- **Device Manager:** no errors on the dock or Thunderbolt devices.
- **Intel display driver errors** (`Intel-Gfx-Display-External` log, event ID 10): the same error appears 7–35 times a day, at every dock connect and disconnect, on days when everything worked. It's background noise, not this problem.

### Current hypothesis

Windows' USB4 connection manager, running the dock on the laptop's **separate Thunderbolt 5 controller**, sometimes doesn't release the DisplayPort input when it tears down the dock's monitor connection. The rebuild then fails for lack of resources. Usually the next wake recovers; occasionally the controller stays stuck until a restart.

Not yet proven. The test below checks whether the controller is the cause.

### Workaround: reset the Thunderbolt controller instead of restarting

Restarting only the Thunderbolt controller the dock is on should clear the stuck state without restarting Windows. The dock disconnects for a few seconds. **Not yet tested.**

In an admin PowerShell:

```powershell
pnputil /restart-device "<host router instance ID>"
```

Instance IDs on the test laptop (yours will differ):

| Controller | Instance ID |
|---|---|
| Thunderbolt 5 (separate chip, where the dock was when it failed) | `PCI\VEN_8086&DEV_5781&SUBSYS_00008086&REV_84&USB4_MS_CM\8A1E98000000ECE400` |
| Thunderbolt 4 (built into the processor, where the dock is now) | `PCI\VEN_8086&DEV_7EC2&SUBSYS_0D331028&REV_10&USB4_MS_CM\3&11583659&0&6A` |

**Find the controller your dock is on.** This walks up from the dock to its host router:

```powershell
$id = (Get-PnpDevice -PresentOnly | Where-Object FriendlyName -match 'USB4 Router.*Dock' | Select-Object -First 1).InstanceId
while ($id -and $id -notmatch 'USB4_MS_CM') { $id = (Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_Parent).Data }
$id
```

The result is the instance ID to put in the `pnputil` command. Change the `'USB4 Router.*Dock'` pattern if your dock has a different name. `Get-PnpDevice -PresentOnly -FriendlyName 'USB4(TM) Host Router*'` lists all controllers.

### Check your own laptop

Count the dock monitor-link failures (event ID 2) and successes (event ID 1):

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-USB-USB4DeviceRouter-EventLogs' } |
    Sort-Object TimeCreated | ForEach-Object { '{0}  {1}' -f $_.TimeCreated, $(if ($_.Id -eq 2) { 'FAILED' } else { 'OK' }) }
```

### Next steps

- [ ] **Controller test (running since 23 October, 10:45).** The dock was moved from a Thunderbolt 5 port (one of the pair next to HDMI) to the single Thunderbolt 4 port on the opposite side, which is on the processor's built-in controller. After a few days of normal use, compare monitor-link failures with the 8 in 6 days on the Thunderbolt 5 port. Few or none would point to the Thunderbolt 5 controller or its driver. The WD22TB4 is a Thunderbolt 4 dock, so it runs at 40 Gbps on either port.
- [ ] **Test the reset command** the next time the monitors get stuck, and record here whether it works.
- [ ] **If the reset works,** add a **Reset dock** button to Power Manager that finds the dock's controller and restarts it.
- [ ] **If failures continue on the Thunderbolt 4 port,** try setting *PCI Express > Link State Power Management* to Off when plugged in (currently Maximum power saving), then test again.
- [ ] **Report to Dell support** with this evidence if the cause is confirmed on Dell hardware with current firmware.
- [ ] **Check the Intel Arc graphics driver** (32.0.101.8724, April 2026) against Dell's recommended version for the laptop.
