import Foundation
import XCTest
@testable import EventRecorderCore

final class CaptureSettingsTests: XCTestCase {
    func testValidatedSucceedsWithBoundaryValues() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let settings = CaptureSettings(
            target: makeTarget(windowID: 1, displayID: 1),
            intervalSeconds: 120.0,
            jpegQuality: 1.0,
            outputDirectory: outputDirectory,
            audioBitrateKbps: 320
        )

        XCTAssertNoThrow(try settings.validated())
    }

    func testValidatedFailsWhenIntervalIsOutOfRange() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let settings = CaptureSettings(
            target: makeTarget(windowID: 1, displayID: 1),
            intervalSeconds: 0.4,
            jpegQuality: 0.9,
            outputDirectory: outputDirectory,
            audioBitrateKbps: 128
        )

        XCTAssertThrowsError(try settings.validated()) { error in
            XCTAssertEqual(error as? CaptureSettingsValidationError, .invalidInterval(0.4))
        }
    }

    func testValidatedFailsWhenIntervalExceedsMaximum() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let settings = CaptureSettings(
            target: makeTarget(windowID: 1, displayID: 1),
            intervalSeconds: 120.1,
            jpegQuality: 0.9,
            outputDirectory: outputDirectory,
            audioBitrateKbps: 128
        )

        XCTAssertThrowsError(try settings.validated()) { error in
            XCTAssertEqual(error as? CaptureSettingsValidationError, .invalidInterval(120.1))
        }
    }

    func testValidatedFailsWhenOutputDirectoryDoesNotExist() {
        let outputDirectory = URL(fileURLWithPath: "/tmp/event-recorder/nonexistent/path", isDirectory: true)
        let settings = CaptureSettings(
            target: makeTarget(windowID: 1, displayID: 1),
            intervalSeconds: 1.0,
            jpegQuality: 0.9,
            outputDirectory: outputDirectory,
            audioBitrateKbps: 128
        )

        XCTAssertThrowsError(try settings.validated()) { error in
            guard case .invalidOutputDirectory = error as? CaptureSettingsValidationError else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testValidatedFailsWhenTargetIsInvalid() throws {
        let outputDirectory = try makeTemporaryDirectory()
        let settings = CaptureSettings(
            target: makeTarget(windowID: 0, displayID: 0),
            intervalSeconds: 1.0,
            jpegQuality: 0.9,
            outputDirectory: outputDirectory,
            audioBitrateKbps: 128
        )

        XCTAssertThrowsError(try settings.validated()) { error in
            XCTAssertEqual(error as? CaptureSettingsValidationError, .invalidTarget)
        }
    }

    func testDecodesLegacySettingsWithManualDisplayDefaults() throws {
        let legacy = LegacyCaptureSettings(
            target: makeTarget(windowID: 1, displayID: 1),
            intervalSeconds: 1,
            jpegQuality: 0.9,
            outputDirectory: try makeTemporaryDirectory(),
            audioBitrateKbps: 128
        )

        let decoded = try JSONDecoder().decode(
            CaptureSettings.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.contentMode, .display)
        XCTAssertEqual(decoded.trigger, .manual)
        XCTAssertNil(decoded.segmentGroupID)
        XCTAssertNil(decoded.presenceEvidenceVersion)
    }

    private func makeTarget(windowID: UInt32, displayID: UInt32) -> CaptureTarget {
        CaptureTarget(
            windowID: windowID,
            displayID: displayID,
            windowTitle: "sample",
            application: .init(
                bundleIdentifier: "com.example.sample",
                processID: 100,
                applicationName: "SampleApp"
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let path = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
}

private struct LegacyCaptureSettings: Codable {
    let target: CaptureTarget
    let intervalSeconds: Double
    let jpegQuality: Double
    let outputDirectory: URL
    let audioBitrateKbps: Int
}
