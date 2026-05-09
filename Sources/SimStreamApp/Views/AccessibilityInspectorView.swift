import SimStreamerCore
import SwiftUI

struct AccessibilityInspectorView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let snapshot = store.accessibilitySnapshot {
                List(selection: $store.selectedElementID) {
                    ForEach(snapshot.elements) { element in
                        AccessibilityRow(
                            element: element,
                            isHovered: store.hoveredElementID == element.id
                        )
                        .tag(element.id)
                        .onHover { inside in
                            store.hoveredElementID = inside ? element.id : nil
                        }
                    }
                }
                .listStyle(.inset)

                if let selected = store.selectedElement {
                    Divider()
                    AccessibilityActionsView(store: store, element: selected)
                    Divider()
                    AccessibilityDetailView(element: selected)
                }
            } else {
                ContentUnavailableView(
                    "No AX Snapshot",
                    systemImage: "viewfinder",
                    description: Text(store.isStreaming ? "Waiting for simulator accessibility data." : "Start the stream to inspect native accessibility elements.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AX Tree")
                    .font(.headline)
                Text(elementCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refreshAccessibilityNow()
            } label: {
                Label("Refresh AX", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(!store.isStreaming)
        }
        .padding(12)
    }

    private var elementCountText: String {
        guard let count = store.accessibilitySnapshot?.elements.count else { return "No elements" }
        return count == 1 ? "1 element" : "\(count) elements"
    }
}

private struct AccessibilityActionsView: View {
    @Bindable var store: SimulatorSessionStore
    let element: AccessibilityElement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    store.tapSelectedElement()
                } label: {
                    Label("Tap", systemImage: "hand.tap")
                }

                Button {
                    store.pressReturnInSimulator()
                } label: {
                    Label("Return", systemImage: "return")
                }

                Button {
                    store.pressBackspaceInSimulator()
                } label: {
                    Label("Delete", systemImage: "delete.left")
                }
            }

            HStack(spacing: 8) {
                TextField("Text to type", text: $store.textToType)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.typeIntoSelectedElement()
                    }

                Button {
                    store.typeIntoSelectedElement()
                } label: {
                    Label("Type", systemImage: "keyboard")
                }
                .disabled(store.textToType.isEmpty)
            }

            Text(actionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionHint: String {
        let title = element.label.isEmpty ? (element.role.isEmpty ? element.type : element.role) : element.label
        return "Actions target \(title.isEmpty ? "the selected element" : title). Click overlay boxes to tap directly."
    }
}

private struct AccessibilityRow: View {
    let element: AccessibilityElement
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(roleText)
                    .foregroundStyle(.secondary)
                Text(sizeText)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.vertical, 3)
        .listRowBackground(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var title: String {
        if !element.label.isEmpty { return element.label }
        if !element.value.isEmpty { return element.value }
        if !element.role.isEmpty { return element.role }
        return "Unlabeled"
    }

    private var roleText: String {
        element.role.isEmpty ? element.type : element.role
    }

    private var sizeText: String {
        "\(Int(element.frame.width.rounded()))x\(Int(element.frame.height.rounded()))"
    }
}

private struct AccessibilityDetailView: View {
    let element: AccessibilityElement

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            detailRow("Label", element.label)
            detailRow("Value", element.value)
            detailRow("Role", element.role)
            detailRow("Type", element.type)
            detailRow("Enabled", element.enabled ? "Yes" : "No")
            detailRow("Frame", frameText)
            detailRow("Path", element.path)
            detailRow("ID", element.id)
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private var frameText: String {
        "\(Int(element.frame.x.rounded())), \(Int(element.frame.y.rounded()))  \(Int(element.frame.width.rounded()))x\(Int(element.frame.height.rounded()))"
    }
}
