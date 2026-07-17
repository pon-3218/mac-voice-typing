import SwiftUI

struct DictationHistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("音声入力履歴").font(.system(size: 28, weight: .semibold))
                Text("\(currentKeyName)を押している間に話し、離すと現在の入力欄へ挿入します")
                    .foregroundStyle(.secondary)
            }
            .padding(28)

            List {
                ForEach(model.dictationRecords) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.text).textSelection(.enabled)
                        HStack {
                            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(String(format: "%.1f秒", record.duration))
                            Spacer()
                            Button("コピー") { TextInserter.copyToClipboard(record.text) }.buttonStyle(.link)
                            Button(role: .destructive) { model.deleteDictation(id: record.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .overlay {
                if model.dictationRecords.isEmpty {
                    ContentUnavailableView("履歴はまだありません", systemImage: "text.cursor")
                }
            }
        }
    }

    private var currentKeyName: String {
        DictationKey(rawValue: model.settings.dictationKeyCode)?.displayName ?? "右 Option"
    }
}
