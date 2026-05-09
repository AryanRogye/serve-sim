import Foundation

struct SimulatorInstalledApp: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let bundleName: String
    let applicationType: String

    var id: String { bundleIdentifier }

    var title: String {
        if !displayName.isEmpty {
            return displayName
        }
        if !bundleName.isEmpty {
            return bundleName
        }
        return bundleIdentifier
    }

    var isUserApp: Bool {
        applicationType == "User"
    }
}
