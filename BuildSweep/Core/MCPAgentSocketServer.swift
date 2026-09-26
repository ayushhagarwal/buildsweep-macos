import Darwin
import Foundation
import Security

struct MCPBridgeRequest: Codable, Sendable {
    let id: UUID
    let operation: String
    let arguments: String
}

struct MCPBridgeResponse: Codable, Sendable {
    let id: UUID
    let result: String?
    let error: String?
}

enum MCPBridgeConfiguration {
    static let helperBundleIdentifier = "com.ayush.buildsweep.mcp"
    static let appGroupSuffix = "com.ayush.buildsweep"

    static var socketURL: URL? {
        guard let teamIdentifier = currentSigningTeamIdentifier() else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "\(teamIdentifier).\(appGroupSuffix)")?
            .appendingPathComponent("BuildSweepMCP.sock")
    }
}

private func currentSigningTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let information = information as? [String: Any] else { return nil }
    return information[kSecCodeInfoTeamIdentifier as String] as? String
}

final class MCPAgentSocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ayush.buildsweep.mcp-socket", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private var requestHandler: (@Sendable (MCPBridgeRequest) async -> MCPBridgeResponse)?

    func start(handler: @escaping @Sendable (MCPBridgeRequest) async -> MCPBridgeResponse) throws {
        try lock.withLock {
            guard listener == -1 else { return }
            guard let socketURL = MCPBridgeConfiguration.socketURL else {
                throw MCPAgentSocketError.appGroupUnavailable
            }
            let path = socketURL.path
            guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
                throw MCPAgentSocketError.socketPathTooLong
            }
            try removeStaleSocket(at: path)

            let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socketFD >= 0 else { throw MCPAgentSocketError.posix("socket") }
            var address = sockaddr_un()
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                let pathBytes = Array(path.utf8) + [0]
                bytes.copyBytes(from: pathBytes)
            }
            let bindResult = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                Darwin.close(socketFD)
                throw MCPAgentSocketError.posix("bind")
            }
            guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0,
                  Darwin.listen(socketFD, 4) == 0 else {
                Darwin.close(socketFD)
                unlink(path)
                throw MCPAgentSocketError.posix("listen")
            }

            listener = socketFD
            requestHandler = handler
            let readSource = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
            readSource.setEventHandler { [weak self] in self?.acceptClient() }
            readSource.setCancelHandler { Darwin.close(socketFD) }
            source = readSource
            readSource.resume()
        }
    }

    func stop() {
        lock.withLock {
            guard listener != -1 else { return }
            source?.cancel()
            source = nil
            listener = -1
            requestHandler = nil
            if let socketURL = MCPBridgeConfiguration.socketURL { unlink(socketURL.path) }
        }
    }

    private func acceptClient() {
        let serverFD = lock.withLock { listener }
        guard serverFD >= 0 else { return }
        let clientFD = Darwin.accept(serverFD, nil, nil)
        guard clientFD >= 0 else { return }
        var noSignal: Int32 = 1
        guard setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            Darwin.close(clientFD)
            return
        }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        _ = setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        queue.async { [weak self] in self?.serve(clientFD) }
    }

    private func serve(_ fd: Int32) {
        defer { Darwin.close(fd) }
        guard verifyHelperPeer(fd) else { return }
        guard let requestData = readLine(from: fd, maximumBytes: MCPAgentItemRegistry.maximumRequestBytes),
              let request = try? JSONDecoder().decode(MCPBridgeRequest.self, from: requestData),
              let handler = lock.withLock({ requestHandler }) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        var response: MCPBridgeResponse?
        let responseLock = NSLock()
        Task {
            let resolved = await handler(request)
            responseLock.withLock { response = resolved }
            semaphore.signal()
        }
        semaphore.wait()
        guard let response = responseLock.withLock({ response }),
              let data = try? JSONEncoder().encode(response) + Data([10]) else { return }
        writeAll(data, to: fd)
    }

    private func verifyHelperPeer(_ fd: Int32) -> Bool {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return false }
        var guest: SecCode?
        let status = SecCodeCopyGuestWithAttributes(
            nil,
            [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary,
            [],
            &guest
        )
        guard status == errSecSuccess, let guest else { return false }
        guard let teamID = signingTeamIdentifier(of: Self.selfCode) else { return false }
        let requirement = "identifier \"\(MCPBridgeConfiguration.helperBundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        var codeRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &codeRequirement) == errSecSuccess,
              let codeRequirement else { return false }
        return SecCodeCheckValidity(guest, SecCSFlags(rawValue: kSecCSStrictValidate), codeRequirement) == errSecSuccess
    }

    private static var selfCode: SecCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess else { return nil }
        return code
    }

    private func signingTeamIdentifier(of code: SecCode?) -> String? {
        guard let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func removeStaleSocket(at path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return }
            throw MCPAgentSocketError.posix("lstat")
        }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else {
            throw MCPAgentSocketError.unsafeSocketPath
        }
        guard unlink(path) == 0 else { throw MCPAgentSocketError.posix("unlink") }
    }

    private func readLine(from fd: Int32, maximumBytes: Int) -> Data? {
        var result = Data()
        var byte: UInt8 = 0
        while result.count <= maximumBytes {
            let count = Darwin.read(fd, &byte, 1)
            if count != 1 { return nil }
            if byte == 10 { return result }
            result.append(byte)
        }
        return nil
    }

    private func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: written), bytes.count - written)
                if count <= 0 { return }
                written += count
            }
        }
    }
}

enum MCPAgentSocketError: LocalizedError {
    case appGroupUnavailable
    case socketPathTooLong
    case unsafeSocketPath
    case posix(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: "The BuildSweep app group is unavailable. Use a properly signed BuildSweep build."
        case .socketPathTooLong: "The private MCP socket path is too long for a local socket."
        case .unsafeSocketPath: "The private MCP socket path is occupied by an unexpected file."
        case .posix(let operation): "Could not start the local MCP socket (\(operation), errno \(errno))."
        }
    }
}
