import XCTest

final class EventRecorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        UIBootHelper.resetPersistentState()

        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10.0))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testAddEventAndOpenFullScreenDoesNotCrash() {
        addEvent(url: "https://example.com")

        let fullScreenButton = app.buttons["event.fullscreenButton"].firstMatch
        XCTAssertTrue(fullScreenButton.waitForExistence(timeout: 5.0), "全画面ボタンが表示されません")

        fullScreenButton.tap()
        sleep(2)

        XCTAssertEqual(app.state, .runningForeground, "全画面操作後にアプリが前面で動作している必要があります")
    }

    func testInvalidURLShowsValidationMessage() {
        let urlField = app.textFields["event.urlField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5.0), "URL入力欄が見つかりません")

        urlField.clearAndTypeText("ftp://example.com")

        let addButton = app.buttons["event.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5.0), "イベント追加ボタンが見つかりません")
        addButton.tap()

        let messageLabel = app.staticTexts["event.messageLabel"]
        XCTAssertTrue(messageLabel.waitForExistence(timeout: 5.0), "バリデーションメッセージが表示されません")
        XCTAssertTrue(messageLabel.label.contains("http/https"), "URLスキームのエラー文言を含む必要があります")
    }

    func testDeleteEventRemovesRow() {
        addEvent(url: "https://example.com/delete")

        let deleteButtons = app.buttons.matching(identifier: "event.deleteButton")
        let firstDeleteButton = deleteButtons.firstMatch
        XCTAssertTrue(firstDeleteButton.waitForExistence(timeout: 5.0), "削除ボタンが表示されません")

        firstDeleteButton.tap()

        let removedPredicate = NSPredicate(format: "count == 0")
        expectation(for: removedPredicate, evaluatedWith: deleteButtons)
        waitForExpectations(timeout: 5.0)
    }

    private func addEvent(url: String) {
        let urlField = app.textFields["event.urlField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5.0), "URL入力欄が見つかりません")
        urlField.clearAndTypeText(url)

        let addButton = app.buttons["event.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5.0), "イベント追加ボタンが見つかりません")
        addButton.tap()
    }
}

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        click()
        typeKey("a", modifierFlags: .command)
        typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        typeText(text)
    }
}
