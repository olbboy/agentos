import Foundation

/// A core error carrying its remedy — the CLI prints `message` plus `remedy` so the user can act.
public struct AgeOSError: Error, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable {
        case invalidSkill = "invalid_skill"
        case invalidSource = "invalid_source"
        case network = "network"
        case rateLimited = "rate_limited"
        case storeCorrupt = "store_corrupt"
        case lockfileCorrupt = "lockfile_corrupt"
        case configUnreadable = "config_unreadable"
        case conflict = "conflict"
        case notFound = "not_found"
        case unsupported = "unsupported"
        case processFailed = "process_failed"
    }

    public let code: Code
    public let message: String
    public let remedy: String?

    public init(_ code: Code, _ message: String, remedy: String? = nil) {
        self.code = code
        self.message = message
        self.remedy = remedy
    }

    public var description: String {
        remedy.map { "\(message)\n  → \($0)" } ?? message
    }
}
