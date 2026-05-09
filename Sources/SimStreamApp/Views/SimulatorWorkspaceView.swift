import SwiftUI

struct SimulatorWorkspaceView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        HSplitView {
            SimulatorCanvasView(store: store)
                .frame(minWidth: 520)

            AccessibilityInspectorView(store: store)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
        }
        .navigationTitle(store.selectedDevice?.name ?? "Simulator Streamer")
    }
}
