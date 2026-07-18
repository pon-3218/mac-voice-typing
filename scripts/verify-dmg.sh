#!/bin/zsh
set -euo pipefail

if [[ $# -ne 4 ]]; then
    print -u2 "Usage: $0 <dmg-path> <app-name> <bundle-id> <team-id>"
    exit 64
fi

dmg_path="${1:A}"
app_name="$2"
expected_bundle_id="$3"
expected_team_id="$4"
mount_point=""

cleanup() {
    if [[ -n "$mount_point" ]]; then
        hdiutil detach "$mount_point" >/dev/null
    fi
}
trap cleanup EXIT

attach_output=$(hdiutil attach -readonly -nobrowse "$dmg_path")
mount_point=$(print -r -- "$attach_output" | awk -F '\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -n 1)
if [[ -z "$mount_point" ]]; then
    print -u2 "Unable to locate mounted DMG volume"
    exit 66
fi

app_path="$mount_point/$app_name.app"
if [[ ! -d "$app_path" ]]; then
    print -u2 "App bundle missing from DMG: $app_name.app"
    exit 66
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
actual_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
actual_team_id=$(codesign -dv --verbose=4 "$app_path" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')

[[ "$actual_bundle_id" == "$expected_bundle_id" ]]
[[ "$actual_team_id" == "$expected_team_id" ]]
