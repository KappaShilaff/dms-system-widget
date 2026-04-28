#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="${DMS_PLUGIN_DIR:-$HOME/.config/DankMaterialShell/plugins}"
source_dir="$repo_dir/plugin/DmsSystemPlugin"
target_dir="$plugin_dir/DmsSystemPlugin"

if [[ ! -d "$source_dir" ]]; then
  echo "Plugin source not found: $source_dir" >&2
  exit 1
fi

mkdir -p "$plugin_dir"

if [[ -e "$target_dir" ]]; then
  backup_dir="${target_dir}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$target_dir" "$backup_dir"
  echo "Existing plugin moved to: $backup_dir"
fi

cp -a "$source_dir" "$target_dir"

echo "Installed DmsSystemPlugin into: $target_dir"
echo "Restart DMS with: systemctl --user restart dms.service"
