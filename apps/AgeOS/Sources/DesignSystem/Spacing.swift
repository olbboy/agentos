import CoreGraphics

/// The 4pt spacing scale. Every gap in the app comes from here, never a loose number.
///
/// Why a caseless `enum` rather than a `struct`: an empty enum cannot be
/// instantiated, so it is a pure namespace — nobody can accidentally write `Space()`.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii. Three steps cover the app: small controls, cards, large containers.
enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
}

/// Line weights. Kept apart from `Space` because these are strokes, not gaps.
enum Stroke {
    static let hairline: CGFloat = 1
    static let emphasis: CGFloat = 2
}
