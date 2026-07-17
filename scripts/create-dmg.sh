#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
    print -u2 "Usage: $0 <app-path> <volume-name> <output-dmg>"
    exit 64
fi

project_dir="${0:A:h:h}"
app_path="${1:A}"
volume_name="$2"
output_path="$3"
dmgbuild_python="${DMGBUILD_PYTHON:-python3}"
background_dir=$(mktemp -d "${TMPDIR:-/tmp}/voice-input-local-dmg-background.XXXXXX")
background_path="$background_dir/background.png"

cleanup() {
    find "$background_dir" -depth -delete
}
trap cleanup EXIT

if [[ ! -d "$app_path" || "$app_path" != *.app ]]; then
    print -u2 "App bundle not found: $app_path"
    exit 66
fi

if ! "$dmgbuild_python" -c 'import dmgbuild' 2>/dev/null; then
    print -u2 "dmgbuild is required. Install scripts/requirements-release.txt into a virtual environment and set DMGBUILD_PYTHON."
    exit 69
fi

mkdir -p "${output_path:h}"
rm -f "$output_path"
xcrun swift "$project_dir/scripts/render-dmg-background.swift" "$background_path"

"$dmgbuild_python" -m dmgbuild \
    --settings "$project_dir/scripts/dmg-settings.py" \
    -D "app_path=$app_path" \
    -D "background_path=$background_path" \
    "$volume_name" \
    "$output_path"
