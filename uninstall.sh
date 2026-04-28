#!/usr/bin/env bash
set -euo pipefail

plugin_dir="${DMS_PLUGIN_DIR:-$HOME/.config/DankMaterialShell/plugins}"
target_dir="$plugin_dir/DmsSystemPlugin"

if [[ ! -d "$target_dir" ]]; then
  echo "Plugin is not installed: $target_dir" >&2
  exit 1
fi

removed_dir="${target_dir}.removed-$(date +%Y%m%d-%H%M%S)"
mv "$target_dir" "$removed_dir"

echo "Removed DmsSystemPlugin."
echo "Backup moved to: $removed_dir"
echo "Restart DMS with: systemctl --user restart dms.service"
