import SwiftUI

struct SimulatorWorkspaceView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        HStack(spacing: 0) {
            SimulatorCanvasView(store: store)
                .frame(minWidth: 360)

            Divider()

            VSplitView {
                AccessibilityInspectorView(store: store)
                    .frame(minHeight: 260)

                RuntimeInspectorView(store: store)
                    .frame(minHeight: 260)
            }
            .frame(width: 380)
        }
        .navigationTitle(store.selectedDevice?.name ?? "Simulator Streamer")
    }
}
