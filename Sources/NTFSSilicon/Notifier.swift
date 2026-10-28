import DiskArbitration
import UserNotifications
import os

/// Posts user notifications when volumes mount/unmount, per the two Alerts
/// toggles in Settings (S-032). The DiskArbitration description-changed
/// callback is watched only for the mount-point key: it stays quiet while
/// the volumes that are already mounted are registered at launch, and only
/// fires when a mount point appears (mounted) or vanishes (unmounted).
/// Failed mounts announce themselves by absence — DiskArbitration can't
/// see them, so there is no toggle for that (honest shortcut).
final class Notifier: @unchecked Sendable {
    static let shared = Notifier()
    private var session: DASession?
    private var started = false

    /// Requesting notification authorization the first time the user turns
    /// an alert toggle on; turning all off leaves the grant alone.
    static func enabled(_ on: Bool) {
        guard on else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            // Authorized state is otherwise invisible (no TCC access, no
            // ncprefs record until answered); log the answer for diagnosis.
            Logger(subsystem: "com.saslu.ntfssilicon", category: "Notifier")
                .notice("notifications granted=\(granted) error=\(String(describing: error ?? nil))")
        }
    }

    static func start() {
        guard !shared.started else { return }
        shared.started = true
        guard let session = DASessionCreate(kCFAllocatorDefault) as DASession? else { return }
        shared.session = session
        let callback: DADiskDescriptionChangedCallback = { disk, _, context in
            guard let context else { return }
            Unmanaged<Notifier>.fromOpaque(context).takeUnretainedValue().event(for: disk)
        }
        let watch = [kDADiskDescriptionVolumePathKey] as CFArray
        DARegisterDiskDescriptionChangedCallback(session, nil, watch,
            callback, Unmanaged.passUnretained(shared).toOpaque())
        DASessionSetDispatchQueue(session, DispatchQueue(label: "com.saslu.ntfssilicon.notifier"))
    }

    private func event(for disk: DADisk) {
        // Watching VolumePath: a CFURL appears on mount, vanishes (NSNull)
        // on unmount. Registration is silent about already-mounted volumes.
        guard let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return }
        let mountedNow = description[kDADiskDescriptionVolumePathKey] != nil
            && !(description[kDADiskDescriptionVolumePathKey] is NSNull)
        let name = (description[kDADiskDescriptionVolumeNameKey] as? String) ?? "A volume"
        let kind = mountedNow ? "mount" : "unmount"
        let key = mountedNow ? "notify.mount" : "notify.unmount"
        DispatchQueue.main.async {
            guard UserDefaults.standard.bool(forKey: key) else { return }
            let content = UNMutableNotificationContent()
            content.title = "NTFSSilicon"
            content.body = mountedNow ? "\(name) mounted." : "\(name) unmounted."
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(kind)-\(UUID().uuidString)",
                                      content: content, trigger: nil))
        }
    }
}
