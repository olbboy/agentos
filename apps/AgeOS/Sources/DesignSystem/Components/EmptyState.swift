import SwiftUI

/// Màn trống: icon + tiêu đề + giải thích, tuỳ chọn một hành động.
///
/// Vì sao không dùng `ContentUnavailableView` của SwiftUI: audit `.contrast` đo
/// được chữ của nó KHÔNG đạt trên nền của app — 9 lần fail trên 6 màn. Nó tự chọn
/// màu `.secondary` và không cho ghi đè, nên cách duy nhất kiểm soát được tỉ lệ là
/// tự dựng bằng token đã đo (`textPrimary` 17.43:1, `textSecondary` 6.54:1).
///
/// Đây cũng là bề mặt người dùng mới gặp ĐẦU TIÊN, nên nó là chỗ tệ nhất để chữ
/// khó đọc.
struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: (title: LocalizedStringKey, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(Color.ageTextSecondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.ageTitleL)
                .foregroundStyle(Color.ageTextPrimary)

            Text(message)
                .font(.ageBody)
                .foregroundStyle(Color.ageTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ageSurface)
    }
}

#Preview("States") {
    VStack(spacing: 0) {
        EmptyState(icon: "books.vertical",
                   title: "Library is empty",
                   message: "Add a GitHub source or a local folder to get started.")
        Divider().overlay(Color.ageBorderSubtle)
        EmptyState(icon: "gauge.with.needle",
                   title: "Not measured yet",
                   message: "Press Measure budget to run it.",
                   action: ("Measure budget", {}))
    }
    .frame(width: 560, height: 620)
}

#Preview("Dark") {
    EmptyState(icon: "server.rack",
               title: "No MCP servers yet",
               message: "Add one from the CLI: ageos mcp add <registry-name|file.mcpb>")
        .frame(width: 560, height: 320)
        .preferredColorScheme(.dark)
}
