import Foundation
import ServiceManagement

/// ログイン時の自動起動（常時メニューバー常駐）を管理する。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // 失敗しても致命にしない（権限/署名状況により未対応のことがある）。
        }
    }
}
