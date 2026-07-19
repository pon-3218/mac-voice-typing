# VOICE-003 音声入力中に他アプリの音声出力を抑制する

## 対象アプリ

Voice Input Local

## 対象リポジトリ

`/Users/pon/dev/mac-voice-typing`

## 目的

音声入力中にYouTubeなど他アプリの再生音が聞こえたり、マイクへ回り込んだりしないようにする。

## 背景

現在はFnホールド中もシステム出力が通常音量で再生されるため、利用者の発話と他アプリの音声が重なる。

## やること

- 録音開始時にAVAudioEngineのVoice Processingを有効にする
- 他アプリ音声へのduckingを最大レベルにする
- エコーキャンセルでマイクへの再生音の回り込みを抑制する
- 録音停止、開始失敗、キャンセル、アプリ終了でVoice Processingを停止する

## やらないこと

- YouTubeなど個別アプリの再生・停止操作
- 音声認識方式の変更
- 常時のシステム音量変更

## 完了条件

- Fnホールド中だけ他アプリの音声出力が最大レベルで抑制される
- ホールド終了後は録音余韻の終了時に通常再生へ戻る
- 失敗・キャンセル・終了時にもVoice Processingが停止する

## 検証方法

- Voice Processing、最大ducking、停止処理の契約テストを先に追加する
- `swift test`
- `swift build`
- 実機で再生音声を流しながらFnホールド前後の出力状態を確認する

## 2026-07-19 調査結果

`setVoiceProcessingEnabled(true)`を有効にした実アプリで、CoreAudioのVoice Processorが録音中に`audio time stamp does not have valid sample time`と`ProcessDownlinkAudio`のI/Oエラーを連続発生させた。保存履歴では導入直後から5〜64.2秒の録音6件がすべて「あ」一文字になったため、音声認識の復旧を優先してVoice Processingによる抑制を撤回した。本チケットは代替方式が決まるまで`open`のままとする。
