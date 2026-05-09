import Foundation

struct SimulatorDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let runtime: String
    let state: String

    var udid: String { id }
    var isBooted: Bool { state == "Booted" }
}
