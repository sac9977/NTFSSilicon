import Foundation
import NTFSSiliconKit

/// App-wide state: the volume list and selection, one session-wide.
/// There is no database — the volumes come from the system each launch;
/// only per-volume user options persist (VolumePrefs, keyed by UUID).
@Observable
final class AppModel {
    let store = VolumeStore()
    var volumes: [VolumeInfo] = []
    var selection: String?
    var error: String?
    var busyLabel: String?
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
    }

    func options(for volume: VolumeInfo) -> VolumeOptions {
        VolumePrefs.options(forUUID: volume.uuid)
    }

    func setOptions(_ options: VolumeOptions, for volume: VolumeInfo) {
        VolumePrefs.set(options, forUUID: volume.uuid)
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
