<p align="center">
  <img src="docs/images/voice-input-local-hero.png" alt="Voice Input Local — Fnを押して話し、離すと入力" width="100%">
</p>

# Voice Input Local

音声入力だけを担当する、Dockに表示されないmacOSメニューバー常駐アプリです。

Fnを押している間だけ録音し、キーを離すとローカルで文字起こしします。認識結果は、話し始めた時にフォーカスしていた入力欄へ直接反映されます。

## 特徴

- Fnなどのホールド中だけマイクを使用
- Apple SpeechAnalyzerによるローカル文字起こし
- ホールド開始時の入力欄を保持して認識結果を直接入力
- Unicode入力、Accessibility、Command+Vのフォールバック
- クリップボードへのコピーと最大500件の入力履歴
- 入力中のフローティングHUD
- ログイン時の自動起動

24時間録音、システム音声取得、会議管理、要約、Todo生成は含みません。

## 必要環境

- macOS 26以降
- Apple Silicon Mac
- Xcode 26 / Swift 6.3

## インストール

```bash
git clone https://github.com/pon-3218/voice-input-local.git
cd voice-input-local
./install-app.sh
```

`/Applications/VoiceInputLocal.app`へインストールされ、メニューバーに常駐します。初回起動時にマイクとアクセシビリティの許可が必要です。

開発ビルドでmacOSの権限が失効しないよう、初回インストール時にローカル専用の安定したコード署名証明書を作成します。秘密鍵はMacのローカルキーチェーンに保存され、リポジトリには含まれません。

## 開発

```bash
swift test
swift build
./build-app.sh
```

## License

[MIT License](LICENSE)
