import Foundation

public struct CaptureTarget: Codable, Equatable, Hashable, Identifiable {
    public struct ApplicationInfo: Codable, Equatable, Hashable {
        public let bundleIdentifier: String
        public let processID: Int32
        public let applicationName: String

        public init(bundleIdentifier: String, processID: Int32, applicationName: String) {
            self.bundleIdentifier = bundleIdentifier
            self.processID = processID
            self.applicationName = applicationName
        }
    }

    public let windowID: UInt32
    public let displayID: UInt32
    public let windowTitle: String
    public let application: ApplicationInfo

    public var id: UInt32 { windowID }

    public init(
        windowID: UInt32,
        displayID: UInt32,
        windowTitle: String,
        application: ApplicationInfo
    ) {
        self.windowID = windowID
        self.displayID = displayID
        self.windowTitle = windowTitle
        self.application = application
    }

    public var summary: String {
        let normalizedTitle = windowTitle.isEmpty ? "無題ウィンドウ" : windowTitle
        return "\(application.applicationName) / \(normalizedTitle)"
    }
}
