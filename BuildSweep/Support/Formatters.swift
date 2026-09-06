import Darwin
import Foundation

enum RealUserHome {
    /// Sandboxed `homeDirectoryForCurrentUser` is the container, not `~/Library/Developer`.
    static var directory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true).standardizedFileURL
        }
        let containerHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let path = containerHome.path
        if let range = path.range(of: "/Library/Containers/") {
            return URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true)
        }
        return containerHome
    }

    static var developerDirectory: URL {
        directory.appending(path: "Library/Developer", directoryHint: .isDirectory)
    }

    static var xcodeCacheDirectory: URL {
        directory.appending(path: "Library/Caches/com.apple.dt.Xcode", directoryHint: .isDirectory)
    }

    static var cursorSupportDirectory: URL {
        directory.appending(path: "Library/Application Support/Cursor", directoryHint: .isDirectory)
    }

    static var cursorHomeDirectory: URL {
        directory.appending(path: ".cursor", directoryHint: .isDirectory)
    }

    static var codexHomeDirectory: URL {
        directory.appending(path: ".codex", directoryHint: .isDirectory)
    }

    static var codexSystemCacheDirectory: URL {
        directory.appending(path: "Library/Caches/com.openai.codex", directoryHint: .isDirectory)
    }

    static var codexNamedCacheDirectory: URL {
        directory.appending(path: "Library/Caches/Codex", directoryHint: .isDirectory)
    }

    static var claudeHomeDirectory: URL {
        directory.appending(path: ".claude", directoryHint: .isDirectory)
    }

    static var claudeSystemCacheDirectory: URL {
        directory.appending(path: "Library/Caches/com.anthropic.claudefordesktop", directoryHint: .isDirectory)
    }

    static var claudeSupportDirectory: URL {
        directory.appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
    }
}

enum BuildSweepFormatters {
    static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteCount.string(fromByteCount: value)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return relativeDate.localizedString(for: date, relativeTo: .now)
    }
}

extension URL {
    var canonicalFileURL: URL {
        resolvingSymlinksInPath().standardizedFileURL
    }

    func isDescendant(of root: URL) -> Bool {
        let candidate = canonicalFileURL.pathComponents
        let parent = root.canonicalFileURL.pathComponents
        return candidate.count > parent.count && candidate.starts(with: parent)
    }
}

