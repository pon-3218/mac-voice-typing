# Contributing

不具合はIssueテンプレートに沿って、macOS・Mac・アプリのバージョン、再現手順、期待結果、実際の結果を記載してください。個人情報、音声、入力履歴は添付しないでください。

Pull Requestでは変更理由と検証結果を記載し、次を通してください。

```bash
swift test
swift build
bash -n build-app.sh install-app.sh tools/setup-signing.sh
plutil -lint VoiceInputLocal.entitlements
```

公開配布用のDeveloper ID証明書や公証資格情報をコミットしないでください。
