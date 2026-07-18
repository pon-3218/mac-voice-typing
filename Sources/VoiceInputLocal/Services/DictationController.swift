import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable { case idle, listening, transcribing }

    var phase: Phase = .idle
    var partialText = ""
    var languageMode: LanguageMode = .auto
    var lastError: String?

    private let capture = OnDemandMicrophoneCapture()
    private let batchTranscriber = BatchTranscriber()
    private var stream: MicStreamTranscriber?
    private var setupTask: Task<Void, Never>?
    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private var insertionTarget: TextInserter.FocusedTarget?

    var onFinished: (() -> Void)?
    var onDeliveredText: ((_ text: String, _ duration: TimeInterval, _ languageMode: LanguageMode) -> Void)?

    /// 権限取得後に呼び、音声を取得せずグラフだけ準備する。
    func prepareCapture() {
        try? capture.prepare()
    }

    func startListening() {
        guard phase == .idle else { return }
        insertionTarget = TextInserter.captureFocusedTarget()
        phase = .listening
        partialText = ""
        lastError = nil
        let transcriber = MicStreamTranscriber()
        transcriber.onUpdate = { [weak self] _, _, _ in
            Task { @MainActor in
                guard let self, self.phase == .listening else { return }
                self.partialText = transcriber.currentText()
            }
        }
        stream = transcriber
        guard startCapture(transcriber) else {
            stream = nil
            return
        }
        let locale = Locale(identifier: languageMode.preferredLocaleIdentifier)
        setupTask = Task { await transcriber.start(locale: locale) }
    }

    private func startCapture(_ transcriber: MicStreamTranscriber) -> Bool {
        do { try capture.prepareForRecording() } catch {
            lastError = error.localizedDescription
            finishWithoutText()
            return false
        }
        guard let format = capture.format, format.sampleRate > 0 else {
            lastError = "マイクの入力形式を取得できません。"
            finishWithoutText()
            return false
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vll-dictation-\(UUID().uuidString).caf")
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            lastError = "音声入力の一時ファイルを作成できません。"
            finishWithoutText()
            return false
        }
        fileURL = url
        audioFile = file
        do {
            try capture.startRecording(stream: transcriber, file: file)
        } catch {
            lastError = error.localizedDescription
            audioFile = nil
            fileURL = nil
            try? FileManager.default.removeItem(at: url)
            finishWithoutText()
            return false
        }
        return true
    }

    func stopAndDeliver() {
        guard phase == .listening else { return }
        phase = .transcribing
        Task { await finishUp() }
    }

    func cancel() {
        setupTask?.cancel()
        setupTask = nil
        stream?.cancel()
        stream = nil
        try? capture.stopRecording()
        audioFile = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        insertionTarget = nil
        phase = .idle
        onFinished?()
    }

    private func finishUp() async {
        // キー解放と発話末尾は一致しないため、短い余韻を録音してから境界を閉じる。
        try? await Task.sleep(for: .seconds(OnDemandMicrophoneCapture.postRollSeconds))
        do {
            try capture.stopRecording()
        } catch {
            lastError = error.localizedDescription
        }
        setupTask?.cancel()
        stream?.cancel()
        stream = nil
        audioFile = nil

        var text = ""
        var duration: TimeInterval = 0
        if let url = fileURL {
            if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 {
                duration = Double(file.length) / file.processingFormat.sampleRate
            }
            if duration >= 0.4 {
                do {
                    text = try await batchTranscriber.transcribe(fileURL: url, languageMode: languageMode)
                } catch {
                    lastError = error.localizedDescription
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        if !text.isEmpty {
            partialText = text
            TextInserter.deliver(text, to: insertionTarget)
            onDeliveredText?(text, duration, languageMode)
        }
        insertionTarget = nil
        phase = .idle
        onFinished?()
    }

    private func finishWithoutText() {
        try? capture.stopRecording()
        audioFile = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        insertionTarget = nil
        phase = .idle
        onFinished?()
    }
}
