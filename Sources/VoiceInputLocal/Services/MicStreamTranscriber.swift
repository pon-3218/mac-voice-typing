import Foundation
import Speech
import AVFoundation
import CoreMedia
import Darwin
import os

/// マイク音声を SpeechAnalyzer へストリーミング入力し、暫定→確定結果をリアルタイムに返す。
/// 音声タップ（別スレッド）から feed され、結果は onUpdate で通知する。
final class MicStreamTranscriber: @unchecked Sendable {

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var isReadyForInput = false
    private var resultsTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?
    private var preReadyBuffers: [AVAudioPCMBuffer] = []
    private var preReadyFrameCount: AVAudioFramePosition = 0
    private var preReadySampleRate: Double = 0

    /// start をキーにした認識結果1件分。
    typealias SegmentValue = (end: Double, text: String)

    private let lock = NSLock()
    private var segments: [Double: SegmentValue] = [:]
    // MEET-023/MEET-038: segments は upsert のたびに増える一方だと常時録音（数時間）で
    // メモリが単調増加する。LiveSegmentStore.defaultRetention と同値（720秒）の直近ウィンドウだけ
    // 保持する。定数は共有せず、対応関係をここに明記するローカル定数にとどめる。
    private static let segmentRetentionSeconds: Double = 720
    /// これまでに観測した最大 end（単調増加。prune の基準に使う）。
    private var latestSegmentEnd: Double = 0
    private var diagnosticLabel: String?
    private var diagnosticStartUptimeNanos: UInt64?
    private var didLogFirstFeedBeforeReady = false
    private var didLogFirstFeedSuccess = false
    private var didLogFirstResult = false
    private var feedBeforeReadyCount = 0
    private var feedBeforeReadyFrames: AVAudioFramePosition = 0
    private var resultCount = 0
    private var feedCount = 0
    private var lastFeedLogUptimeNanos: UInt64 = 0
    private static let updateThrottleNanos: UInt64 = 250_000_000
    private var lastUpdateEmitUptimeNanos: UInt64 = 0
    private var pendingUpdate: (start: Double, end: Double, text: String)?
    private var updateEmitTask: Task<Void, Never>?
    private static let maxPreReadyBufferSeconds: Double = 5
    // MEET-033: cancel() が start() のセットアップ完了より先に呼ばれた場合を検知するためのフラグ。
    // Task.isCancelled だけに頼ると、cancel() を呼んだ側（MainActor）と start() を実行する
    // Task の間で伝播タイミングにずれがあり、start() がチェックをすり抜けて
    // analyzer/AsyncStream/Task を「誰にも止められない状態」で生成してしまう恐れがある。
    private var didCancel = false

    /// 認識結果（暫定含む）が更新されるたびに、その「変更分の1区間」だけで呼ばれる。
    /// 全履歴の sort・全件 re-emit はしない（MEET-017: 録音長に比例する MainActor 負荷の除去）。
    /// 受け手側が開始時刻をキーに差分マージする前提。
    var onUpdate: (@Sendable (_ start: Double, _ end: Double, _ text: String) -> Void)?

    private let isFinishedLock = OSAllocatedUnfairLock(initialState: false)

    /// 解析ループ（analyzer.start）が正常終了・エラー終了いずれかで止まったら true になる。
    /// @MainActor から安全に読める（音声フレームは書き込まれ続けても文字起こしが恒久停止した状態を検知するため）。
    var isFinished: Bool {
        isFinishedLock.withLock { $0 }
    }

    func setDiagnostics(label: String, startedAtUptimeNanos: UInt64) {
        lock.lock()
        diagnosticLabel = label
        diagnosticStartUptimeNanos = startedAtUptimeNanos
        lock.unlock()
    }

