import SwiftUI

/// Cầu nối từ tên ngữ nghĩa sang Asset Catalog.
///
/// Tên mô tả **vai trò** (`statusDanger`), không mô tả màu (`red`). Đổi hue về sau
/// chỉ phải sửa Asset Catalog, không phải rà lại call site.
///
/// Mỗi color set khai báo 4 biến thể (light / dark / light+HighContrast /
/// dark+HighContrast). macOS tự chọn biến thể đúng theo môi trường, nên view
/// không cần đọc `@Environment(\.colorScheme)` hay dò Increase Contrast.
///
/// Giá trị hex và contrast ratio đo được: `docs/design-guidelines.md`.
extension Color {
    /// Nền cửa sổ.
    static let ageSurface       = Color("surface")
    /// Nền của card/section nổi trên `ageSurface`.
    static let ageSurfaceRaised = Color("surfaceRaised")
    /// Đường kẻ phân cách. Thuần trang trí — không bao giờ mang trạng thái.
    static let ageBorderSubtle  = Color("borderSubtle")
    static let ageTextPrimary   = Color("textPrimary")
    static let ageTextSecondary = Color("textSecondary")

    /// Chỉ dùng ở diện tích nhỏ: trạng thái active, đường kẻ trái, eyebrow.
    /// Không làm nền lớn — xem quy tắc trong design-guidelines.
    static let ageAccentBrand   = Color("accentBrand")

    static let ageStatusSuccess = Color("statusSuccess")
    static let ageStatusWarning = Color("statusWarning")
    static let ageStatusDanger  = Color("statusDanger")
    static let ageStatusInfo    = Color("statusInfo")
}
