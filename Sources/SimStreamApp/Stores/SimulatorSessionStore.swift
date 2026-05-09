import AppKit
import Foundation
import Observation
import SimStreamerCore

@MainActor
@Observable
final class SimulatorSessionStore {
    var devices: [SimulatorDevice] = []
    var selectedDeviceID: String?
    var frameImage: NSImage?
    var frameSize: CGSize = .zero
    var accessibilitySnapshot: AccessibilitySnapshot?
    var selectedElementID: String?
    var hoveredElementID: String?
    var isStreaming = false
    var axOverlayEnabled = true
    var textToType = ""
    var runtimeBundleID = ""
    var runtimeInspectorStatus = "Runtime inspector idle."
    var runtimeInspectorLogs: [String] = []
    var isRuntimeInspectorBusy = false
    var isRuntimeLogStreaming = false
    var statusText = "Select a booted simulator."
    var errorText: String?

    private var streamer: SimulatorStreamer?
    private var inputController: SimulatorInputController?
    private var runtimeLogStream: RuntimeInspectorLogStream?
    private var axTask: Task<Void, Never>?
    private var lastFrameUpdate = Date.distantPast

    var selectedDevice: SimulatorDevice? {
        guard let selectedDeviceID else { return devices.first }
        return devices.first { $0.id == selectedDeviceID }
    }

    var selectedElement: AccessibilityElement? {
        guard let selectedElementID else { return nil }
        return accessibilitySnapshot?.elements.first { $0.id == selectedElementID }
    }