    /// SpeechAnalyzer 周辺を事前に初期化しておく（初回押下時の遅延を減らすウォームアップ）。
    /// アセット導入 API は起動直後に不安定な環境があるため、明示フラグ時だけ呼ぶ。
    static func prewarm(locale: Locale) async {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        Dbg.log("[dictation][prewarm] start locale=\(locale.identifier)")
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if Self.shouldInstallSpeechAssets {
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Dbg.log("[dictation][prewarm] assetInstallationRequest begin")
                try? await request.downloadAndInstall()
                Dbg.log("[dictation][prewarm] assetInstallationRequest end")
            } else {
                Dbg.log("[dictation][prewarm] assetInstallationRequest none")
            }
        } else {
            Dbg.log("[dictation][prewarm] assetInstallationRequest skipped")
        }
        guard !Task.isCancelled else { return }
        let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard !Task.isCancelled else { return }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        await analyzer.cancelAndFinishNow()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        Dbg.log("[dictation][prewarm] end locale=\(locale.identifier) target=\(Self.describe(format: target)) elapsedMs=\(String(format: "%.1f", elapsed))")
    }

    /// 認識エンジンを準備して入力受付を開始する。
    func start(locale: Locale) async {
        diagnosticLog("MicStreamTranscriber.start locale=\(locale.identifier)")
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if Self.shouldInstallSpeechAssets {
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                diagnosticLog("assetInstallationRequest begin")
                try? await request.downloadAndInstall()
                diagnosticLog("assetInstallationRequest end")
            } else {
                diagnosticLog("assetInstallationRequest none")
            }
        } else {
            diagnosticLog("assetInstallationRequest skipped")
        }
        diagnosticLog("bestAvailableAudioFormat begin")
        let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        diagnosticLog("bestAvailableAudioFormat end target=\(Self.describe(format: target))")

        // MEET-033: 解放時に setupTask.cancel() で中途終了させるようになったため、ここまでの
        // await（アセット導入・フォーマット決定）の間にキャンセルされていたら、analyzer/AsyncStream を
        // 立ち上げずに即座に終了する。立ち上げてしまうと finishUp 側の stream.cancel() より後に
        // continuation/analyzeTask/resultsTask が生成され、誰にも止められず残り続ける（リーク）。
        if Task.isCancelled {
            diagnosticLog("start cancelled before analyzer setup")
            markFinished()
            return
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        var buffersToReplay: [AVAudioPCMBuffer] = []
        var framesToReplay: AVAudioFramePosition = 0

        let cancelledBeforeCommit = lock.withLock {
            // cancel() が Task.isCancelled チェックと、ここでの状態コミットの間に割り込んでいたら、
            // analyzer/continuation を確定させずに畳む。
            let cancelled = didCancel
            if !cancelled {
                self.transcriber = transcriber
                self.analyzer = analyzer
                self.targetFormat = target
                self.continuation = continuation
                self.isReadyForInput = true
                buffersToReplay = preReadyBuffers
                framesToReplay = preReadyFrameCount
                preReadyBuffers = []
                preReadyFrameCount = 0
                preReadySampleRate = 0
            }
            return cancelled
        }

        if cancelledBeforeCommit {
            diagnosticLog("start cancelled just before analyzer commit")
            continuation.finish()
            markFinished()
            return
        }

        resultsTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    if let logNumber = self?.markResultForLog() {
                        self?.diagnosticLog(
                            "result #\(logNumber) start=\(Self.describe(seconds: start)) end=\(Self.describe(seconds: end)) chars=\(text.count)"
                        )
                    }
                    self?.upsert(
                        start: start.isFinite ? start : 0,
                        end: end.isFinite ? end : start,
                        text: text
                    )
                }
                self?.diagnosticLog("results loop ended count=\(self?.currentResultCount() ?? 0)")
            } catch {
                self?.diagnosticLog("results loop error domain=\((error as NSError).domain) code=\((error as NSError).code)")
            }
        }
        analyzeTask = Task { [weak self, weak analyzer, stream] in
            self?.diagnosticLog("analyzer start")
            defer { self?.markFinished() }
            do {
                try await analyzer?.start(inputSequence: stream)
                self?.diagnosticLog("analyzer ended")
            } catch {
                self?.diagnosticLog("analyzer error domain=\((error as NSError).domain) code=\((error as NSError).code)")
                Dbg.log("[live] transcriber finished error=\(error.localizedDescription)")
            }
        }
        diagnosticLog("analyzer ready")
        if !buffersToReplay.isEmpty {
            diagnosticLog("replay pre-ready buffers count=\(buffersToReplay.count) frames=\(framesToReplay)")
            for buffer in buffersToReplay {
                feed(buffer)
            }
        }
    }

    private static var shouldInstallSpeechAssets: Bool {
        ProcessInfo.processInfo.environment["MRL_INSTALL_SPEECH_ASSETS"] == "1"
    }

    /// 音声バッファを供給する（音声タップスレッドから呼ばれる）。
    func feed(_ buffer: AVAudioPCMBuffer) {
        var logMessage: String?
        lock.lock()
        guard isReadyForInput, let continuation else {
            feedBeforeReadyCount += 1
            feedBeforeReadyFrames += AVAudioFramePosition(buffer.frameLength)
            retainPreReadyBuffer(buffer)
            if !didLogFirstFeedBeforeReady {
                didLogFirstFeedBeforeReady = true
                logMessage = "first feed before analyzer ready inputFrames=\(buffer.frameLength) input=\(Self.describe(format: buffer.format))"
            }
            lock.unlock()
            if let logMessage { diagnosticLog(logMessage) }
            return
        }
        let target = targetFormat
        let output: AVAudioPCMBuffer?
        if let target {
            output = convert(buffer, to: target)
        } else {
            output = buffer
        }
        guard let output else {
            lock.unlock()
            return
        }
        if !didLogFirstFeedSuccess {
            didLogFirstFeedSuccess = true
            lastFeedLogUptimeNanos = DispatchTime.now().uptimeNanoseconds
            logMessage = "first feed success inputFrames=\(buffer.frameLength) outputFrames=\(output.frameLength) target=\(Self.describe(format: target)) droppedBeforeReadyBuffers=\(feedBeforeReadyCount) droppedBeforeReadyFrames=\(feedBeforeReadyFrames)"
        } else if let feedAlive = markFeedAliveForLog(inputFrames: buffer.frameLength, outputFrames: output.frameLength) {
            logMessage = feedAlive
        }
        continuation.yield(AnalyzerInput(buffer: output))
        lock.unlock()
        if let logMessage { diagnosticLog(logMessage) }
    }

    /// 認識器が準備できる前の冒頭音声を短時間だけ保持する。
    /// 会議開始直後に話した音声が、そのまま欠落するのを避ける。
    private func retainPreReadyBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        let sampleRate = max(copy.format.sampleRate, 1)
        if preReadySampleRate == 0 { preReadySampleRate = sampleRate }
        preReadyBuffers.append(copy)
        preReadyFrameCount += AVAudioFramePosition(copy.frameLength)

        let maxFrames = AVAudioFramePosition(Self.maxPreReadyBufferSeconds * preReadySampleRate)
        while preReadyFrameCount > maxFrames, !preReadyBuffers.isEmpty {
            let dropped = preReadyBuffers.removeFirst()
            preReadyFrameCount -= AVAudioFramePosition(dropped.frameLength)
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copied = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copied.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let copiedBuffers = UnsafeMutableAudioBufferListPointer(copied.mutableAudioBufferList)
        let count = min(sourceBuffers.count, copiedBuffers.count)
        for index in 0..<count {
            guard let source = sourceBuffers[index].mData,
                  let destination = copiedBuffers[index].mData else { continue }
            let byteCount = min(Int(sourceBuffers[index].mDataByteSize), Int(copiedBuffers[index].mDataByteSize))
            memcpy(destination, source, byteCount)
        }
        return copied
    }

    /// 入力を終了して最終テキストを返す。
    func finish() async -> String {
        let continuation = lock.withLock { self.continuation }
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        analyzeTask?.cancel()
        return currentText()
    }

    /// 結果を待たずに即座に停止（ライブ表示用途で、最終結果が不要なとき）。
    /// start() のセットアップ中（analyzer/AsyncStream 未確定）に呼ばれた場合は didCancel を立て、
    /// start() 側がコミット直前にそれを検知して確定させずに畳むことでリークを防ぐ。
    func cancel() {
        lock.lock()
        didCancel = true
        let continuation = self.continuation
        let updateEmitTask = self.updateEmitTask
        self.updateEmitTask = nil
        self.pendingUpdate = nil
        lock.unlock()
        diagnosticLog("stream cancel")
        continuation?.finish()
        updateEmitTask?.cancel()
        resultsTask?.cancel()
        analyzeTask?.cancel()
    }

    func currentText() -> String {
        lock.lock()
        let joined = segments.sorted { $0.key < $1.key }.map { $0.value.text }.joined()
        lock.unlock()
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 内部

    /// 「最新 end から retention 秒より古いキー」を落とした segments を返す純関数。
    /// 副作用なし・ロック不要（呼び出し側で lock 保持中に呼ぶ想定）。
    ///
    /// ディクテーション用途（数十秒〜数分）では latestEnd - retention が全キーの start を
    /// 下回るため何も落ちない。720秒を超えて連続入力し続けるケースはほぼないが、万一
    /// 超えた場合は currentText()（全文取得）から古い区間が欠落する（常時録音の
    /// onUpdate 差分通知は upsert 時点で発火済みのため影響を受けない）。
    static func pruning(
        segments: [Double: SegmentValue],
        latestEnd: Double,
        retention: Double
    ) -> [Double: SegmentValue] {
        let cutoff = latestEnd - retention
        guard cutoff > 0 else { return segments }
        return segments.filter { $0.key >= cutoff }
    }

    private func upsert(start: Double, end: Double, text: String) {
        let e = max(start, end)
        let now = DispatchTime.now().uptimeNanoseconds
        var immediateUpdate: (start: Double, end: Double, text: String)?
        var callback: (@Sendable (_ start: Double, _ end: Double, _ text: String) -> Void)?
        lock.lock()
        segments[start] = (end: e, text: text)
        if e > latestSegmentEnd { latestSegmentEnd = e }
        segments = Self.pruning(segments: segments, latestEnd: latestSegmentEnd, retention: Self.segmentRetentionSeconds)
        if lastUpdateEmitUptimeNanos == 0 || now - lastUpdateEmitUptimeNanos >= Self.updateThrottleNanos {
            lastUpdateEmitUptimeNanos = now
            pendingUpdate = nil
            immediateUpdate = (start, e, text)
            callback = onUpdate
        } else {
            pendingUpdate = (start, e, text)
            if updateEmitTask == nil {
                let delay = Self.updateThrottleNanos - (now - lastUpdateEmitUptimeNanos)
                updateEmitTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delay)
                    self?.emitPendingUpdate()
                }
            }
        }
        lock.unlock()
        if let immediateUpdate {
            callback?(immediateUpdate.start, immediateUpdate.end, immediateUpdate.text)
        }
    }

    private func emitPendingUpdate() {
        var update: (start: Double, end: Double, text: String)?
        var callback: (@Sendable (_ start: Double, _ end: Double, _ text: String) -> Void)?
        lock.lock()
        update = pendingUpdate
        pendingUpdate = nil
        updateEmitTask = nil
        if update != nil {
            lastUpdateEmitUptimeNanos = DispatchTime.now().uptimeNanoseconds
            callback = onUpdate
        }
        lock.unlock()
        if let update {
            callback?(update.start, update.end, update.text)
        }
    }

    private func markFinished() {
        isFinishedLock.withLock { $0 = true }
    }

    private func markResultForLog() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        resultCount += 1
        let count = resultCount
        if !didLogFirstResult {
            didLogFirstResult = true
            return count
        }
        if count <= 5 || count.isMultiple(of: 10) {
            return count
        }
        return nil
    }

    private func currentResultCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return resultCount
    }

    private func markFeedAliveForLog(inputFrames: AVAudioFrameCount, outputFrames: AVAudioFrameCount) -> String? {
        feedCount += 1
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastFeedLogUptimeNanos >= 10_000_000_000 else { return nil }
        lastFeedLogUptimeNanos = now
        return "feed alive count=\(feedCount) inputFrames=\(inputFrames) outputFrames=\(outputFrames)"
    }

    private func diagnosticLog(_ event: String) {
        lock.lock()
        let label = diagnosticLabel
        let start = diagnosticStartUptimeNanos
        lock.unlock()
        guard let label, let start else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        Dbg.log("[speech][\(label)] +\(String(format: "%.1f", elapsed))ms \(event)")
    }

    private static func describe(format: AVAudioFormat?) -> String {
        guard let format else { return "nil" }
        return "\(format.sampleRate)Hz/\(format.channelCount)ch"
    }

    private static func describe(seconds: Double) -> String {
        seconds.isFinite ? String(format: "%.3f", seconds) : "nan"
    }

    /// 入力フォーマットを認識器の要求フォーマットへ変換する（必要時のみ）。lock 保持中に呼ばれる。
    private func convert(_ input: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if input.format == target { return input }
        if converter == nil || converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: target)
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if error != nil { return nil }
        return output.frameLength > 0 ? output : nil
    }
}
