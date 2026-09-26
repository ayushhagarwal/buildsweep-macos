import Foundation

struct MCPAgentItemRegistry {
    private(set) var generationID: UUID?
    private var itemIDsByOpaqueID: [String: String] = [:]

    mutating func beginGeneration(_ generation: UUID) {
        guard generationID != generation else { return }
        generationID = generation
        itemIDsByOpaqueID.removeAll(keepingCapacity: true)
    }

    mutating func opaqueID(for itemID: String, generation: UUID) -> String {
        beginGeneration(generation)
        if let existing = itemIDsByOpaqueID.first(where: { $0.value == itemID })?.key { return existing }
        let opaqueID = UUID().uuidString
        itemIDsByOpaqueID[opaqueID] = itemID
        return opaqueID
    }

    func itemID(for opaqueID: String, generation: UUID) -> String? {
        guard generationID == generation else { return nil }
        return itemIDsByOpaqueID[opaqueID]
    }

    static func boundedPageSize(_ requested: Int?) -> Int {
        min(max(requested ?? 25, 1), 50)
    }

    static let maximumCleanupItems = 50
    static let maximumInspectionChildren = 30
    static let maximumRequestBytes = 65_536
}
