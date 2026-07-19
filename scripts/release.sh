#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
mode="${1:-local}"
app_name="Voice Input Local"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")
release_dir="$project_dir/dist/releases/$version"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/voice-input-local-release.XXXXXX")
app_path="$work_dir/$app_name.app"
stable_archive_path=""

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$release_dir"

case "$mode" in
    local)
        SIGNING_IDENTITY=- \
        APP_OUTPUT_DIR="$app_path" \
            "$project_dir/build-app.sh" release

        archive_path="$release_dir/Voice-Input-Local-$version-macOS-development.zip"
        rm -f "$archive_path"
        ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
        ;;

    notarized)
        : "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
        : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

        APP_OUTPUT_DIR="$app_path" \
            "$project_dir/build-app.sh" release

        codesign --verify --deep --strict --verbose=2 "$app_path"

        archive_path="$release_dir/Voice-Input-Local-$version-macOS.dmg"
        "$project_dir/scripts/create-dmg.sh" \
            "$app_path" \
            "$app_name" \
            "$archive_path"

        expected_team_id=$(codesign -dv --verbose=4 "$app_path" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')
        "$project_dir/scripts/verify-dmg.sh" \
            "$archive_path" \
            "$app_name" \
            "jp.co.ntc.voice-input-local" \
            "$expected_team_id"

        codesign \
            --force \
            --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$archive_path"

        xcrun notarytool submit \
            "$archive_path" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        xcrun stapler staple "$archive_path"
        xcrun stapler validate "$archive_path"

        stable_archive_path="$release_dir/Voice-Input-Local-macOS.dmg"
        rm -f "$stable_archive_path"
        ditto "$archive_path" "$stable_archive_path"

        : "${SPARKLE_EDDSA_PRIVATE_KEY:?Set SPARKLE_EDDSA_PRIVATE_KEY to the exported Sparkle private key}"
        sparkle_generate_appcast=$(find "$project_dir/.build/artifacts" -type f -path '*/bin/generate_appcast' -print -quit)
        if [[ -z "$sparkle_generate_appcast" ]]; then
            print -u2 "Sparkle generate_appcast tool was not found"
            exit 66
        fi
        appcast_dir="$work_dir/appcast"
        mkdir -p "$appcast_dir"
        ditto "$archive_path" "$appcast_dir/${archive_path:t}"
        print -- "- 音声認識が一文字だけになる問題を修正\n- 自動アップデートに対応" > "$appcast_dir/Voice-Input-Local-$version-macOS.md"
        print -rn -- "$SPARKLE_EDDSA_PRIVATE_KEY" | \
            "$sparkle_generate_appcast" \
                --ed-key-file - \
                --download-url-prefix "https://github.com/pon-3218/mac-voice-typing/releases/download/v$version/" \
                --link "https://github.com/pon-3218/mac-voice-typing/releases/tag/v$version" \
                --embed-release-notes \
                --maximum-deltas 0 \
                -o "$appcast_dir/appcast.xml" \
                "$appcast_dir"
        ditto "$appcast_dir/appcast.xml" "$release_dir/appcast.xml"
        ;;

    *)
        print -u2 "Usage: $0 [local|notarized]"
        exit 64
        ;;
esac

(
    cd "${archive_path:h}"
    shasum -a 256 "${archive_path:t}" > "${archive_path:t}.sha256"
)
if [[ -n "$stable_archive_path" ]]; then
    (
        cd "${stable_archive_path:h}"
        shasum -a 256 "${stable_archive_path:t}" > "${stable_archive_path:t}.sha256"
    )
    (
        cd "$release_dir"
        shasum -a 256 appcast.xml > appcast.xml.sha256
    )
fi
print "$archive_path"
