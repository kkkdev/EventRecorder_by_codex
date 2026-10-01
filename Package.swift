// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EventRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EventRecorderCore", targets: ["EventRecorderCore"])
    ],
    targets: [
        .target(
            name: "EventRecorderCore",
            path: "EventRecorder",
            exclude: [
                "App",
                "Application/CaptureSessionController.swift",
                "Application/EventManager.swift",
                "Application/TeamsAutomationController.swift",
                "EventRecorder.entitlements",
                "Infrastructure/AudioFileWriter.swift",
                "Infrastructure/AccessibilityPermissionManager.swift",
                "Infrastructure/BrowserWindowController.swift",
                "Infrastructure/CaptureLogger.swift",
                "Infrastructure/JpegFrameWriter.swift",
                "Infrastructure/PermissionManager.swift",
                "Infrastructure/ReminderService.swift",
                "Infrastructure/ScreenCaptureService.swift",
                "Infrastructure/TeamsAccessibilitySnapshotProvider.swift",
                "Infrastructure/TeamsAutomationNotifier.swift",
                "Info.plist"
            ],
            sources: [
                "Domain",
                "Application/IntervalSnapshotScheduler.swift",
                "Infrastructure/FFmpegCommandBuilder.swift",
                "Infrastructure/FFmpegTranscoder.swift",
                "Infrastructure/EventStore.swift"
            ]
        ),
        .testTarget(
            name: "EventRecorderTests",
            dependencies: ["EventRecorderCore"],
            path: "EventRecorderTests"
        )
    ]
)
