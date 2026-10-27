import Foundation
import NTFSSiliconKit

/// App-wide state: the volume list and selection, one session-wide.
/// There is no database — the volumes come from the system each launch;
/// only per-volume user options persist (VolumePrefs, keyed by UUID).
@Observable
final class AppModel {
    let store = VolumeStore()
    var volumes: [VolumeInfo] = []
    /// Restores the last selection immediately (S-006); `refresh()` keeps it
    /// only if that volume still exists, else falls back to the boot volume.
    init() {
        if !Env.isOverridden {
            selection = UserDefaults.standard.string(forKey: "last.selected")
        }
    }
    var selection: String? {
        didSet { // remembered across launches (S-006); test runs don't write it
            if !Env.isOverridden {
                UserDefaults.standard.set(selection, forKey: "last.selected")
            }
        }
    }
    var error: String?
    var busyLabel: String?
    /// Cross-view actions (S-043): right-clicking a sidebar row may address
    /// a volume whose detail pane is not open. The erase sheet is presented
    /// by the window for any volume; verify selects the row first, and the
    /// counter makes repeating the same request on the same volume fire.
    var eraseTarget: VolumeInfo?
    var verifyRequest = 0
    /// False until the first refresh lands, so the sidebar shows a loading
    /// state instead of flashing the empty view.
    private(set) var loaded = false
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Env.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    var selected: VolumeInfo? {
        volumes.first { $0.device == selection }
    }

    func refresh() async {
        if let list = try? await store.refresh() {
            volumes = list
        }
        if selection == nil || selected == nil {
            selection = volumes.first { $0.isBoot }?.device ?? volumes.first?.device
        }
        loaded = true
    }

    func options(for volume: VolumeInfo) -> VolumeOptions {
        VolumePrefs.options(forUUID: volume.uuid)
    }

    func setOptions(_ options: VolumeOptions, for volume: VolumeInfo) {
        VolumePrefs.set(options, forUUID: volume.uuid)
    }

    func requestVerify(for volume: VolumeInfo) {
        selection = volume.device
        verifyRequest += 1
    }

    /// Runs one action with the busy label up, refreshes afterwards,
    /// keeps the first error inline.
    func act(_ label: String, _ action: @escaping (VolumeStore) async -> String?) async {
        busyLabel = label
        defer { busyLabel = nil }
        if let failure = await action(store) { error = failure }
        await refresh()
    }
}
