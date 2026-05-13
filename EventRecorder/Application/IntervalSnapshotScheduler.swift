import Foundation

public final class IntervalSnapshotScheduler {
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?

    public init(queue: DispatchQueue = DispatchQueue(label: "event-recorder.snapshot.scheduler")) {
        self.queue = queue
    }

    public func start(
        intervalSeconds: TimeInterval,
        leewaySeconds: TimeInterval = 0.05,
        handler: @escaping () -> Void
    ) throws {
        guard intervalSeconds > 0 else {
            throw IntervalSnapshotSchedulerError.invalidInterval(intervalSeconds)
        }
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + intervalSeconds,
            repeating: intervalSeconds,
            leeway: .milliseconds(Int(leewaySeconds * 1000))
        )
        timer.setEventHandler(handler: handler)
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    deinit {
        stop()
    }
}

public enum IntervalSnapshotSchedulerError: LocalizedError {
    case invalidInterval(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .invalidInterval(let value):
            return "スクショ間隔が0以下です: \(value)"
        }
    }
}
