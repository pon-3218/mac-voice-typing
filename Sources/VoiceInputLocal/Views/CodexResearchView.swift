import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class CodexResearchController {
    enum Phase: Equatable { case idle, asking, answered, failed }

    var phase: Phase = .idle
    var question = ""
    var answer = ""
    var errorMessage: String?

    private let client = CodexResearchClient()
    private var task: Task<Void, Never>?

    func ask(_ rawQuestion: String) {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, phase != .asking else { return }
        task?.cancel()
        self.question = question
        answer = ""
        errorMessage = nil
        phase = .asking

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let finalAnswer = try await client.ask(question: question) { [weak self] partial in
                    DispatchQueue.main.async {
                        guard let self, self.phase == .asking else { return }
                        self.answer = partial
                    }
                }
                answer = finalAnswer
                phase = .answered
            } catch {
                errorMessage = error.localizedDescription
                phase = .failed
            }
        }
    }
}

struct CodexResearchView: View {
    var controller: CodexResearchController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Codexで調べる")
                    .font(.system(size: 24, weight: .semibold))
                Text(controller.question)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            Group {
                if controller.phase == .asking, controller.answer.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("調べています…").foregroundStyle(.secondary)
                    }
                } else if let error = controller.errorMessage {
                    ContentUnavailableView("回答を取得できませんでした", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if controller.answer.isEmpty {
                    ContentUnavailableView("質問はまだありません", systemImage: "waveform.and.magnifyingglass")
                } else {
                    ScrollView {
                        Text(controller.answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button("回答をコピー") {
                    TextInserter.copyToClipboard(controller.answer)
                }
                .disabled(controller.answer.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
    }
}

@MainActor
final class CodexResearchWindowController {
    private let controller: CodexResearchController
    private var window: NSWindow?

    init(controller: CodexResearchController) {
        self.controller = controller
    }

    func ask(_ question: String) {
        controller.ask(question)
        show()
    }

    func show() {
        let window = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexで調べる"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: CodexResearchView(controller: controller))
        self.window = window
        return window
    }
}
