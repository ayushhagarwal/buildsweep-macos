import Foundation

protocol TrashRouting: Sendable {
    func moveToTrash(_ url: URL) throws
}

struct SystemTrashRouter: TrashRouting {
    func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

actor DefaultCleanupExecutor: CleanupExecuting {
    private let policy: CleanupPathPolicy
    private let trashRouter: TrashRouting
    private let simulatorController: SimulatorControlling
    private let freeCleanupStore: FreeCleanupAccounting

    init(
        policy: CleanupPathPolicy = CleanupPathPolicy(),
        trashRouter: TrashRouting = SystemTrashRouter(),
        simulatorController: SimulatorControlling = SimctlController(),
        freeCleanupStore: FreeCleanupAccounting = KeychainFreeCleanupStore()
    ) {
        self.policy = policy
        self.trashRouter = trashRouter
        self.simulatorController = simulatorController
        self.freeCleanupStore = freeCleanupStore
    }

    func execute(_ plan: CleanupPlan) async -> CleanupSessionResult {
        let started = Date()
        var results: [CleanupItemResult] = []
        var freeMarkerRecorded = false

        for planned in plan.items {
            if Task.isCancelled { break }
            do {
                var successMessage: String
                switch planned.item.action {
                case .trash:
                    let didAccess = planned.authorizedRoot.startAccessingSecurityScopedResource()
                    defer { if didAccess { planned.authorizedRoot.stopAccessingSecurityScopedResource() } }
                    let url = try policy.validate(planned.item, inside: planned.authorizedRoot)
                    guard url == planned.canonicalURLAtPlanning else {
                        throw CleanupPolicyError.ruleMismatch(planned.item.displayName)
                    }
                    try trashRouter.moveToTrash(url)
                    successMessage = "Moved to Trash"
                case .permanentSimulatorDeletion:
                    try await simulatorController.deleteDevice(id: planned.item.id)
                    successMessage = "Deleted permanently"
                case .inspectionOnly:
                    throw CleanupPolicyError.inspectionOnly(planned.item.displayName)
                }

                if !freeMarkerRecorded {
                    do {
                        try await freeCleanupStore.recordUse()
                        freeMarkerRecorded = true
                    } catch {
                        successMessage += "; free-use marker needs attention: \(error.localizedDescription)"
                    }
                }
                results.append(CleanupItemResult(itemID: planned.item.id, displayName: planned.item.displayName, size: planned.item.size, succeeded: true, message: successMessage))
            } catch {
                results.append(CleanupItemResult(itemID: planned.item.id, displayName: planned.item.displayName, size: planned.item.size, succeeded: false, message: error.localizedDescription))
            }
        }

        return CleanupSessionResult(id: UUID(), startedAt: started, completedAt: .now, results: results)
    }
}
