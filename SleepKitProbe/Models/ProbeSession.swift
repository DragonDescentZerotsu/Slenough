import Foundation

struct ProbeSession: Codable, Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var note: String?

    init(id: UUID = UUID(), startedAt: Date = Date(), endedAt: Date? = nil, note: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }
}
