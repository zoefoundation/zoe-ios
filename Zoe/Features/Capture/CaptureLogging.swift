import OSLog

// Declared in a separate file to prevent Swift 6 @MainActor isolation inference,
// which applies to all private top-level declarations in files containing @MainActor types.
extension Logger {
    static let capture = Logger(subsystem: "com.zoe", category: "CaptureViewModel")
}
