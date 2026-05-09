import SwiftUI

struct SimulatorWorkspaceView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        HSplitView {
            SimulatorCanvasView(store: store)
                .frame(minWidth: 520)

            VSplitView {
                AccessibilityInspectorView(store: store)
                    .frame(minHeight: 260)

                RuntimeInspectorView(store: store)
                    .frame(minHeight: 220)
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
        }
        .navigationTitle(store.selectedDevice?.name ?? "Simulator Streamer")
    }
}
