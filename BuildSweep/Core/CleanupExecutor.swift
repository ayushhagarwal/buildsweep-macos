import Foundation

protocol TrashRouting: Sendable {
    func moveToTrash(_ url: URL) throws -> URL?
}

struct SystemTrashRouter: TrashRouting {
    func moveToTrash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL.map { $0 as URL }
    }
}

actor DefaultCleanupExecutor: CleanupExecuting {
    private let policy: CleanupPathPolicy
    private let trashRouter: TrashRouting
    private let simulatorController: SimulatorControlling

    init(
        policy: CleanupPathPolicy = CleanupPathPolicy(),
        trashRouter: TrashRouting = SystemTrashRouter(),
        simulatorController: SimulatorControlling = SimctlController()
    ) {
        self.policy = policy
        self.trashRouter = trashRouter
        self.simulatorController = simulatorController
    }

    func execute(_ plan: CleanupPlan) async -> CleanupSessionResult {
        let started = Date()
        var results: [CleanupItemResult] = []

        for planned in plan.items {
            if Task.isCancelled { break }
            do {
                let successMessage: String
                var trashedURL: URL?
                switch planned.item.action {
                case .trash:
                    let didAccess = planned.authorizedRoot.startAccessingSecurityScopedResource()
                    defer { if didAccess { planned.authorizedRoot.stopAccessingSecurityScopedResource() } }
                    let url = try policy.validate(planned.item, inside: planned.authorizedRoot)
                    guard url == planned.canonicalURLAtPlanning else {
                        throw CleanupPolicyError.ruleMismatch(planned.item.displayName)
                    }
                    guard let expectedIdentity = planned.targetIdentity else {
                        throw CleanupPolicyError.identityChanged(planned.item.displayName)
                    }
                    let currentIdentity = try policy.targetIdentity(of: url)
                    guard currentIdentity == expectedIdentity else {
                        throw CleanupPolicyError.identityChanged(planned.item.displayName)
                    }
                    trashedURL = try trashRouter.moveToTrash(url)
                    successMessage = "Moved to Trash"
                case .permanentSimulatorDeletion:
                    try await simulatorController.deleteDevice(id: planned.item.id)
                    successMessage = "Deleted permanently"
                case .inspectionOnly:
                    throw CleanupPolicyError.inspectionOnly(planned.item.displayName)
                }
                results.append(CleanupItemResult(itemID: planned.item.id, displayName: planned.item.displayName, size: planned.item.size, succeeded: true, message: successMessage, trashedURL: trashedURL))
            } catch {
                results.append(CleanupItemResult(itemID: planned.item.id, displayName: planned.item.displayName, size: planned.item.size, succeeded: false, message: error.localizedDescription, trashedURL: nil))
            }
        }

        return CleanupSessionResult(id: UUID(), startedAt: started, completedAt: .now, results: results)
    }
}
