import Foundation

public struct EventEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String?
    public var url: URL
    public var startsAt: Date
    public var endsAt: Date
    public var notificationID: String

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        url: URL,
        startsAt: Date,
        endsAt: Date,
        notificationID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.notificationID = notificationID ?? "event-reminder-\(id.uuidString)"
    }

    public var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }

    public func validated() throws -> EventEntry {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw EventEntryValidationError.invalidURLScheme(url.absoluteString)
        }
        guard startsAt < endsAt else {
            throw EventEntryValidationError.invalidDateRange(startsAt: startsAt, endsAt: endsAt)
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return EventEntry(
            id: id,
            title: normalizedTitle?.isEmpty == true ? nil : normalizedTitle,
            url: url,
            startsAt: startsAt,
            endsAt: endsAt,
            notificationID: notificationID
        )
    }
}

public enum EventEntryValidationError: LocalizedError {
    case invalidURLScheme(String)
    case invalidDateRange(startsAt: Date, endsAt: Date)

    public var errorDescription: String? {
        switch self {
        case .invalidURLScheme(let value):
            return "URLはhttp/httpsのみ対応です: \(value)"
        case .invalidDateRange:
            return "開始日時は終了日時より前にしてください。"
        }
    }
}
