import Foundation

enum SimulatorDeviceService {
    static func bootedDevices() throws -> [SimulatorDevice] {
        let output = try run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "-j"])
        let response = try JSONDecoder().decode(SimctlDeviceResponse.self, from: output)

        return response.devices.flatMap { runtime, devices in
            devices
                .filter { $0.state == "Booted" }
                .map {
                    SimulatorDevice(
                        id: $0.udid,
                        name: $0.name,
                        runtime: runtimeDisplayName(runtime),
                        state: $0.state
                    )
                }
        }
        .sorted { lhs, rhs in
            if lhs.runtime == rhs.runtime { return lhs.name < rhs.name }
            return lhs.runtime > rhs.runtime
        }
    }

    private static func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "SimulatorDeviceService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message ?? "xcrun simctl failed"]
            )
        }
        return data
    }

    private static func runtimeDisplayName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

private struct SimctlDeviceResponse: Decodable {
    let devices: [String: [SimctlDevice]]
}

private struct SimctlDevice: Decodable {
    let name: String
    let udid: String
    let state: String
}
