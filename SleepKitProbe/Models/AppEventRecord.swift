import Foundation

struct AppEventRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID?
    let createdAt: Date
    let name: String
    let detail: String?

    init(id: UUID = UUID(), sessionId: UUID?, createdAt: Date = Date(), name: String, detail: String?) {
        self.id = id
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.name = name
        self.detail = detail
    }
}
