import Foundation

enum UIBootHelper {
    static func resetPersistentState() {
        let fileManager = FileManager.default

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        let eventStoreURL = appSupport
            .appendingPathComponent("EventRecorder", isDirectory: true)
            .appendingPathComponent("events.json")

        try? fileManager.removeItem(at: eventStoreURL)

        let savedStateURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State", isDirectory: true)
            .appendingPathComponent("io.github.eventrecorder.EventRecorder.savedState", isDirectory: true)

        try? fileManager.removeItem(at: savedStateURL)
    }
}
