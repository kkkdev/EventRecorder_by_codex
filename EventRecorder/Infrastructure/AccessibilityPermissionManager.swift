import AppKit
import ApplicationServices
import Foundation

public protocol AccessibilityPermissionManaging {
    func hasPermission() -> Bool
    @discardableResult func requestPermission() -> Bool
    func openAccessibilitySettings()
}

public final class AccessibilityPermissionManager: AccessibilityPermissionManaging {
    public init() {}

    public func hasPermission() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public func requestPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
