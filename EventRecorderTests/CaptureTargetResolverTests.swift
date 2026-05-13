import XCTest
@testable import EventRecorderCore

final class CaptureTargetResolverTests: XCTestCase {
    func testResolveUsesExactWindowIDMatchFirst() throws {
        let selected = makeTarget(windowID: 10, processID: 100, title: "Event Browser")
        let latest = [
            makeTarget(windowID: 10, processID: 100, title: "Event Browser"),
            makeTarget(windowID: 11, processID: 100, title: "Event Browser")
        ]

        let resolved = try CaptureTargetResolver.resolve(selected: selected, latestTargets: latest)
        XCTAssertEqual(resolved.windowID, 10)
    }

    func testResolveFallsBackToSameProcessAndTitle() throws {
        let selected = makeTarget(windowID: 10, processID: 100, title: "Event Browser")
        let latest = [
            makeTarget(windowID: 20, processID: 100, title: "Event Browser"),
            makeTarget(windowID: 30, processID: 200, title: "Other")
        ]

        let resolved = try CaptureTargetResolver.resolve(selected: selected, latestTargets: latest)
        XCTAssertEqual(resolved.windowID, 20)
    }

    func testResolveFallsBackToSingleSameProcessTarget() throws {
        let selected = makeTarget(windowID: 10, processID: 100, title: "Old")
        let latest = [
            makeTarget(windowID: 50, processID: 100, title: "New Title")
        ]

        let resolved = try CaptureTargetResolver.resolve(selected: selected, latestTargets: latest)
        XCTAssertEqual(resolved.windowID, 50)
    }

    func testResolveFailsWhenAmbiguous() {
        let selected = makeTarget(windowID: 10, processID: 100, title: "Old")
        let latest = [
            makeTarget(windowID: 20, processID: 100, title: "A"),
            makeTarget(windowID: 30, processID: 100, title: "B")
        ]

        XCTAssertThrowsError(try CaptureTargetResolver.resolve(selected: selected, latestTargets: latest)) { error in
            XCTAssertEqual(error as? CaptureTargetResolverError, .unavailableAfterFullscreen)
        }
    }

    private func makeTarget(windowID: UInt32, processID: Int32, title: String) -> CaptureTarget {
        CaptureTarget(
            windowID: windowID,
            displayID: 1,
            windowTitle: title,
            application: .init(
                bundleIdentifier: "com.example.app",
                processID: processID,
                applicationName: "Example"
            )
        )
    }
}
