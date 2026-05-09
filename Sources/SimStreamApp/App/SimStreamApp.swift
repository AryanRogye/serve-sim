import AppKit
import SwiftUI

@main
struct SimStreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SimulatorSessionStore()

    var body: some Scene {
        WindowGroup("Simulator Streamer") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    store.refreshDevices()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Simulators") {
                    store.refreshDevices()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(store.isStreaming ? "Stop Stream" : "Start Stream") {
                    store.isStreaming ? store.stop() : store.startSelectedDevice()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
