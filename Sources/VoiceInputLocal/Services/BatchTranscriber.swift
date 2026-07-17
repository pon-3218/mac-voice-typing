import Foundation
import Speech
import AVFoundation

final class BatchTranscriber: @unchecked Sendable {
    func transcribe(fileURL: URL, languageMode: LanguageMode) async throws -> String {
        let requested = Locale(identifier: languageMode.preferredLocaleIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw AppError.transcriptionUnavailable("対応する言語モデルがありません。")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)

        let collector = Task { () -> [String] in
            var values: [String] = []
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { values.append(text) }
                }
            } catch { }
            return values
        }

        if let end = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return await collector.value.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
