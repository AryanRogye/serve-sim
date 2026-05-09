import SimStreamerCore
import SwiftUI

struct SimulatorCanvasView: View {
    @Bindable var store: SimulatorSessionStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = store.frameImage {
                    let contentSize = preferredContentSize(image: image)
                    let imageRect = CGRect.aspectFit(
                        contentSize: contentSize,
                        in: CGRect(origin: .zero, size: proxy.size)
                    )

                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .shadow(radius: 18, y: 8)

                    if store.axOverlayEnabled, let snapshot = store.accessibilitySnapshot {
                        AccessibilityOverlayView(
                            snapshot: snapshot,
                            imageRect: imageRect,
                            selectedID: store.selectedElementID,
                            hoveredID: store.hoveredElementID,
                            onHover: { store.hoveredElementID = $0 },
                            onSelect: { store.activate(elementID: $0) }
                        )
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "iphone")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)
                        Text("Start a booted simulator to stream it here.")
                            .foregroundStyle(.secondary)
                        Button("Start Stream") {
                            store.startSelectedDevice()
                        }
                        .disabled(store.selectedDevice == nil)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.35))
        }
    }

    private func preferredContentSize(image: NSImage) -> CGSize {
        if let snapshot = store.accessibilitySnapshot, snapshot.screen.width > 0, snapshot.screen.height > 0 {
            return snapshot.screen
        }
        if store.frameSize.width > 0, store.frameSize.height > 0 {
            return store.frameSize
        }
        return image.size
    }
}

private struct AccessibilityOverlayView: View {
    let snapshot: AccessibilitySnapshot
    let imageRect: CGRect
    let selectedID: String?
    let hoveredID: String?
    let onHover: (String?) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(snapshot.elements) { element in
                if let rect = overlayRect(for: element) {
                    AccessibilityTargetView(
                        element: element,
                        rect: rect,
                        isSelected: selectedID == element.id,
                        isHovered: hoveredID == element.id,
                        onHover: onHover,
                        onSelect: onSelect
                    )
                }
            }
        }
        .frame(width: imageRect.width, height: imageRect.height)
        .position(x: imageRect.midX, y: imageRect.midY)
    }

    private func overlayRect(for element: AccessibilityElement) -> CGRect? {
        guard snapshot.screen.width > 0, snapshot.screen.height > 0 else { return nil }

        let scaleX = imageRect.width / snapshot.screen.width
        let scaleY = imageRect.height / snapshot.screen.height
        let rect = CGRect(
            x: element.frame.x * scaleX,
            y: element.frame.y * scaleY,
            width: element.frame.width * scaleX,
            height: element.frame.height * scaleY
        )
        return rect.width > 2 && rect.height > 2 ? rect : nil
    }
}

private struct AccessibilityTargetView: View {
    let element: AccessibilityElement
    let rect: CGRect
    let isSelected: Bool
    let isHovered: Bool
    let onHover: (String?) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(element.id)
        } label: {
            Rectangle()
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .stroke(strokeColor, lineWidth: isSelected || isHovered ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onHover { inside in
            onHover(inside ? element.id : nil)
        }
    }

    private var strokeColor: Color {
        if isSelected { return .blue }
        if isHovered { return .yellow }
        return .green
    }

    private var fillColor: Color {
        if isSelected { return .blue.opacity(0.24) }
        if isHovered { return .yellow.opacity(0.20) }
        return .green.opacity(0.10)
    }

    private var helpText: String {
        [
            element.label.isEmpty ? "Unlabeled" : element.label,
            element.role.isEmpty ? element.type : element.role,
            element.enabled ? "enabled" : "disabled",
        ].filter { !$0.isEmpty }.joined(separator: " - ")
    }
}
