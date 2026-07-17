import Foundation

enum AppError: LocalizedError {
    case permissionDenied(String)
    case noDisplayAvailable
    case captureSetupFailed(String)
    case diskSpaceLow
    case transcriptionUnavailable(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let target): return "\(target)の権限が許可されていません。"
        case .noDisplayAvailable: return "録音対象のディスプレイを取得できませんでした。"
        case .captureSetupFailed(let detail): return "録音の開始に失敗しました: \(detail)"
        case .diskSpaceLow: return "ディスクの空き容量が不足しています。"
        case .transcriptionUnavailable(let detail): return "音声認識を実行できません: \(detail)"
        case .storageFailed(let detail): return "保存に失敗しました: \(detail)"
        }
    }
}
