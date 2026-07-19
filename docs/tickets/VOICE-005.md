# VOICE-005 公開版の自動アップデートに対応する

## 対象アプリ

Voice Input Local

## 対象リポジトリ

`/Users/pon/dev/mac-voice-typing`

## 目的

GitHub Releasesで公開した新しい公証済みバージョンを、インストール済みアプリから確認・取得・置換できるようにする。

## 背景

v0.1.5まではstable DMG URLを公開しているが、アプリ自身は更新を検知せず、利用者がDMGを手動で再インストールする必要がある。

## やること

- Sparkle 2をSwift Package依存として固定する
- 起動後の自動更新確認とバックグラウンド更新を有効にする
- メニューバーに手動更新確認を追加する
- Sparkle.frameworkと内部ヘルパーをDeveloper IDで順に署名して同梱する
- Release workflowでEdDSA署名済みappcastを生成し、GitHub Releaseへ公開する
- 公開DMG、appcast、署名、公証、Gatekeeperを検証する

## やらないこと

- 独自更新UIの実装
- Mac App Store配布への変更
- v0.1.5以前のアプリへ後付けで自動更新機能を注入すること

## 完了条件

- v0.1.6以降のアプリが定期的に更新を確認する
- 「アップデートを確認…」から手動確認できる
- appcastの更新アーカイブがEdDSA署名されている
- 公開DMGにSparkle.frameworkが含まれ、Developer ID署名・公証・Gatekeeper検証に成功する
- v0.1.6以降の次回Releaseで同じworkflowから更新情報を公開できる

## 検証方法

- Sparkle設定・包装・appcast公開のcontract testを修正前に失敗させる
- `swift test`
- `swift build`
- Developer ID署名で`./build-app.sh release`
- 公開appcastのXMLとEdDSA署名属性を確認する
- stable DMGを公開URLから再取得して完全検証する

## TDD結果

- 修正前: Sparkle設定・包装テスト10 assertion、appcast公開テスト4 assertionが失敗した。
- 修正後: `swift test`で17テストが成功した。
- `swift build`が成功した。
- Developer ID Application署名のReleaseビルドが成功した。
- `codesign --verify --deep --strict`でアプリとSparkle内部コンポーネントの署名を確認した。
- GitHub Actions Release run 29677461771が成功し、v0.1.6を公開した。
- 公開stable DMGのSHA-256、ディスクイメージ、Developer ID署名、Apple公証、Gatekeeperを検証した。
- 公開appcastのXML、SHA-256、v0.1.6/build 7、更新DMGのEdDSA署名を検証した。
- 公開DMGから`/Applications/Voice Input Local.app`へv0.1.6を再インストールして起動した。
- 更新確認時刻`SULastCheckTime`が更新され、公開appcastへの自動確認が動作した。
