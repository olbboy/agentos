import SwiftUI
import AppKit
import AgeOSCore

/// Nội dung của `MenuBarExtra`.
///
/// RÀNG BUỘC quan trọng: đây là **menu của hệ thống**, không phải view thường.
/// macOS chỉ nhận một tập control hạn chế — `SectionCard`, `StatTile`, `RatioMeter`
/// KHÔNG render được ở đây. Nên phase design system với màn này là "nói đúng thông
/// tin bằng menu item", không phải "áp component".
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let managed = model.lock.skills.count
        let summary = model.attentionSummary

        Text("AgeOS — \(managed) skills managed")

        // Cùng nguồn đếm với Overview và Diagnostics, nên ba bề mặt không thể
        // báo ba con số khác nhau.
        if model.hasRunDiagnostics {
            let total = summary.errors + summary.warnings + summary.info
            if total == 0 {
                Text("No problems found")
            } else {
                Text("\(summary.errors) errors · \(summary.warnings) warnings · \(summary.info) info")
            }
        }

        if let sync = model.lastSyncAt {
            Text("Last sync: \(sync.formatted(date: .omitted, time: .shortened))")
        }

        Divider()

        // Trước đây đóng cửa sổ chính là hết đường quay lại, chỉ còn cách thoát app.
        //
        // Không dùng `openWindow(id:)`: muốn vậy thì WindowGroup phải có id, mà đo
        // được là đặt id khiến app khởi động không mở cửa sổ nào. Thay vào đó gọi
        // đúng đường mà macOS chạy khi người dùng bấm icon Dock — SwiftUI tự dựng
        // lại cửa sổ của WindowGroup.
        Button("Open AgeOS") {
            NSApp.activate(ignoringOtherApps: true)
            // Loại cửa sổ Settings ra: nó cũng canBecomeMain, nên nếu người dùng
            // đóng cửa sổ chính rồi mở Settings, đường cũ sẽ chỉ đưa Settings lên
            // trước và cửa sổ chính không bao giờ quay lại.
            if let existing = NSApp.windows.first(where: {
                $0.canBecomeMain && $0.identifier?.rawValue != "com_apple_SwiftUI_Settings_window"
            }) {
                existing.makeKeyAndOrderFront(nil)
            } else {
                _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp,
                                                                   hasVisibleWindows: false)
            }
        }

        Divider()

        Button("Sync every source") {
            Task { await model.syncAll() }
        }
        Button("Run doctor") {
            Task { await model.runDoctor(fix: false) }
        }

        Divider()

        Button("Quit AgeOS") {
            NSApplication.shared.terminate(nil)
        }
    }
}
