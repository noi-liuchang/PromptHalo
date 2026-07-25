import Foundation

struct PromptItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var slot: Int?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        slot: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.slot = slot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

}
