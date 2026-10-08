import Foundation

struct Prompt: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var body: String
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    /// When the prompt was starred; favorites are ordered by this.
    var favoritedAt: Date?
    /// Last use per app, keyed by bundle identifier.
    var lastUsedByApp: [String: Date]

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        createdAt: Date = .now,
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        favoritedAt: Date? = nil,
        lastUsedByApp: [String: Date] = [:]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.favoritedAt = favoritedAt
        self.lastUsedByApp = lastUsedByApp
    }

    /// The moment this prompt was last relevant: used, or else created.
    var recency: Date { lastUsedAt ?? createdAt }
    var isFavorite: Bool { favoritedAt != nil }
}

extension Prompt {
    /// Accepts files written before favorites and per-app usage existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount = try container.decode(Int.self, forKey: .useCount)
        favoritedAt = try container.decodeIfPresent(Date.self, forKey: .favoritedAt)
        lastUsedByApp = try container.decodeIfPresent([String: Date].self, forKey: .lastUsedByApp) ?? [:]
    }
}
