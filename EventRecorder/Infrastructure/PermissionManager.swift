import AppKit
import ApplicationServices
import Foundation

public protocol PermissionManaging {
    func preflightScreenCaptureAccess() -> Bool
    func requestScreenCaptureAccess() -> Bool
    func openScreenRecordingSettings()
}

public final class PermissionManager: PermissionManaging {
    public init() {}

    public func preflightScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
