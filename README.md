# Dank Fan Stats

Simple Dank Material Shell fan widget with a root daemon for hardware access.

## Files

Root service files in this folder:

- `install.sh`
- `dank-fan-stats.service`
- `dank-fan-stats-daemon.sh`

Dank Material Shell plugin files:

- `.config/DankMaterialShell/plugins/dankFanStats/plugin.json`
- `.config/DankMaterialShell/plugins/dankFanStats/DankFanStats.qml`
- `.config/DankMaterialShell/plugins/dankFanStats/DankFanStatsSettings.qml`

Plugin settings:

- `/home/spreadsheets600/.config/DankMaterialShell/plugin_settings.json`

## What It DoeS

- Runs a root daemon to read fan speed from EC/debugfs.
- Writes widget data to `/run/dank-fan-stats/stats.json`.
- Exposes a control FIFO at `/run/dank-fan-stats/control`.
- Lets the DMS widget toggle cooler boost on click.

## Install

```bash
sudo /home/spreadsheets600/.local/share/dank-fan-stats/install.sh
sudo systemctl restart dank-fan-stats.service
```

## Check

```bash
systemctl status dank-fan-stats.service
cat /run/dank-fan-stats/stats.json
```

## Reload DMS

Restart Dank Material Shell or Quickshell after plugin changes so the widget reloads.


## Resources

MSI EC - https://github.com/BeardOverflow/msi-ec
DankMaterialShell - https://github.com/AvengeMedia/DankMaterialShelL
