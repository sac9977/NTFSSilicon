import DiskArbitration
import Foundation

/// Blocks the mount of volumes whose prefs say "do not mount automatically".
/// DiskArbitration consults registered sessions before any volume mounts;
/// returning a dissenter vetoes the mount, returning nil approves. Only
/// active while the app runs — when the app is not running, macOS mounts
/// normally (shortcut: no root fstab veto inside a sandboxed app; a
/// privileged helper would be the only stronger option).
/// Our own explicit Mount wraps its work in `allowing`, so a user who asks
/// for the volume in the app gets it.
public final class MountVeto: @unchecked Sendable {
    public static let shared = MountVeto()
    private var session: DASession?
    private var started = false
    /// One flag for the whole app: explicit mounts are single verbs, we do
    /// not nest them, so a plain boolean is enough (no lock; a DA callback
    /// racing a write costs at most one extra allowed mount).
    nonisolated(unsafe) package static var suppress = false

    private init() {}

    public static func start() {
        guard !shared.started else { return }
        shared.started = true
        guard let session = DASessionCreate(kCFAllocatorDefault) as DASession? else { return }
        shared.session = session
        // nil return approves the mount; a dissenter blocks it.
        let callback: DADiskMountApprovalCallback = { disk, context in
            guard let context else { return nil }
            return Unmanaged<MountVeto>.fromOpaque(context).takeUnretainedValue().dissent(for: disk)
        }
        DARegisterDiskMountApprovalCallback(session, nil, callback,
                                           Unmanaged.passUnretained(shared).toOpaque())
        DASessionSetDispatchQueue(session, DispatchQueue(label: "com.saslu.ntfssilicon.mount-veto"))
    }

    /// Wraps an explicit mount so the veto stays out of its way.
    @MainActor
    public static func allowing<T>(_ body: () async throws -> T) async rethrows -> T {
        suppress = true
        defer { suppress = false }
        return try await body()
    }

    private func dissent(for disk: DADisk) -> Unmanaged<DADissenter>? {
        if Self.suppress { return nil }
        guard let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return nil }
        // The volume UUID arrives as CFUUID in current systems, a CFString
        // elsewhere; accept both. Prefs are keyed like the app's VolumePrefs.
        let uuid: String?
        if let raw = description[kDADiskDescriptionVolumeUUIDKey] {
            if CFGetTypeID(raw as CFTypeRef) == CFUUIDGetTypeID() {
                uuid = (CFUUIDCreateString(kCFAllocatorDefault, (raw as! CFUUID)) as String)
            } else {
                uuid = raw as? String
            }
        } else {
            uuid = nil
        }
        guard let uuid, VolumePrefs.options(forUUID: uuid.uppercased()).noAutoMount else { return nil }
        let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnExclusiveAccess),
                                          "NTFSSilicon: do not mount automatically" as CFString)
        return Unmanaged.passRetained(dissenter)
    }
}
