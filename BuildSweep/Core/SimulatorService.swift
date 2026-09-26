import Foundation

enum SimulatorFeaturePolicy {
    // Keep false until a signed App Sandbox feasibility build proves both inventory and deletion.
    static let deletionEnabled = false
}

enum SimulatorControllerError: LocalizedError, Equatable {
    case commandFailed(String)
    case invalidJSON
    case deletionNotValidated
    case broadDeletionTarget
    case invalidDeviceID
    case deviceNotInInventory

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): "simctl failed: \(message)"
        case .invalidJSON: "simctl returned data BuildSweep could not understand."
        case .deletionNotValidated: "Permanent Simulator deletion is disabled until signed sandbox feasibility is proven."
        case .broadDeletionTarget: "BuildSweep will not delete every Simulator device or every unavailable device."
        case .invalidDeviceID: "Simulator deletion requires one device UDID."
        case .deviceNotInInventory: "That Simulator device is not in the current inventory."
        }
    }
}

enum SimulatorDeviceIDPolicy {
    private static let udidPattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#

    static func validate(_ raw: String) throws -> String {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = id.lowercased()
        if id.isEmpty || lowered == "all" || lowered == "unavailable" || id.contains(where: { $0.isWhitespace || $0 == "," || $0 == "/" }) {
            throw SimulatorControllerError.broadDeletionTarget
        }
        guard id.range(of: udidPattern, options: .regularExpression) != nil else {
            throw SimulatorControllerError.invalidDeviceID
        }
        return id
    }

    static func confirm(_ id: String, listedDeviceIDs: some Sequence<String>) throws -> String {
        let udid = try validate(id)
        let listed = Set(listedDeviceIDs.map { $0.uppercased() })
        guard listed.contains(udid.uppercased()) else { throw SimulatorControllerError.deviceNotInInventory }
        return udid
    }
}

actor SimctlController: SimulatorControlling {
    private let sizer = DirectorySizer()

    func inventory() async throws -> SimulatorInventory {
        let data = try run(arguments: ["simctl", "list", "--json"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimulatorControllerError.invalidJSON
        }
        let rawDevices = root["devices"] as? [String: [[String: Any]]] ?? [:]
        var devices: [SimulatorDevice] = []
        for (runtime, values) in rawDevices {
            for value in values {
                guard let id = value["udid"] as? String, let name = value["name"] as? String else { continue }
                let path = (value["dataPath"] as? String).map(URL.init(fileURLWithPath:))
                let size: Int64 = if let path { (try? await sizer.allocatedSize(of: path)) ?? Int64(0) } else { Int64(0) }
                devices.append(SimulatorDevice(
                    id: id,
                    name: name,
                    runtime: runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "").replacingOccurrences(of: "-", with: " "),
                    state: value["state"] as? String ?? "Unknown",
                    dataPath: path,
                    size: size,
                    isAvailable: value["isAvailable"] as? Bool ?? true
                ))
            }
        }
        let rawRuntimes = root["runtimes"] as? [[String: Any]] ?? []
        let runtimes = rawRuntimes.compactMap { value -> SimulatorRuntime? in
            guard let id = value["identifier"] as? String, let name = value["name"] as? String else { return nil }
            return SimulatorRuntime(id: id, name: name, version: value["version"] as? String ?? "Unknown", isAvailable: value["isAvailable"] as? Bool ?? true)
        }
        return SimulatorInventory(
            devices: devices.sorted { $0.size > $1.size },
            runtimes: runtimes,
            deletionIsAvailable: SimulatorFeaturePolicy.deletionEnabled,
            limitation: SimulatorFeaturePolicy.deletionEnabled ? nil : "Simulator deletion is inspection-only until it passes the signed App Sandbox feasibility test."
        )
    }

    func deleteDevice(id: String) async throws {
        let udid = try SimulatorDeviceIDPolicy.validate(id)
        guard SimulatorFeaturePolicy.deletionEnabled else { throw SimulatorControllerError.deletionNotValidated }
        let inventory = try await inventory()
        let confirmed = try SimulatorDeviceIDPolicy.confirm(udid, listedDeviceIDs: inventory.devices.map(\.id))
        _ = try run(arguments: ["simctl", "delete", confirmed])
    }

    private func run(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SimulatorControllerError.commandFailed(String(decoding: errorData, as: UTF8.self))
        }
        return outputData
    }
}
