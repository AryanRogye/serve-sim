import SwiftUI

struct RuntimeInspectorView: View {
    @Bindable var store: SimulatorSessionStore

    private var visibleLogEntries: [(offset: Int, element: String)] {
        Array(store.runtimeInspectorLogs.enumerated()).filter { _, line in
            store.runtimeShowsStackFrames || !RuntimeLogEntry(line: line).isStackNoise
        }
    }

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

                RuntimeAppPicker(store: store)

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

                    Toggle(isOn: $store.runtimeShowsStackFrames) {
                        Label("Stacks", systemImage: "list.bullet.rectangle")
                    }
                    .toggleStyle(.button)
                    .help("Show call stack frames")
                }

                Text(store.runtimeInspectorStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            .padding(12)

            Divider()

            if visibleLogEntries.isEmpty {
                ContentUnavailableView(
                    "No Selector Logs",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(store.runtimeInspectorLogs.isEmpty
                                      ? "Inject a simulator app, then tap controls to see target/action selectors here."
                                      : "Only stack frames are hidden. Turn on Stacks to show them.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(visibleLogEntries, id: \.offset) { index, line in
                                RuntimeLogRow(line: line)
                                    .id(index)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: store.runtimeInspectorLogs.count) { _, count in
                        guard count > 0 else { return }
                        if let lastVisible = visibleLogEntries.last?.offset {
                            proxy.scrollTo(lastVisible, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            if store.runtimeInstalledApps.isEmpty {
                store.refreshRuntimeInstalledApps()
            }
        }
        .onChange(of: store.selectedDeviceID) {
            store.runtimeInstalledApps = []
            store.runtimeAppSearchText = ""
            store.refreshRuntimeInstalledApps()
        }
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

private struct RuntimeAppPicker: View {
    @Bindable var store: SimulatorSessionStore

    private var visibleApps: [SimulatorInstalledApp] {
        Array(store.filteredRuntimeInstalledApps.prefix(50))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                TextField("Search installed apps or bundle IDs", text: $store.runtimeAppSearchText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    store.refreshRuntimeInstalledApps()
                } label: {
                    Label("Refresh Apps", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Refresh installed apps")
                .disabled(store.isRuntimeAppListLoading || store.selectedDevice == nil)
            }

            appList

            HStack {
                Text(resultSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isRuntimeAppListLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var appList: some View {
        if store.runtimeInstalledApps.isEmpty && !store.isRuntimeAppListLoading {
            Text("No app list loaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else if visibleApps.isEmpty {
            Text("No matching apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleApps) { app in
                        RuntimeAppRow(app: app, isSelected: store.runtimeBundleID == app.bundleIdentifier) {
                            store.selectRuntimeApp(app)
                        }
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 96, maxHeight: 160)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var resultSummary: String {
        if store.isRuntimeAppListLoading {
            return "Loading installed apps..."
        }

        let total = store.runtimeInstalledApps.count
        let visible = store.filteredRuntimeInstalledApps.count
        if total == 0 {
            return "Select a booted simulator, then refresh apps."
        }
        if visible == total {
            return "\(total) installed apps"
        }
        return "\(visible) of \(total) apps"
    }
}

private struct RuntimeAppRow: View {
    let app: SimulatorInstalledApp
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: app.isUserApp ? "app.badge" : "app")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(app.bundleIdentifier)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(app.isUserApp ? "User" : "System")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tertiary.opacity(0.5), in: Capsule())
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Use \(app.bundleIdentifier)")
    }
}

private struct RuntimeLogRow: View {
    let line: String

    private var entry: RuntimeLogEntry {
        RuntimeLogEntry(line: line)
    }

    var body: some View {
        if entry.isStackNoise {
            stackRow
        } else {
            eventRow
        }
    }

    private var eventRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.kind)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let event = entry.fields["events"] ?? entry.fields["event"] {
                    Text(event)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let action = entry.fields["action"] {
                Text(action)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let metadata = entry.metadata
            if !metadata.isEmpty {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(metadata, id: \.self) { item in
                        Text(item)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.tertiary.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 6))
    }

    private var stackRow: some View {
        Text(entry.message)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}

private struct RuntimeLogEntry {
    let message: String

    init(line: String) {
        if let range = line.range(of: "[RuntimeInspector]") {
            message = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            message = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var isStackNoise: Bool {
        message == "callStackSymbols:"
            || message.range(of: #"^\d+\s+"#, options: .regularExpression) != nil
            || message.hasPrefix("0x")
    }

    var kind: String {
        let firstToken = message.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "Runtime"
        switch firstToken {
        case "UIApplication.sendAction":
            return "App Action"
        case "UIControl.addTarget":
            return "Control Target"
        case "UIControl.sendAction":
            return "Control Action"
        case "UIGestureRecognizer.init":
            return "Gesture Init"
        case "UIGestureRecognizer.addTarget":
            return "Gesture Target"
        case "loaded":
            return "Loaded"
        case "swizzled":
            return "Swizzled"
        default:
            return firstToken
        }
    }

    var fields: [String: String] {
        var result: [String: String] = [:]
        let pattern = #"(\w+)=([^=]+?)(?=\s+\w+=|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }

        let nsRange = NSRange(message.startIndex..<message.endIndex, in: message)
        for match in regex.matches(in: message, range: nsRange) {
            guard
                let keyRange = Range(match.range(at: 1), in: message),
                let valueRange = Range(match.range(at: 2), in: message)
            else { continue }

            result[String(message[keyRange])] = String(message[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    var metadata: [String] {
        let preferredKeys = ["control", "recognizer", "target", "sender", "events", "event"]
        return preferredKeys.compactMap { key in
            guard let value = fields[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentItems: [Row.Item] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if nextWidth > maxWidth, !currentItems.isEmpty {
                rows.append(Row(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(Row.Item(index: index, size: size))
            currentWidth = currentItems.count == 1 ? size.width : currentWidth + spacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }

    private struct Row {
        struct Item {
            let index: Int
            let size: CGSize
        }

        let items: [Item]
        let width: CGFloat
        let height: CGFloat
    }
}
