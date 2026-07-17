import SwiftUI
import AppKit

/// 音声入力中に表示する小さなフローティングHUD。認識テキストをライブ表示する。
struct DictationHUDView: View {
    var controller: DictationController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: controller.phase == .transcribing ? "waveform.badge.magnifyingglass" : "mic.fill")
                .font(.system(size: 18))
                .foregroundStyle(controller.phase == .transcribing ? .orange : .red)
                .symbolEffect(.pulse, isActive: controller.phase == .listening)

            VStack(alignment: .leading, spacing: 3) {
                Text(controller.phase == .transcribing ? "変換中…" : "聞き取り中…")
                    .font(.headline)
                if controller.partialText.isEmpty {
                    Text(controller.phase == .listening ? "話してください。キーを離すと入力します" : "")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    // 末尾（最新）を常に表示。古い行は上へスクロールして消える。
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(controller.partialText)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("tail")
                        }
                        .frame(maxHeight: 60)
                        .onChange(of: controller.partialText) { _, _ in
                            proxy.scrollTo("tail", anchor: .bottom)
                        }
                        .onAppear { proxy.scrollTo("tail", anchor: .bottom) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 380, height: 110, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
    }
}

/// HUD を表示する非アクティブなフローティングパネルの管理。
@MainActor
final class DictationHUDController {
    private var panel: NSPanel?

    func show(_ controller: DictationController) {
        let panel = ensurePanel(controller)
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel(_ controller: DictationController) -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: DictationHUDView(controller: controller))
        panel = p
        return p
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
