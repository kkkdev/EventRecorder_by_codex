import Foundation

public enum CaptureState {
    case idle
    case preparing
    case capturing
    case stopping
    case completed(outputDirectory: URL)
    case failed(Error)

    public var isRunning: Bool {
        switch self {
        case .preparing, .capturing, .stopping:
            return true
        default:
            return false
        }
    }

    public var canStop: Bool {
        if case .capturing = self {
            return true
        }
        return false
    }

    public var statusText: String {
        switch self {
        case .idle:
            return "待機中"
        case .preparing:
            return "準備中"
        case .capturing:
            return "録画中"
        case .stopping:
            return "停止処理中"
        case .completed(let outputDirectory):
            return "完了: \(outputDirectory.path)"
        case .failed(let error):
            return "失敗: \(error.localizedDescription)"
        }
    }
}
