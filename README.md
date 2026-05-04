# dms-system-plugin

System/process widget plugin for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

This repository packages a system monitor as a normal DMS plugin. It does not include or overwrite a personal DMS config.

## What It Adds

- Process popout with CPU, GPU, RAM and swap cards.
- CPU detail view:
  - current CPU usage and temperature
  - 1-minute sparkline with gaps when polling was stopped
  - max and average CPU frequency
  - per-core frequency grid
  - EPP mode switcher
- GPU detail view:
  - total GPU memory, shared memory and resident memory
  - per-process GPU memory table with sorting
- Process list improvements:
  - RAM/swap/GPU columns
  - remembered sort/search/scroll state
  - expanded rows with full command, PPID, swap and GPU metrics
  - inline `Kill` button
- DankBar plugin pill with CPU and RAM summary.
- Plugin popout with processes, CPU details and GPU memory details.

## Requirements

- Linux desktop running Wayland.
- DankMaterialShell with plugin support.
- `dgop` available in `PATH`.
- `python3` for CPU frequency and per-process extra metric helpers.

The plugin uses DMS primitives such as `Theme`, `DgopService`, `PluginComponent` and shared widgets.

## Install

```bash
git clone https://github.com/KappaShilaff/dms-system-plugin.git
cd dms-system-plugin
./install.sh
systemctl --user restart dms.service
```

The installer copies `plugin/DmsSystemPlugin` into:

```text
${DMS_PLUGIN_DIR:-~/.config/DankMaterialShell/plugins}/DmsSystemPlugin
```

After restart, enable the plugin in DMS settings and add the widget to DankBar.

## Uninstall

```bash
./uninstall.sh
systemctl --user restart dms.service
```

## Notes

- The plugin depends on `dgop` for system/process metrics.
- CPU frequency details are read from `/sys/devices/system/cpu`.
- GPU memory details read per-process DRM fdinfo metrics through the plugin helper and merge them with `DgopService` process data. The parser supports Intel-style `drm-total/resident/shared-*` counters and AMD `drm-memory-*` counters.
- The CPU helper is resolved relative to the loaded plugin directory, so custom `DMS_PLUGIN_DIR` installs work.
- Search in the process list matches the visible process name and PID. It intentionally does not match the full command line, because long VM/QEMU args create noisy false positives.

## License

MIT

This plugin is based on and intended for DankMaterialShell, which is MIT-licensed.
See: https://github.com/AvengeMedia/DankMaterialShell
