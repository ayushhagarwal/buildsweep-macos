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
}
