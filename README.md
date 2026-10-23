# Dank Fan Stats

A [Dux Shell 2.0](https://github.com/duxlabs-dev/dux-shell) bar widget for MSI laptops
running the [`msi-ec`](https://github.com/BeardOverflow/msi-ec) kernel driver. It
shows fan speed and temperatures in the bar and opens a tabbed popout for
performance modes, battery care, the advanced fan curve, and the keyboard
backlight.

## Features

- **Bar pill** with fan RPM, CPU temperature, GPU temperature, or CPU temperature
  plus RPM. The fan icon can be hidden.
- **Stats tab** with live CPU/GPU temperatures, fan percentages, fan RPM, the
  active performance/fan mode, firmware version, and daemon status.
- **Settings tab** with grouped performance and fan-mode selectors, Cooler Boost,
  Super Battery, camera privacy controls, and battery charge thresholds.
- **Curve tab** with a draggable seven-point CPU/GPU fan curve, six temperature
  thresholds, Silent / Balanced / Performance presets, and a one-click apply.
- **Keyboard tab** with backlight levels and the Fn / Windows key swap.
- **Capability detection**: controls the firmware does not expose are hidden or
  disabled instead of failing silently.
- **Right-click** the pill to toggle Cooler Boost.
- **Persistent settings**: the daemon reapplies the last known state after a
  reboot or EC reset.

## Requirements

- Dux Shell 2.0 or newer (`requires_dms: ">=2.0.0"`).
- An MSI laptop supported by the `msi-ec` kernel driver.
- Root access for the helper daemon.
- `ec_sys` for raw EC fan RPM reads and advanced fan-curve writes.

## Install

### From the plugin registry

Search for **Dank Fan Stats** in the Dux Shell plugin registry or with:

```bash
dms plugins search
```

Install the plugin, then install the root service from the plugin directory:

```bash
sudo ~/.config/dms/plugins/dankFanStats/Service/install.sh
```

### From a local checkout

```bash
git clone https://github.com/SpreadSheets600/dankFanStatus \
  ~/.config/dms/plugins/dankFanStats
sudo ~/.config/dms/plugins/dankFanStats/Service/install.sh
```

The installer:

1. Installs the daemon to `/usr/local/bin/dank-fan-stats-daemon`.
2. Installs and enables `dank-fan-stats.service`, detecting the desktop user.
3. Loads `ec_sys` so fan RPM can be read.
4. Enables `write_support=1` so the advanced fan curve can be programmed.
5. Reloads `ec_sys` and restarts the service.

## How it works

The privileged daemon reads fan RPM from the embedded controller through
read-only `ec_sys` and reads the remaining telemetry from the `msi-ec` sysfs
device. It publishes a JSON snapshot to:

```text
/run/dank-fan-stats/stats.json
```

Commands are written to a root-owned FIFO:

```text
/run/dank-fan-stats/control
```

The widget polls the snapshot only while the bar surface is live or the popout is
open, so a hidden widget does not keep waking the daemon.

| Control | MSI EC attribute |
| :--- | :--- |
| Performance mode | `shift_mode` |
| Fan mode | `fan_mode` |
| Cooler Boost | `cooler_boost` |
| Super Battery | `super_battery` |
| Webcam / Block Webcam | `webcam`, `webcam_block` |
| Fn / Windows key position | `fn_key`, `win_key` |
| Keyboard backlight | LED `msiacpi::kbd_backlight` |
| Battery charge start / end | `charge_control_start_threshold`, `charge_control_end_threshold` |
| Advanced curve | raw EC fan-curve table |

Keyboard backlight, fan RPM, and the fan curve are not exposed as regular
`msi-ec` sysfs values. The backlight is a standard kernel LED class device, while
fan RPM and the curve are accessed through the raw EC debugfs node.

## Fan curve

The advanced fan mode uses a table in raw EC memory:

- CPU temperatures `0x6A-0x6F`, CPU fan levels `0x72-0x78`
- GPU temperatures `0x82-0x87`, GPU fan levels `0x8A-0x90`
- Fan mode register `0xD4` (`auto` `0x0D`, `advanced` `0x8D`)

Reads work with read-only `ec_sys`. Writes require `ec_sys write_support=1`,
installed to `/etc/modprobe.d/ec_sys.conf`. The debugfs node stays root-only, so
only the daemon can write it.

Before writing, the daemon validates that:

- every temperature and fan level is between 0 and 100,
- temperatures are strictly ascending,
- fan levels are non-decreasing.

The curve is restored before `advanced` is reselected after a reboot.

## Settings persistence

The MSI EC forgets its state on power loss. The daemon stores applied settings in:

```text
/var/lib/dank-fan-stats/settings.conf
```

On startup it replays the file before the first refresh:

- performance and fan mode, including `advanced`,
- Cooler Boost and Super Battery,
- webcam and webcam block,
- Fn / Windows key positions,
- battery charge thresholds,
- keyboard backlight level,
- the advanced fan curve.

Values are read back from the kernel after each write, so the file reflects the
final state. On replay, every value is validated again; a mode that is no longer
available or an invalid curve is skipped. Delete the file to return to firmware
defaults.

## Widget settings

The plugin settings page exposes:

- **Pill content**: fan RPM, CPU temperature, GPU temperature, or CPU temperature
  and fan RPM.
- **Show fan icon**: hide the icon and keep only the value.
- **Refresh interval**: 1-10 seconds.
- **Stats file path** and **control FIFO path**, for non-default deployments.

## Diagnostics

```bash
systemctl status dank-fan-stats.service
journalctl -u dank-fan-stats.service -f
cat /run/dank-fan-stats/stats.json
```

A healthy snapshot starts with `"ok": true` and includes capability flags such as
`advancedSupported`, `curveWritable`, `coolerBoostSupported`, `chargeSupported`,
`kbdBacklightSupported`, `fnKeySupported`, and `winKeySupported`.

## Control FIFO commands

```text
set shift_mode <eco|comfort|sport|turbo>
set fan_mode <auto|silent|basic|advanced>
set cooler_boost <on|off|toggle>
set super_battery <on|off|toggle>
set webcam <on|off|toggle>
set webcam_block <on|off|toggle>
set fn_key <left|right>
set win_key <left|right>
set charge_start <0-100>
set charge_end <0-100>
set fan_curve <6 cpu temps> <7 cpu levels> <6 gpu temps> <7 gpu levels>
set advanced <on|off>
set kbd_backlight <0-3>
refresh
```

`fan_curve` arguments are comma-separated integers:

```text
set fan_curve 50,60,65,70,75,80 0,40,50,60,70,80,85 50,60,65,70,75,80 0,40,50,60,70,80,85
```

Charge thresholds must satisfy `start < end`; the daemon clamps out-of-order
values before writing.

## Files

Root service files (`Service/`):

- `install.sh`
- `dank-fan-stats.service`
- `dank-fan-stats-daemon.sh`
- `ec_sys.conf`
- `ec_sys-write.conf`

Plugin files (repository root):

- `plugin.json`
- `DankFanStats.qml`
- `DankFanStatsSettings.qml`

## Reload the widget

```bash
dms ipc call plugins reload dankFanStats
```

## Resources

- MSI EC - https://github.com/BeardOverflow/msi-ec
- Dux Shell - https://github.com/duxlabs-dev/dux-shell
- Plugin registry - https://plugins.duxlabs.dev
