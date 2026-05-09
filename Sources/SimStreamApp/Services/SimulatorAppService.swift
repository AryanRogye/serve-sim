import Foundation

enum SimulatorAppService {
    static func installedApps(deviceUDID: String) throws -> [SimulatorInstalledApp] {
        let output = try run("/usr/bin/xcrun", arguments: ["simctl", "listapps", deviceUDID])
        let plist = try PropertyListSerialization.propertyList(from: output, format: nil)
        guard let appDictionary = plist as? [String: [String: Any]] else {
            throw NSError(
                domain: "SimulatorAppService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse simulator app list."]
            )
        }

        return appDictionary.compactMap { bundleIdentifier, values in
            guard !bundleIdentifier.isEmpty else { return nil }

            return SimulatorInstalledApp(
                bundleIdentifier: bundleIdentifier,
                displayName: stringValue(values["CFBundleDisplayName"]),
                bundleName: stringValue(values["CFBundleName"]),
                applicationType: stringValue(values["ApplicationType"])
            )
        }
        .sorted { lhs, rhs in
            if lhs.isUserApp != rhs.isUserApp {
                return lhs.isUserApp
            }
            if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
                return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return ""
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
                domain: "SimulatorAppService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message ?? "xcrun simctl listapps failed"]
            )
        }
        return data
    }
}
