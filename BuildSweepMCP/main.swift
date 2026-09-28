import Foundation
import MCP
import System
import Darwin
import Security

private enum MCPBridgeConfiguration {
    static let appBundleIdentifier = "com.ayush.buildsweep"
    static let appGroupSuffix = "com.ayush.buildsweep"
    static var socketURL: URL? {
        guard let teamID = currentTeamIdentifier() else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "\(teamID).\(appGroupSuffix)")?
            .appendingPathComponent("BuildSweepMCP.sock")
    }
}

private struct ToolArguments: Codable {
    var category: String?
    var limit: Int?
    var cursor: String?
    var itemID: String?
    var itemIDs: [String]?
    var snapshotGeneration: String?
    var reviewID: String?
}

private struct BridgePayload: Codable {
    let operation: String
    let arguments: ToolArguments
}

private struct BridgeResponse: Codable {
    let id: UUID
    let result: String?
    let error: String?
}

private struct BridgeRequest: Codable {
    let id: UUID
    let operation: String
    let arguments: String
}

private enum BridgeError: Error, LocalizedError {
    case appGroupUnavailable
    case socketUnavailable(String, Int32)
    case appSignatureUnverified(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: "The MCP helper could not resolve BuildSweep's signed app group. Reinstall BuildSweep and enable MCP in Settings."
        case .socketUnavailable(let operation, let code): "BuildSweep's local MCP socket is unavailable (" + operation + ", errno " + String(code) + "). Open BuildSweep and enable MCP in Settings."
        case .appSignatureUnverified(let reason): "The MCP helper could not verify the signed BuildSweep app (\(reason)). Reinstall BuildSweep and its MCP helper."
        case .invalidResponse: "BuildSweep returned an invalid local MCP response."
        }
    }
}

private struct AppConnection {
    func send(operation: String, arguments: ToolArguments) throws -> String {
        guard let socketURL = MCPBridgeConfiguration.socketURL else { throw BridgeError.appGroupUnavailable }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.socketUnavailable("socket", errno) }
        defer { Darwin.close(fd) }
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw BridgeError.socketUnavailable("setsockopt", errno)
        }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw BridgeError.socketUnavailable("path", ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: Array(path.utf8) + [0])
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw BridgeError.socketUnavailable("connect", errno) }
        if let failure = verifyBuildSweepPeer(fd) { throw BridgeError.appSignatureUnverified(failure) }

        let argsData = try JSONEncoder().encode(arguments)
        guard let args = String(data: argsData, encoding: .utf8) else { throw BridgeError.invalidResponse }
        let request = BridgeRequest(id: UUID(), operation: operation, arguments: args)
        var requestData = try JSONEncoder().encode(request)
        requestData.append(10)
        try writeAll(requestData, to: fd)
        guard let data = readLine(from: fd), let response = try? JSONDecoder().decode(BridgeResponse.self, from: data), response.id == request.id else {
            throw BridgeError.invalidResponse
        }
        if let error = response.error { throw NSError(domain: "BuildSweep.MCP", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard let result = response.result else { throw BridgeError.invalidResponse }
        return result
    }

    private func readLine(from fd: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count <= 65_536 {
            guard Darwin.read(fd, &byte, 1) == 1 else { return nil }
            if byte == 10 { return data }
            data.append(byte)
        }
        return nil
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: written), bytes.count - written)
                guard count > 0 else { throw BridgeError.socketUnavailable("write", errno) }
                written += count
            }
        }
    }
}

private func currentTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let information = information as? [String: Any] else { return nil }
    return information[kSecCodeInfoTeamIdentifier as String] as? String
}

