import SwiftUI

/// Type ramp của AgeOS. Nhận diện thương hiệu đến từ đây và từ `Space`,
/// không đến từ độ bão hoà màu — xem `docs/design-guidelines.md`.
extension Font {
    /// Số liệu lớn nhất trên Overview. Chỉ dùng một lần mỗi màn.
    static let ageDisplayL = Font.system(size: 28, weight: .semibold)
    static let ageTitleL   = Font.system(size: 20, weight: .semibold)
    static let ageHeadline = Font.system(size: 15, weight: .medium)
    static let ageBody     = Font.system(size: 13)
    static let ageCallout  = Font.system(size: 12)
    static let ageCaption  = Font.system(size: 11)

    /// Cho mọi con số thay đổi theo thời gian (token count, tỉ lệ, số đếm).
    /// `monospacedDigit` giữ mọi chữ số cùng bề rộng, nên cột số không nhảy
    /// ngang khi giá trị đổi — lỗi rất dễ thấy ở meter cập nhật realtime.
    static let ageNumeric  = Font.system(size: 15, weight: .medium).monospacedDigit()

    /// Bản nhỏ của `ageNumeric`, cho số phụ trong một dòng danh sách.
    static let ageNumericS = Font.system(size: 12, weight: .regular).monospacedDigit()
}
