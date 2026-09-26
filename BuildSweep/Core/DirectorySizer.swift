import Foundation

actor DirectorySizer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func allocatedSize(of url: URL) throws -> Int64 {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
            .isSymbolicLinkKey, .isDirectoryKey
        ]
        let rootValues = try? url.resourceValues(forKeys: keys)
        if rootValues?.isRegularFile == true {
            return Int64(rootValues?.totalFileAllocatedSize ?? rootValues?.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var visited = 0
        for case let fileURL as URL in enumerator {
            visited += 1
            if visited.isMultiple(of: 256) { try Task.checkCancellation() }
            let values = try? fileURL.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    func inspectImmediateChildren(of url: URL, limit: Int = 50) async throws -> StorageChildrenInspection {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        guard values.isDirectory == true else {
            return StorageChildrenInspection(children: [], totalCount: 0)
        }
        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: []
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let candidates = Array(urls.prefix(max(0, limit)))
        var children: [StorageChildSummary] = []
        children.reserveCapacity(candidates.count)
        for child in candidates {
            try Task.checkCancellation()
            let childValues = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
            let isSymlink = childValues?.isSymbolicLink == true
            let size = isSymlink ? nil : try? await allocatedSize(of: child)
            children.append(StorageChildSummary(
                url: child,
                isDirectory: childValues?.isDirectory == true,
                size: size,
                modifiedAt: childValues?.contentModificationDate
            ))
        }
        return StorageChildrenInspection(children: children, totalCount: urls.count)
    }
}
