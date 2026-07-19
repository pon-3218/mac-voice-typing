import Foundation
import Speech
import AVFoundation

struct FinalTranscriptAssembler {
    private struct Segment {
        let start: Double
        let end: Double
        let text: String
    }

    private var segmentsByStart: [Double: Segment] = [:]

    mutating func upsert(start: Double, end: Double, text: String) {
        let normalizedStart = start.isFinite ? start : 0
        let normalizedEnd = end.isFinite ? end : normalizedStart
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            segmentsByStart.removeValue(forKey: normalizedStart)
            return
        }
        segmentsByStart[normalizedStart] = Segment(
            start: normalizedStart,
            end: normalizedEnd,
            text: text
        )
    }

    var text: String {
        segmentsByStart.values
            .sorted {
                if $0.start == $1.start { return $0.end < $1.end }
                return $0.start < $1.start
            }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func collect<Results: AsyncSequence>(
        _ results: Results,
        segment: (Results.Element) -> (start: Double, end: Double, text: String)
    ) async throws -> String {
        var assembler = FinalTranscriptAssembler()
        for try await result in results {
            let value = segment(result)
            assembler.upsert(start: value.start, end: value.end, text: value.text)
        }
        return assembler.text
    }
}

final class BatchTranscriber: @unchecked Sendable {
    func transcribe(fileURL: URL, languageMode: LanguageMode) async throws -> String {
        let requested = Locale(identifier: languageMode.preferredLocaleIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw AppError.transcriptionUnavailable("対応する言語モデルがありません。")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)

        let collector = Task { () throws -> String in
            try await FinalTranscriptAssembler.collect(transcriber.results) { result in
                (
                    start: result.range.start.seconds,
                    end: result.range.end.seconds,
                    text: String(result.text.characters)
                )
            }
        }

        do {
            if let end = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            _ = try? await collector.value
            throw error
        }
    }
}
