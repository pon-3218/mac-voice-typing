#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_path="${1:-$project_dir/VoiceInputLocal.app}"

[[ -d "$app_path" ]] || {
    print -u2 "App not found: $app_path"
    exit 66
}

plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_path"

executable="$app_path/Contents/MacOS/VoiceInputLocal"
file "$executable"
lipo -archs "$executable"

if codesign -dv --verbose=4 "$app_path" 2>&1 | grep -q 'Authority=Developer ID Application'; then
    codesign -d --entitlements :- "$app_path" >/dev/null
    spctl --assess --type execute --verbose=4 "$app_path"
else
    print "Development signature detected; Gatekeeper distribution assessment skipped."
fi
