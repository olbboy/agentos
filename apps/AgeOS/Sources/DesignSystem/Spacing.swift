import CoreGraphics

/// Thang spacing 4pt. Mọi khoảng cách trong app lấy từ đây, không viết số rời.
///
/// Vì sao dùng `enum` không có case thay vì `struct`: enum rỗng không thể khởi tạo
/// instance, nên nó là namespace thuần — không ai lỡ viết `Space()` được.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Bán kính bo góc. Ba mức đủ cho toàn app: control nhỏ, card, container lớn.
enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
}

/// Độ dày đường kẻ. Tách riêng khỏi `Space` vì đây là nét vẽ, không phải khoảng cách.
enum Stroke {
    static let hairline: CGFloat = 1
    static let emphasis: CGFloat = 2
}
