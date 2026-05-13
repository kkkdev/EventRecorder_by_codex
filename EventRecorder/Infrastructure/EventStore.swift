import Foundation

public protocol EventStoreProtocol {
    func load() throws -> [EventEntry]
    func save(events: [EventEntry]) throws
    func add(event: EventEntry) throws -> [EventEntry]
    func delete(id: UUID) throws -> [EventEntry]
}

public final class EventStore: EventStoreProtocol {
    public static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("EventRecorder", isDirectory: true)
            .appendingPathComponent("events.json")
    }

    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL = EventStore.defaultStorageURL(), fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> [EventEntry] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }
        let data = try Data(contentsOf: storageURL)
        let events = try decoder.decode([EventEntry].self, from: data)
        return events.sorted(by: { $0.startsAt < $1.startsAt })
    }

    public func save(events: [EventEntry]) throws {
        try createParentDirectoryIfNeeded()
        let sorted = events.sorted(by: { $0.startsAt < $1.startsAt })
        let data = try encoder.encode(sorted)
        try data.write(to: storageURL, options: .atomic)
    }

    public func add(event: EventEntry) throws -> [EventEntry] {
        let validated = try event.validated()
        var events = try load().filter { $0.id != validated.id }
        events.append(validated)
        try save(events: events)
        return events.sorted(by: { $0.startsAt < $1.startsAt })
    }

    public func delete(id: UUID) throws -> [EventEntry] {
        let events = try load().filter { $0.id != id }
        try save(events: events)
        return events
    }

    private func createParentDirectoryIfNeeded() throws {
        let directory = storageURL.deletingLastPathComponent()
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return
            }
            throw EventStoreError.invalidStorageDirectory(directory.path)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

public enum EventStoreError: LocalizedError {
    case invalidStorageDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .invalidStorageDirectory(let path):
            return "イベント保存先ディレクトリが不正です: \(path)"
        }
    }
}
