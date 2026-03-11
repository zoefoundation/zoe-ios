import Foundation

// MARK: - RegistrationLogEntry

struct RegistrationLogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let stage: Stage
    let message: String
    let level: Level

    init(stage: Stage, message: String, level: Level = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.stage = stage
        self.message = message
        self.level = level
    }

    enum Stage: String, Sendable, Equatable {
        case INIT       = "INIT    "
        case STATE      = "STATE   "
        case KEY        = "KEY     "
        case REVOC      = "REVOC   "
        case CHALLENGE  = "CHALLENGE"
        case ATTEST     = "ATTEST  "
        case REGISTER   = "REGISTER"
        case RETRY      = "RETRY   "
        case COMPLETE   = "COMPLETE"
    }

    enum Level: Sendable, Equatable {
        case info, success, warning, error

        var icon: String {
            switch self {
            case .info:    return "🔄"
            case .success: return "✅"
            case .warning: return "⚠️"
            case .error:   return "❌"
            }
        }
    }

    /// Human-readable single line, suitable for os.Logger and debug UI.
    var formatted: String {
        "[\(stage.rawValue)] \(level.icon) \(message)"
    }
}