    func refreshDevices() {
        do {
            devices = try SimulatorDeviceService.bootedDevices()
            if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = devices.first?.id
            }
            statusText = devices.isEmpty ? "No booted simulators found." : "Ready."
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            statusText = "Could not read simulators."
        }
    }

    func startSelectedDevice() {
        guard let device = selectedDevice else {
            statusText = "Boot a simulator first."
            return
        }
        start(deviceUDID: device.udid)
    }

    func start(deviceUDID: String) {
        stop()

        let nextStreamer = SimulatorStreamer(jpegQuality: 0.72)
        let nextInputController = SimulatorInputController()
        streamer = nextStreamer
        inputController = nextInputController
        statusText = "Starting \(selectedDevice?.name ?? "simulator")..."
        errorText = nil

        do {
            try nextInputController.setup(deviceUDID: deviceUDID)
            try nextStreamer.start(
                deviceUDID: deviceUDID,
                onJPEGFrame: { [weak self] data in
                    Task { @MainActor in
                        self?.acceptFrame(data)
                    }
                },
                onScreenSize: { [weak self] size in
                    Task { @MainActor in
                        self?.frameSize = CGSize(width: size.width, height: size.height)
                    }
                }
            )
            isStreaming = true
            statusText = "Streaming \(selectedDevice?.name ?? deviceUDID)."
            startAccessibilityPolling(deviceUDID: deviceUDID)
        } catch {
            streamer = nil
            inputController = nil
            isStreaming = false
            errorText = error.localizedDescription
            statusText = "Failed to start stream."
        }
    }

    func stop() {
        axTask?.cancel()
        axTask = nil
        stopRuntimeLogStream()
        streamer?.stop()
        streamer = nil
        inputController = nil
        isStreaming = false
        accessibilitySnapshot = nil
        selectedElementID = nil
        hoveredElementID = nil
        if frameImage != nil {
            statusText = "Stopped."
        }
    }

    func refreshAccessibilityNow() {
        guard let device = selectedDevice else { return }
        Task {
            await updateAccessibility(deviceUDID: device.udid)
        }
    }

    func activate(elementID: String) {
        selectedElementID = elementID
        guard
            let element = accessibilitySnapshot?.elements.first(where: { $0.id == elementID }),
            let snapshot = accessibilitySnapshot
        else { return }

        inputController?.tap(element: element, in: snapshot)
        statusText = "Tapped \(element.label.isEmpty ? element.roleOrType : element.label)."
    }

    func tapSelectedElement() {
        guard let selectedElementID else { return }
        activate(elementID: selectedElementID)
    }

    func typeIntoSelectedElement() {
        let text = textToType
        guard !text.isEmpty else { return }
        guard
            let element = selectedElement,
            let snapshot = accessibilitySnapshot
        else { return }

        inputController?.tapAndType(element: element, in: snapshot, text: text)
        statusText = "Typed into \(element.label.isEmpty ? element.roleOrType : element.label)."
    }

    func pressReturnInSimulator() {
        inputController?.pressReturn()
    }

    func pressBackspaceInSimulator() {
        inputController?.pressBackspace()
    }

    func launchRuntimeInspector() {
        let bundleID = runtimeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else {
            runtimeInspectorStatus = "Enter a bundle id first."
            return
        }
        guard let device = selectedDevice else {
            runtimeInspectorStatus = "Select a booted simulator first."
            return
        }

        isRuntimeInspectorBusy = true
        runtimeInspectorStatus = "Building runtime inspector..."
        errorText = nil

        Task {
            do {
                let dylibPath = try await Task.detached(priority: .userInitiated) {
                    try RuntimeInspectorService.buildDylib()
                }.value

                runtimeInspectorStatus = "Launching \(bundleID)..."

                try await Task.detached(priority: .userInitiated) {
                    try RuntimeInspectorService.launch(
                        bundleID: bundleID,
                        deviceUDID: device.udid,
                        dylibPath: dylibPath
                    )
                }.value

                runtimeInspectorStatus = "Injected into \(bundleID). Interact with the app to see selector logs."
                startRuntimeLogStream()
            } catch {
                runtimeInspectorStatus = "Runtime inspector failed."
                errorText = error.localizedDescription
            }
            isRuntimeInspectorBusy = false
        }
    }

    func startRuntimeLogStream() {
        guard let device = selectedDevice else {
            runtimeInspectorStatus = "Select a booted simulator first."
            return
        }

        stopRuntimeLogStream()
        let stream = RuntimeInspectorLogStream(deviceUDID: device.udid) { [weak self] line in
            Task { @MainActor in
                self?.appendRuntimeLog(line)
            }
        }

        do {
            try stream.start()
            runtimeLogStream = stream
            isRuntimeLogStreaming = true
            runtimeInspectorStatus = "Streaming selector logs."
        } catch {
            runtimeInspectorStatus = "Could not start selector logs."
            errorText = error.localizedDescription
        }
    }

    func stopRuntimeLogStream() {
        runtimeLogStream?.stop()
        runtimeLogStream = nil
        isRuntimeLogStreaming = false
    }

    func clearRuntimeLogs() {
        runtimeInspectorLogs.removeAll()
    }

    private func acceptFrame(_ data: Data) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameUpdate) >= 1.0 / 30.0 else { return }
        guard let image = NSImage(data: data) else { return }
        frameImage = image
        if frameSize == .zero {
            frameSize = image.size
        }
        lastFrameUpdate = now
    }

    private func startAccessibilityPolling(deviceUDID: String) {
        axTask?.cancel()
        axTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateAccessibility(deviceUDID: deviceUDID)
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }

    private func updateAccessibility(deviceUDID: String) async {
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try SimulatorAccessibility.snapshot(deviceUDID: deviceUDID)
            }.value
            accessibilitySnapshot = snapshot
            if let selectedElementID, !snapshot.elements.contains(where: { $0.id == selectedElementID }) {
                self.selectedElementID = nil
            }
            if let hoveredElementID, !snapshot.elements.contains(where: { $0.id == hoveredElementID }) {
                self.hoveredElementID = nil
            }
        } catch {
            accessibilitySnapshot = nil
            errorText = "AX unavailable: \(error.localizedDescription)"
        }
    }

    private func appendRuntimeLog(_ line: String) {
        runtimeInspectorLogs.append(line)
        if runtimeInspectorLogs.count > 400 {
            runtimeInspectorLogs.removeFirst(runtimeInspectorLogs.count - 400)
        }
    }
}

private extension AccessibilityElement {
    var roleOrType: String {
        if !role.isEmpty { return role }
        if !type.isEmpty { return type }
        return "element"
    }
}
