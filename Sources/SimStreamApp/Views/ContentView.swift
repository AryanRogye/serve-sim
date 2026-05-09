import SwiftUI

struct ContentView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            SimulatorWorkspaceView(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.refreshDevices()
                } label: {
                    Label("Refresh Simulators", systemImage: "arrow.clockwise")
                }

                Button {
                    store.isStreaming ? store.stop() : store.startSelectedDevice()
                } label: {
                    Label(store.isStreaming ? "Stop" : "Start", systemImage: store.isStreaming ? "stop.fill" : "play.fill")
                }
                .disabled(store.selectedDevice == nil)

                Toggle(isOn: $store.axOverlayEnabled) {
                    Label("AX Overlay", systemImage: "viewfinder")
                }
                .toggleStyle(.button)
                .disabled(store.frameImage == nil)
            }
        }
    }
}
