import SwiftUI

struct SidebarView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        List(selection: $store.selectedDeviceID) {
            Section("Booted Simulators") {
                if store.devices.isEmpty {
                    Text("No booted simulators")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.devices) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .lineLimit(1)
                            Text(device.runtime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(device.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let error = store.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}
