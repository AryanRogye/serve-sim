import SwiftUI

struct RuntimeInspectorView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("Bundle ID, e.g. com.example.MyApp", text: $store.runtimeBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.launchRuntimeInspector()
                    }

                HStack {
                    Button {
                        store.launchRuntimeInspector()
                    } label: {
                        Label("Inject & Launch", systemImage: "syringe")
                    }
                    .disabled(store.isRuntimeInspectorBusy || store.runtimeBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        store.isRuntimeLogStreaming ? store.stopRuntimeLogStream() : store.startRuntimeLogStream()
                    } label: {
                        Label(store.isRuntimeLogStreaming ? "Stop Logs" : "Start Logs",
                              systemImage: store.isRuntimeLogStreaming ? "stop.fill" : "text.badge.play")
                    }
                    .disabled(store.selectedDevice == nil)

                    Button {
                        store.clearRuntimeLogs()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(store.runtimeInspectorLogs.isEmpty)
                }

                Text(store.runtimeInspectorStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            .padding(12)

            Divider()

            if store.runtimeInspectorLogs.isEmpty {
                ContentUnavailableView(
                    "No Selector Logs",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Inject a simulator app, then tap controls to see target/action selectors here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(store.runtimeInspectorLogs.enumerated()), id: \.offset) { index, line in
                                RuntimeLogRow(line: line)
                                    .id(index)
                            }
                        }
                        .padding(10)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: store.runtimeInspectorLogs.count) { _, count in
                        guard count > 0 else { return }
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Runtime Inspector")
                    .font(.headline)
                Text("UIKit selectors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isRuntimeInspectorBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
    }
}

private struct RuntimeLogRow: View {
    let line: String

    var body: some View {
        Text(cleanedLine)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private var cleanedLine: String {
        if let range = line.range(of: "[RuntimeInspector]") {
            return String(line[range.lowerBound...])
        }
        return line
    }
}