private func verifyBuildSweepPeer(_ fd: Int32) -> String? {
    var pid: pid_t = 0
    var size = socklen_t(MemoryLayout<pid_t>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return "peer PID lookup (errno \(errno))" }
    var guest: SecCode?
    let guestStatus = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary, [], &guest)
    guard guestStatus == errSecSuccess, let guest else { return "peer code lookup (status \(guestStatus))" }
    guard let teamID = currentTeamIdentifier() else { return "helper signing team lookup" }
    let requirement = "identifier \"\(MCPBridgeConfiguration.appBundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    var codeRequirement: SecRequirement?
    let requirementStatus = SecRequirementCreateWithString(requirement as CFString, [], &codeRequirement)
    guard requirementStatus == errSecSuccess, let codeRequirement else { return "requirement creation (status \(requirementStatus))" }
    let validityStatus = SecCodeCheckValidity(guest, SecCSFlags(rawValue: kSecCSStrictValidate), codeRequirement)
    return validityStatus == errSecSuccess ? nil : "strict app signature check (status \(validityStatus))"
}

Task {
    do {
        try await runServer()
    } catch {
        FileHandle.standardError.write(Data("BuildSweep MCP: \(error.localizedDescription)\n".utf8))
        Darwin.exit(EXIT_FAILURE)
    }
}
dispatchMain()

private func runServer() async throws {
    let connection = AppConnection()
    let server = Server(
        name: "BuildSweep",
        version: "1.0.0",
        capabilities: .init(tools: .init())
    )

    await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                Tool(name: "get_status", description: "Get BuildSweep connection, scan, and authorization status.", inputSchema: objectSchema()),
                Tool(name: "scan_storage", description: "Start a scan using only locations already authorized in BuildSweep. Poll get_status for progress.", inputSchema: objectSchema()),
                Tool(name: "list_storage_items", description: "List bounded storage item summaries using opaque IDs. Paths and file contents are never returned.", inputSchema: objectSchema([
                    "category": .object(["type": .string("string")]),
                    "limit": .object(["type": .string("integer")]),
                    "cursor": .object(["type": .string("string")])
                ])),
                Tool(name: "inspect_storage_item", description: "Inspect metadata and up to 30 immediate child summaries for a current opaque item ID.", inputSchema: objectSchema([
                    "itemID": .object(["type": .string("string")])
                ], required: ["itemID"])),
                Tool(name: "prepare_cleanup", description: "Stage up to 50 current items for native BuildSweep review. This never executes cleanup; the person must confirm in BuildSweep.", inputSchema: objectSchema([
                    "snapshotGeneration": .object(["type": .string("string")]),
                    "itemIDs": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "maxItems": .int(50)])
                ], required: ["snapshotGeneration", "itemIDs"]), annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
                Tool(name: "get_cleanup_status", description: "Check whether a staged cleanup is awaiting native review, was cancelled, or finished after the person confirmed it.", inputSchema: objectSchema([
                    "reviewID": .object(["type": .string("string")])
                ], required: ["reviewID"]))
            ])
        }

    await server.withMethodHandler(CallTool.self) { params in
            do {
                let data = try JSONEncoder().encode(params.arguments ?? [:])
                let arguments = try JSONDecoder().decode(ToolArguments.self, from: data)
                let operation: String
                switch params.name {
                case "get_status": operation = "status"
                case "scan_storage": operation = "scan"
                case "list_storage_items": operation = "list"
                case "inspect_storage_item": operation = "inspect"
                case "prepare_cleanup": operation = "prepare"
                case "get_cleanup_status": operation = "cleanupStatus"
                default: return .init(content: [.text(text: "Unknown BuildSweep tool.", annotations: nil, _meta: nil)], isError: true)
                }
                let result = try connection.send(operation: operation, arguments: arguments)
                return .init(content: [.text(text: result, annotations: nil, _meta: nil)], isError: false)
            } catch {
                return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
            }
        }

    try await server.start(transport: StdioTransport())
}

private func objectSchema(
    _ properties: [String: Value] = [:],
    required: [String] = []
) -> Value {
    var schema: [String: Value] = ["type": .string("object"), "properties": .object(properties), "additionalProperties": .bool(false)]
    if !required.isEmpty { schema["required"] = .array(required.map(Value.string)) }
    return .object(schema)
}
