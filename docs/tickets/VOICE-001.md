# VOICE-001 マイク権限とメニューバー表示を修正して公開設定を強化する

## 対象アプリ

Voice Input Local

## 対象リポジトリ

`/Users/pon/dev/mac-voice-typing`

## 目的

Developer ID版でマイク権限を正常に要求でき、インストール後に確実に操作できる状態へ修正する。同時に公開リポジトリと配布経路の主要なセキュリティ不足を解消する。

## 背景

設定画面は開くが、macOSのマイク設定へアプリが登録されず許可できない。インストール済みバイナリはHardened Runtimeで署名されている一方、`com.apple.security.device.audio-input` entitlementが含まれていない。またプロセスは起動しているがメニューバー項目を確認できない。開発用署名Keychainの固定パスワード、DMG生成依存のハッシュ未固定、通常PR用CIと公開文書の不足も確認された。

## スコープ

- Audio Input entitlementを全署名経路へ適用する
- 権限状態に応じた初回起動・設定導線を安定化する
- ステータス項目を明示的に可視化し、アクセス不能を避ける
- 固定パスワードの開発用署名Keychainを廃止する
- DMG生成依存を完全なハッシュロックでインストールする
- 最終DMG内のアプリ署名と構成を公開前に再検証する
- SECURITY、PRIVACY、CONTRIBUTING、Issue/PRテンプレート、通常CIを追加する
- GitHubのPrivate vulnerability reporting、Dependabot、ブランチ・タグ・リリース環境保護を設定する

## やらないこと

- 音声認識方式や入力フォールバック順の変更
- Mac App Store配布への移行
- 履歴UI全体の再設計

## 実装メモ

Hardened RuntimeのAudio Inputは`com.apple.security.device.audio-input`を必要とする。権限修正後は既存TCC状態を整理して再インストールし、実際のDeveloper ID版から許可要求する。

## 完了条件

- 署名済みアプリにAudio Input entitlementが含まれる
- macOSのマイク許可プロンプトが表示され、設定一覧へアプリが登録される
- インストール済みアプリからステータス項目または代替の設定導線へ到達できる
- 公開スクリプトに再利用可能な固定Keychain/P12パスワードが残らない
- リリース用Python依存が`--require-hashes`で失敗閉鎖する
- 公開リポジトリの報告・PR導線とGitHub保護設定が有効になる

## 検証方法

- 先に権限・署名契約テストを追加して失敗を確認する
- `swift test`
- `swift build`
- `./build-app.sh release`後に`codesign -d --entitlements :-`を確認する
- `/Applications/Voice Input Local.app`を再インストールし、マイク許可とメニューバー・設定導線を確認する
- GitHub APIまたは設定画面で保護設定を確認する

## 未確認事項

- ユーザー環境でメニューバー項目が見えない直接要因がノッチによるオーバーフローか、macOS 26の可視性状態かは未確認。両方に耐える実装にする。

## 検証結果

- 2026-07-18: `swift test` 10件、`swift build`、CI相当検証に成功
- 2026-07-18: `/Applications/Voice Input Local.app` 0.1.2 build 3をDeveloper ID署名で起動
- 2026-07-18: Audio Input entitlementをインストール版と公開DMG内アプリで確認
- 2026-07-18: macOSのマイク一覧へ`Voice Input Local.app`が登録され、許可オンであることを実画面確認
- 2026-07-18: 公開DMGのSHA-256、公証staple、Gatekeeper、Bundle ID、Team IDを再検証
- 2026-07-18: [v0.1.2](https://github.com/pon-3218/mac-voice-typing/releases/tag/v0.1.2)を公開
- 2026-07-18: Private vulnerability reporting、Dependabot、secret scanning、push protection、main保護、Immutable Releasesを有効化
