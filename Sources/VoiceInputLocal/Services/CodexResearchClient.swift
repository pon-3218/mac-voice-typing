import Foundation
import Darwin

final class CodexResearchClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case codexNotFound
        case launchFailed(String)
        case protocolFailure(String)
        case connectionClosed
        case emptyResponse
        case timedOut

        var errorDescription: String? {
            switch self {
            case .codexNotFound:
                return "Codex CLIが見つかりません。Codexをインストールし、ログインしてください。"
            case .launchFailed(let detail):
                return detail.isEmpty ? "Codexを起動できませんでした。" : "Codexを起動できませんでした。\n\(detail)"
            case .protocolFailure(let detail):
                return "Codexから回答を取得できませんでした。\n\(detail)"
            case .connectionClosed:
                return "Codexとの接続が終了しました。"
            case .emptyResponse:
                return "Codexから回答が返りませんでした。"
            case .timedOut:
                return "Codexの回答が2分以内に完了しませんでした。"
            }
        }
    }

    func ask(
        question: String,
        onPartialAnswer: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let runner = CodexResearchRunner(
                        question: question,
                        onPartialAnswer: onPartialAnswer
                    )
                    continuation.resume(returning: try runner.run())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class CodexResearchRunner {
    private let question: String
    private let onPartialAnswer: @Sendable (String) -> Void
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let processLock = NSLock()
    private var outputBuffer = Data()
    private var answerChunks: [String] = []
    private var lastPartialPublish = Date.distantPast
    private var timedOut = false

    init(question: String, onPartialAnswer: @escaping @Sendable (String) -> Void) {
        self.question = question
        self.onPartialAnswer = onPartialAnswer
    }

    func run() throws -> String {
        guard let executable = Self.codexExecutableURL() else {
            throw CodexResearchClient.ClientError.codexNotFound
        }

        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe.fileHandleForReading
        process.standardOutput = outputPipe.fileHandleForWriting
        process.standardError = FileHandle.nullDevice
        process.environment = Self.processEnvironment()

        do {
            try process.run()
            try inputPipe.fileHandleForReading.close()
            try outputPipe.fileHandleForWriting.close()
        } catch {
            throw CodexResearchClient.ClientError.launchFailed(error.localizedDescription)
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 120)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.processLock.lock()
            self.timedOut = true
            self.processLock.unlock()
            self.terminateProcessIfNeeded()
        }
        timer.resume()

        defer {
            timer.cancel()
            try? inputPipe.fileHandleForWriting.close()
            terminateProcessIfNeeded()
        }

        try send([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_voice_research",
                    "title": "Voice Input Local",
                    "version": "0.1.7"
                ]
            ]
        ])

        while let line = readLine() {
            guard let message = Self.message(from: line) else { continue }
            if let error = message["error"] as? [String: Any] {
                throw CodexResearchClient.ClientError.protocolFailure(
                    error["message"] as? String ?? "不明なプロトコルエラー"
                )
            }

            let id = (message["id"] as? NSNumber)?.intValue
            if id == 0 {
                try send(["method": "initialized", "params": [:]])
                try send([
                    "method": "thread/start",
                    "id": 1,
                    "params": [
                        "model": "gpt-5.6-luna",
                        "cwd": FileManager.default.temporaryDirectory.path,
                        "approvalPolicy": "never",
                        "sandbox": "read-only",
                        "ephemeral": true,
                        "developerInstructions": "ユーザーの音声から文字起こしされた質問に、日本語で簡潔かつ直接回答してください。必要な場合はWeb検索を使って情報を確認してください。ファイルの変更、コマンド実行、外部サービスへの書き込みは行わないでください。"
                    ]
                ])
            } else if id == 1,
                      let result = message["result"] as? [String: Any],
                      let thread = result["thread"] as? [String: Any],
                      let threadID = thread["id"] as? String {
                try send([
                    "method": "turn/start",
                    "id": 2,
                    "params": [
                        "threadId": threadID,
                        "model": "gpt-5.6-luna",
                        "effort": "low",
                        "approvalPolicy": "never",
                        "sandboxPolicy": ["type": "readOnly", "networkAccess": true],
                        "summary": "none",
                        "input": [["type": "text", "text": question]]
                    ]
                ])
            }

            if message["method"] as? String == "item/agentMessage/delta",
               let params = message["params"] as? [String: Any],
               let delta = params["delta"] as? String {
                answerChunks.append(delta)
                publishPartialAnswerIfNeeded()
            }

            if message["method"] as? String == "turn/completed" {
                var answer = answerChunks.joined()
                if answer.isEmpty { answer = Self.finalMessage(in: message) ?? "" }
                let result = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw CodexResearchClient.ClientError.emptyResponse }
                return result
            }
        }

        processLock.lock()
        let didTimeOut = timedOut
        processLock.unlock()
        if didTimeOut { throw CodexResearchClient.ClientError.timedOut }
        throw CodexResearchClient.ClientError.connectionClosed
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func readLine() -> String? {
        while true {
            if let newline = outputBuffer.firstIndex(of: 0x0A) {
                let data = outputBuffer.prefix(upTo: newline)
                outputBuffer.removeSubrange(outputBuffer.startIndex...newline)
                return String(data: data, encoding: .utf8)
            }
            let chunk = outputPipe.fileHandleForReading.availableData
            if chunk.isEmpty { return nil }
            outputBuffer.append(chunk)
        }
    }

    private func terminateProcessIfNeeded() {
        processLock.lock()
        defer { processLock.unlock() }
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        if pid > 0 { Darwin.kill(pid, SIGTERM) }
    }

    private func publishPartialAnswerIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPartialPublish) >= 0.2 else { return }
        lastPartialPublish = now
        onPartialAnswer(answerChunks.joined())
    }

    private static func message(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func finalMessage(in message: [String: Any]) -> String? {
        guard let params = message["params"] as? [String: Any],
              let turn = params["turn"] as? [String: Any],
              let items = turn["items"] as? [[String: Any]] else { return nil }
        return items.reversed().first { $0["type"] as? String == "agentMessage" }?["text"] as? String
    }

    private static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.codex/bin/codex"
        ].first(where: FileManager.default.isExecutableFile(atPath:))
            .map { URL(fileURLWithPath: $0) }
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = [
            "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin", existingPath
        ].filter { !$0.isEmpty }.joined(separator: ":")
        environment["RUST_LOG"] = "error"
        return environment
    }
}
