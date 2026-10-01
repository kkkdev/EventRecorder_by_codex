import OSLog

enum CaptureLog {
    static let subsystem = "io.github.eventrecorder.capture"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let stream = Logger(subsystem: subsystem, category: "stream")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let teams = Logger(subsystem: subsystem, category: "teams-automation")
}
