import Foundation

public enum CaptureTargetResolverError: LocalizedError, Equatable {
    case unavailableAfterFullscreen

    public var errorDescription: String? {
        switch self {
        case .unavailableAfterFullscreen:
            return "全画面化などで対象ウィンドウが変化したため開始できません。対象を再選択して再実行してください。"
        }
    }
}

public enum CaptureTargetResolver {
    public static func resolve(
        selected: CaptureTarget,
        latestTargets: [CaptureTarget]
    ) throws -> CaptureTarget {
        if let exact = latestTargets.first(where: { $0.windowID == selected.windowID }) {
            return exact
        }

        if let sameTitle = latestTargets.first(where: {
            $0.application.processID == selected.application.processID &&
            $0.windowTitle == selected.windowTitle
        }) {
            return sameTitle
        }

        let sameProcessTargets = latestTargets.filter {
            $0.application.processID == selected.application.processID
        }
        if sameProcessTargets.count == 1, let fallback = sameProcessTargets.first {
            return fallback
        }

        throw CaptureTargetResolverError.unavailableAfterFullscreen
    }
}
