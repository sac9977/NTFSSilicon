import AppKit
import NTFSSiliconKit
import SwiftUI

// NTFSSilicon — a native volume manager.
//   APP_STORE=… NTFSSilicon     mark a sandboxed run (self-test, snapshots)
//   APP_SNAPSHOT=<dir> …        save PNGs of the window and Settings, then quit
//   NTFSSilicon --selftest      run the self-test and quit with 0 or 1
//   APP_ACCENT=<id> …           run with another accent from Theme.all

@main
struct NTFSSiliconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("NTFSSilicon", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 960, height: 620)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.selected?.isMounted == true ? "Unmount" : "Mount") {
                    Task {
                        (model.selected?.isMounted == true)
                            ? await model.unmountSelected() : await model.mountSelected()
                    }
                }
                .keyboardShortcut("m", modifiers: .command)
                .disabled(model.selected == nil || model.busyLabel != nil)
                Button("Eject") { Task { await model.ejectSelected() } }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.selected == nil || model.busyLabel != nil)
                Button("Verify") { Task { await model.verifySelected() } }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(model.selected?.isMounted != true || model.busyLabel != nil)
                Divider()
                Button("Refresh Volumes") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        VolumeMenu()

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

extension AppModel {
    @MainActor
    func mountSelected() async {
        guard let volume = selected else { return }
        let readOnly = options(for: volume).readOnly
        await act("Mounting \(volume.name)…") { store in
            await MountVeto.allowing { await store.mount(volume, readOnly: readOnly) }
        }
    }

    @MainActor
    func unmountSelected() async {
        guard let volume = selected else { return }
        await act("Unmounting \(volume.name)…") { await $0.unmount(volume) }
    }

    @MainActor
    func ejectSelected() async {
        guard let volume = selected else { return }
        await act("Ejecting \(volume.name)…") { await $0.eject(volume) }
    }

    @MainActor
    func verifySelected() async {
        guard let volume = selected else { return }
        await act("Verifying \(volume.name)…") { store in
            switch await store.verify(volume) {
            case .passed: return nil
            case .failed(let line): return line
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        MountVeto.start()
    }

    // The volume menu exists with or without the main window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// True when a test run points APP_STORE somewhere else (self-test, snapshots).
enum Env {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }
}
