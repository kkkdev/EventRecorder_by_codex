import Foundation
import XCTest
@testable import EventRecorderCore

final class AudioInputPreflightTests: XCTestCase {
    func testValidateFailsWhenFileDoesNotExist() {
        let tempURL = makeTemporaryFileURL()

        XCTAssertThrowsError(try AudioInputPreflight.validate(tempAudioURL: tempURL)) { error in
            guard case .fileMissing(let path) = error as? AudioInputPreflightError else {
                XCTFail("unexpected error: \(error)")
                return
            }
            XCTAssertEqual(path, tempURL.path)
        }
    }

    func testValidateFailsWhenFileIsEmpty() throws {
        let tempURL = makeTemporaryFileURL()
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())

        XCTAssertThrowsError(try AudioInputPreflight.validate(tempAudioURL: tempURL)) { error in
            guard case .fileEmpty(let path) = error as? AudioInputPreflightError else {
                XCTFail("unexpected error: \(error)")
                return
            }
            XCTAssertEqual(path, tempURL.path)
        }
    }

    func testValidateSucceedsWhenFileHasContent() throws {
        let tempURL = makeTemporaryFileURL()
        FileManager.default.createFile(atPath: tempURL.path, contents: Data([0x01, 0x02]))

        XCTAssertNoThrow(try AudioInputPreflight.validate(tempAudioURL: tempURL))
    }

    private func makeTemporaryFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("caf")
    }
}
