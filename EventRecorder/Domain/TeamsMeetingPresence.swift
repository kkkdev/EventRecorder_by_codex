import Foundation

public struct TeamsAccessibilityElementSnapshot: Equatable {
    public let role: String
    public let subrole: String?
    public let identifier: String?
    public let title: String?
    public let label: String?
    public let elementDescription: String?

    public init(
        role: String,
        subrole: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        label: String? = nil,
        elementDescription: String? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.label = label
        self.elementDescription = elementDescription
    }

    fileprivate var normalizedSearchText: String {
        [role, subrole, identifier, title, label, elementDescription]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

public struct TeamsAccessibilityWindowSnapshot: Equatable {
    public let windowID: UInt32
    public let processID: Int32
    public let bundleIdentifier: String
    public let elements: [TeamsAccessibilityElementSnapshot]

    public init(
        windowID: UInt32,
        processID: Int32,
        bundleIdentifier: String,
        elements: [TeamsAccessibilityElementSnapshot]
    ) {
        self.windowID = windowID
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.elements = elements
    }
}

public struct TeamsMeetingPresenceEvidence: Equatable {
    public let windowID: UInt32
    public let processID: Int32
    public let hasLeaveControl: Bool
    public let supportingControlKinds: Set<TeamsMeetingControlKind>

    public init(
        windowID: UInt32,
        processID: Int32,
        hasLeaveControl: Bool,
        supportingControlKinds: Set<TeamsMeetingControlKind>
    ) {
        self.windowID = windowID
        self.processID = processID
        self.hasLeaveControl = hasLeaveControl
        self.supportingControlKinds = supportingControlKinds
    }

    public var isConfirmedCandidate: Bool {
        hasLeaveControl && supportingControlKinds.count >= 2
    }
}

public enum TeamsMeetingControlKind: String, CaseIterable, Hashable {
    case microphone
    case camera
    case participants
    case sharing
    case chat
    case reactions
    case more
}

public enum TeamsMeetingPresenceDetector {
    public static let teamsBundleIdentifier = "com.microsoft.teams2"

    public static func evidence(
        for snapshot: TeamsAccessibilityWindowSnapshot
    ) -> TeamsMeetingPresenceEvidence {
        guard snapshot.bundleIdentifier == teamsBundleIdentifier else {
            return TeamsMeetingPresenceEvidence(
                windowID: snapshot.windowID,
                processID: snapshot.processID,
                hasLeaveControl: false,
                supportingControlKinds: []
            )
        }

        let searchTexts = snapshot.elements.map(\.normalizedSearchText)
        let hasLeaveControl = searchTexts.contains { text in
            leaveControlTokens.contains { text.contains($0) }
        }

        var supportingKinds: Set<TeamsMeetingControlKind> = []
        for (kind, tokens) in supportingControlTokens {
            if searchTexts.contains(where: { text in tokens.contains(where: text.contains) }) {
                supportingKinds.insert(kind)
            }
        }

        return TeamsMeetingPresenceEvidence(
            windowID: snapshot.windowID,
            processID: snapshot.processID,
            hasLeaveControl: hasLeaveControl,
            supportingControlKinds: supportingKinds
        )
    }

    public static func uniqueCandidate(
        in snapshots: [TeamsAccessibilityWindowSnapshot]
    ) -> TeamsMeetingPresenceEvidence? {
        let candidates = snapshots
            .map(evidence(for:))
            .filter(\.isConfirmedCandidate)
        guard candidates.count == 1 else {
            return nil
        }
        return candidates[0]
    }

    private static let leaveControlTokens = [
        "hang up",
        "hangup",
        "leave call",
        "leave meeting",
        "leave",
        "end call",
        "endcall",
        "通話を終了",
        "通話から退出",
        "会議から退出",
        "会議を退出",
        "退出"
    ]

    private static let supportingControlTokens: [TeamsMeetingControlKind: [String]] = [
        .microphone: ["microphone", "mute", "unmute", "マイク", "ミュート"],
        .camera: ["camera", "video", "カメラ", "ビデオ"],
        .participants: ["participant", "people", "参加者"],
        .sharing: ["share", "present", "共有", "発表"],
        .chat: ["meeting chat", "チャット"],
        .reactions: ["reaction", "raise hand", "リアクション", "挙手"],
        .more: ["more actions", "その他の操作", "その他"]
    ]
}

public struct TeamsMeetingPresenceStabilizer: Equatable {
    public let requiredConsecutiveObservations: Int

    private var lastWindowID: UInt32?
    private var consecutiveObservationCount = 0

    public init(requiredConsecutiveObservations: Int = 2) {
        self.requiredConsecutiveObservations = max(1, requiredConsecutiveObservations)
    }

    public mutating func observe(
        _ evidence: TeamsMeetingPresenceEvidence?
    ) -> TeamsMeetingPresenceEvidence? {
        guard let evidence, evidence.isConfirmedCandidate else {
            reset()
            return nil
        }

        if lastWindowID == evidence.windowID {
            consecutiveObservationCount += 1
        } else {
            lastWindowID = evidence.windowID
            consecutiveObservationCount = 1
        }

        guard consecutiveObservationCount >= requiredConsecutiveObservations else {
            return nil
        }
        return evidence
    }

    public mutating func reset() {
        lastWindowID = nil
        consecutiveObservationCount = 0
    }
}
