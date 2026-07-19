import AVFoundation
import Foundation

/// Fnを押している間だけマイクを起動する。待機中は prepare のみで音声を取得しない。
final class OnDemandMicrophoneCapture: @unchecked Sendable {
    static let postRollSeconds: TimeInterval = 0.30

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "jp.co.ntc.voice-input-local.on-demand-mic")
    private var preparedFormat: AVAudioFormat?
    private var tapInstalled = false

    // queue 内だけで触る。
    private var activeStream: MicStreamTranscriber?
    private var activeFile: AVAudioFile?
    private var writeError: Error?

    var format: AVAudioFormat? { preparedFormat }
    var isCapturing: Bool { engine.isRunning }

    /// ハードウェア形式の取得とグラフ準備だけを行う。マイク入力は開始しない。
    func prepare() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        var format = input.inputFormat(forBus: 0)
        if format.sampleRate <= 0 {
            engine.prepare()
            format = input.inputFormat(forBus: 0)
        }
        guard format.sampleRate > 0 else {
            throw AppError.captureSetupFailed("マイクの入力形式を取得できません。")
        }
        preparedFormat = format
        engine.prepare()
    }

    func startRecording(stream: MicStreamTranscriber, file: AVAudioFile) throws {
        guard !engine.isRunning else {
            throw AppError.captureSetupFailed("マイクはすでに使用中です。")
        }

        try prepare()
        guard let format = preparedFormat else {
            throw AppError.captureSetupFailed("マイクの入力形式を取得できません。")
        }

        queue.sync {
            activeStream = stream
            activeFile = file
            writeError = nil
        }

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self, let copied = Self.copy(buffer) else { return }
            self.queue.async { self.receive(copied) }
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            queue.sync {
                activeStream = nil
                activeFile = nil
            }
            throw error
        }
    }

    /// タップ停止以前のバッファを直列キューで書き切ってからファイルを閉じる。
    func stopRecording() throws {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        let error = queue.sync { () -> Error? in
            activeStream = nil
            activeFile = nil
            let error = writeError
            writeError = nil
            return error
        }
        if let error { throw error }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        activeStream?.feed(buffer)
        guard let file = activeFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            if writeError == nil { writeError = error }
            activeFile = nil
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copied.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copied.mutableAudioBufferList)
        for index in 0..<min(source.count, destination.count) {
            guard let sourceData = source[index].mData,
                  let destinationData = destination[index].mData else { continue }
            memcpy(destinationData, sourceData, min(Int(source[index].mDataByteSize), Int(destination[index].mDataByteSize)))
        }
        return copied
    }
}
