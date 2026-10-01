import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct TeamsAccessibilitySnapshotBatch: Equatable {
    public let teamsIsRunning: Bool
    public let windows: [TeamsAccessibilityWindowSnapshot]

    public init(teamsIsRunning: Bool, windows: [TeamsAccessibilityWindowSnapshot]) {
        self.teamsIsRunning = teamsIsRunning
        self.windows = windows
    }
}

public protocol TeamsAccessibilitySnapshotProviding: AnyObject {
    func snapshot() async throws -> TeamsAccessibilitySnapshotBatch
}

public enum TeamsAccessibilitySnapshotError: Error {
    case permissionDenied
    case windowListUnavailable
}

public final class TeamsAccessibilitySnapshotProvider: TeamsAccessibilitySnapshotProviding {
    private let permissionManager: AccessibilityPermissionManaging
    private let queue = DispatchQueue(label: "event-recorder.teams.accessibility", qos: .userInitiated)

    public init(permissionManager: AccessibilityPermissionManaging = AccessibilityPermissionManager()) {
        self.permissionManager = permissionManager
    }

    public func snapshot() async throws -> TeamsAccessibilitySnapshotBatch {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.makeSnapshot())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeSnapshot() throws -> TeamsAccessibilitySnapshotBatch {
        guard permissionManager.hasPermission() else {
            throw TeamsAccessibilitySnapshotError.permissionDenied
        }

        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: TeamsMeetingPresenceDetector.teamsBundleIdentifier
        )
        guard !applications.isEmpty else {
            return TeamsAccessibilitySnapshotBatch(teamsIsRunning: false, windows: [])
        }

        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw TeamsAccessibilitySnapshotError.windowListUnavailable
        }

        let descriptors = windowInfo.compactMap(Self.makeWindowDescriptor)
        var snapshots: [TeamsAccessibilityWindowSnapshot] = []
        for application in applications {
            snapshots.append(contentsOf: makeSnapshots(
                processID: application.processIdentifier,
                descriptors: descriptors
            ))
        }

        return TeamsAccessibilitySnapshotBatch(teamsIsRunning: true, windows: snapshots)
    }

    private func makeSnapshots(
        processID: pid_t,
        descriptors: [WindowDescriptor]
    ) -> [TeamsAccessibilityWindowSnapshot] {
        let applicationElement = AXUIElementCreateApplication(processID)
        guard let windows = elementArrayAttribute(applicationElement, kAXWindowsAttribute) else {
            return []
        }

        let processWindows = descriptors.filter { $0.processID == processID }
        var usedWindowIDs: Set<UInt32> = []
        var snapshots: [TeamsAccessibilityWindowSnapshot] = []

        for window in windows {
            guard let frame = frame(of: window),
                  let descriptor = uniquelyMatchedDescriptor(
                      frame: frame,
                      candidates: processWindows.filter { !usedWindowIDs.contains($0.windowID) }
                  ) else {
                continue
            }
            usedWindowIDs.insert(descriptor.windowID)
            snapshots.append(
                TeamsAccessibilityWindowSnapshot(
                    windowID: descriptor.windowID,
                    processID: Int32(processID),
                    bundleIdentifier: TeamsMeetingPresenceDetector.teamsBundleIdentifier,
                    elements: accessibilityElements(in: window)
                )
            )
        }
        return snapshots
    }

    private func accessibilityElements(in root: AXUIElement) -> [TeamsAccessibilityElementSnapshot] {
        let maximumDepth = 12
        let maximumElementCount = 1_500
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        var result: [TeamsAccessibilityElementSnapshot] = []

        while index < queue.count, result.count < maximumElementCount {
            let (element, depth) = queue[index]
            index += 1

            result.append(
                TeamsAccessibilityElementSnapshot(
                    role: stringAttribute(element, kAXRoleAttribute) ?? "",
                    subrole: stringAttribute(element, kAXSubroleAttribute),
                    identifier: stringAttribute(element, kAXIdentifierAttribute),
                    title: stringAttribute(element, kAXTitleAttribute),
                    label: stringAttribute(element, kAXHelpAttribute),
                    elementDescription: stringAttribute(element, kAXDescriptionAttribute)
                )
            )

            guard depth < maximumDepth,
                  let children = elementArrayAttribute(element, kAXChildrenAttribute) else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    private func uniquelyMatchedDescriptor(
        frame: CGRect,
        candidates: [WindowDescriptor]
    ) -> WindowDescriptor? {
        let scored = candidates
            .map { descriptor in
                (descriptor, Self.frameDistance(frame, descriptor.frame))
            }
            .filter { $0.1 <= 24 }
            .sorted { $0.1 < $1.1 }

        guard let best = scored.first else {
            return nil
        }
        if scored.count > 1, abs(scored[1].1 - best.1) < 1 {
            return nil
        }
        return best.0
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func elementArrayAttribute(_ element: AXUIElement, _ name: String) -> [AXUIElement]? {
        attribute(element, name) as? [AXUIElement]
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func makeWindowDescriptor(_ info: [String: Any]) -> WindowDescriptor? {
        guard let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
              let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
            return nil
        }
        return WindowDescriptor(
            windowID: windowNumber.uint32Value,
            processID: ownerPID.int32Value,
            frame: frame
        )
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.size.width - rhs.size.width)
            + abs(lhs.size.height - rhs.size.height)
    }

    private struct WindowDescriptor {
        let windowID: UInt32
        let processID: Int32
        let frame: CGRect
    }
}
