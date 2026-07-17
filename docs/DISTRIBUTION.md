# Distribution

## Development archive

```bash
./scripts/release.sh local
```

`dist/releases/<version>/`へad-hoc署名のZIPとSHA-256ファイルを生成します。これは開発確認用であり、一般配布には使用しません。

## Public distribution outside the Mac App Store

Apple Developer ProgramのDeveloper ID Application証明書と、公証用のnotarytoolプロファイルが必要です。

```bash
security find-identity -v -p codesigning
```

公証資格情報はKeychainへ保存します。アプリ用パスワードをコマンド履歴へ直接残さないでください。

```bash
xcrun notarytool store-credentials "voice-input-local-notary" \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID"
```

Apple Silicon向けのDeveloper ID署名、公証、DMG作成、staple、SHA-256生成を実行します。
DMGはアプリとApplicationsフォルダを左右に配置したドラッグインストール形式で生成します。

ローカルでDMG生成を確認する場合は、専用の仮想環境へ固定バージョンの`dmgbuild`をインストールします。

```bash
python3 -m venv .release-venv
.release-venv/bin/pip install -r scripts/requirements-release.txt
APP_OUTPUT_DIR="$PWD/dist/Voice Input Local.app" \
  ALLOW_ADHOC_SIGNING=1 \
  ./build-app.sh release
DMGBUILD_PYTHON="$PWD/.release-venv/bin/python" \
  ./scripts/create-dmg.sh \
  "dist/Voice Input Local.app" \
  "Voice Input Local" \
  "/tmp/Voice-Input-Local-preview.dmg"
```

```bash
SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARY_PROFILE="voice-input-local-notary" \
./scripts/release.sh notarized
```

出力先:

```text
dist/releases/<version>/Voice-Input-Local-<version>-macOS.dmg
dist/releases/<version>/Voice-Input-Local-<version>-macOS.dmg.sha256
```

## Verification

```bash
./scripts/verify-app.sh "VoiceInputLocal.app"
xcrun stapler validate "dist/releases/<version>/Voice-Input-Local-<version>-macOS.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "dist/releases/<version>/Voice-Input-Local-<version>-macOS.dmg"
```

## GitHub release secrets

`.github/workflows/release.yml`には次のRepository secretsが必要です。

- `DEVELOPER_ID_CERTIFICATE_P12`: Developer ID Application証明書のP12をBase64化した値
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: P12のパスワード
- `DEVELOPER_ID_APPLICATION`: `Developer ID Application: ...`形式の署名ID
- `APPLE_ID`: 公証に使用するApple Account
- `APPLE_TEAM_ID`: Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: Apple Accountのアプリ用パスワード

タグ名と`Info.plist`のバージョンを一致させます。例: `v0.1.0`。
