import Foundation

/// One volume as the app shows it. `device` ("disk6s4") is the identity
/// within a session; `uuid` (when the volume has one) keys user prefs
/// across sessions.
public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public var device: String
    public var name: String
    public var mountPoint: String?
    public var filesystem: String
    public var totalBytes: Int64?
    public var freeBytes: Int64?
    public var uuid: String?
    public var isReadOnly: Bool
    public var isHidden: Bool
    public var isBoot: Bool
    public var wholeDisk: String

    public init(device: String, name: String, mountPoint: String?, filesystem: String,
                totalBytes: Int64?, freeBytes: Int64?, uuid: String?, isReadOnly: Bool,
                isHidden: Bool, isBoot: Bool, wholeDisk: String) {
        self.device = device
        self.name = name
        self.mountPoint = mountPoint
        self.filesystem = filesystem
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.uuid = uuid
        self.isReadOnly = isReadOnly
        self.isHidden = isHidden
        self.isBoot = isBoot
        self.wholeDisk = wholeDisk
    }

    public var id: String { device }
    public var isMounted: Bool { mountPoint != nil }

    /// The word that always travels with the status dot (never color alone).
    public var statusWord: String {
        if !isMounted { return "Unmounted" }
        if isReadOnly { return "Read-only" }
        return "Ready"
    }

    public static var bootVolumeMarkers: Set<String> { ["/", "/System/Volumes/Data"] }

    /// Internal system helper volumes no person manages from a volume
    /// manager: the APFS role partitions and the Data twin of the boot
    /// disk. Real removable disks with nobrowse (e.g. a DVD image) stay.
    public var isSystemInternal: Bool {
        let helpers: Set<String> = ["Preboot", "Update", "VM", "Hardware", "iSCPreboot", "Recovery"]
        if helpers.contains(name) { return true }
        if let mount = mountPoint {
            if mount == "/System/Volumes/Data" { return true } // boot disk's Data twin
            if mount.hasPrefix("/System/Volumes/") { return true }
        }
        return false
    }
}

/// Parsers for `diskutil` plist output and `mount(8)` lines. All throw or
/// return nothing when the system changes its shape — nothing here is
/// allowed to crash the app.
public enum VolumeParse {
    public enum ParseError: Error { case unexpectedShape }

    /// Volume entries from `diskutil list -plist`: device id, name,
    /// filesystem as listed. Partitions without a name or filesystem
    /// (EFI, booters, free space) are skipped.
    public static func partitions(fromDiskutilList data: Data) throws -> [(device: String, name: String?, fs: String?)] {
        guard let top = try propertyList(from: data) as? [String: Any],
              let disks = top["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw ParseError.unexpectedShape
        }
        var out: [(String, String?, String?)] = []
        for disk in disks {
            for key in ["APFSVolumes", "Partitions"] {
                guard let volumes = disk[key] as? [[String: Any]] else { continue }
                for v in volumes {
                    guard let device = v["DeviceIdentifier"] as? String else { continue }
                    let name = v["VolumeName"] as? String
                    let fs = (v["FilesystemName"] as? String) ?? (v["FilesystemType"] as? String)
                    if name == nil && fs == nil { continue }
                    out.append((device, name, fs))
                }
            }
        }
        return out.map { ($0.0, $0.1, $0.2) }
    }

    /// `mount(8)` flag words per device:
    /// "/dev/disk6s4 on /Volumes/windows (exfat, local, nobrowse)".
    public static func mountFlags(from output: String, roots: inout Set<String>) -> [String: [String]] {
        var flags: [String: [String]] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count > 2, parts[0].hasPrefix("/dev/"), parts[1] == "on" else { continue }
            let device = String(parts[0].replacingOccurrences(of: "/dev/", with: ""))
            guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") else { continue }
            let words = line[line.index(after: open)..<close]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            flags[device] = words
            // The mount point sits between "on" and the flags; "/" marks a boot root.
            if let onRange = line.range(of: " on ") {
                let mountPoint = line[onRange.upperBound..<open].trimmingCharacters(in: .whitespaces)
                if mountPoint == "/" { roots.insert(device) }
            }
        }
        return flags
    }

    /// One volume from `diskutil info -plist <device>` plus the flags
    /// seen in `mount` for it. Returns nil for non-volumes (disks, blobs).
    public static func volume(fromDiskutilInfo data: Data, flags: [String], bootDevices: Set<String>) throws -> VolumeInfo? {
        guard let plist = try propertyList(from: data) as? [String: Any],
              let device = plist["DeviceIdentifier"] as? String else { return nil }
        // Whole-disk entries and quanta-like entries have no filesystem.
        let fs = (plist["FilesystemType"] as? String) ?? (plist["FilesystemName"] as? String)
        guard fs != nil || plist["MountPoint"] != nil || plist["VolumeName"] != nil else { return nil }
        let mountPoint = plist["MountPoint"] as? String
        let isBoot = bootDevices.contains(device)
        let readOnly = flags.contains("read-only")
        let name = (plist["VolumeName"] as? String) ?? device
        // Strip every trailing sN segment: disk3s1s1 (the sealed snapshot)
        // and disk3s1 (its base) must land on the same wholeDisk / disk3.
        var whole = device
        while let r = whole.range(of: "s[0-9]+$", options: .regularExpression) {
            let parent = String(whole[whole.startIndex..<r.lowerBound])
            if parent.isEmpty { break }
            whole = parent
        }
        return VolumeInfo(
            device: device,
            name: name,
            mountPoint: mountPoint,
            filesystem: fs ?? "unknown",
            totalBytes: anyInt64(plist, ["TotalSize", "VolumeSize"]),
            freeBytes: anyInt64(plist, ["VolumeFreeSpace", "FreeSpace"]),
            uuid: plist["VolumeUUID"] as? String,
            isReadOnly: readOnly,
            isHidden: flags.contains("nobrowse"),
            isBoot: isBoot,
            wholeDisk: whole
        )
    }

    static func propertyList(from data: Data) throws -> Any {
        if let any = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return any
        }
        if let json = try? JSONSerialization.jsonObject(with: data) { return json }
        throw ParseError.unexpectedShape
    }

    static func anyInt64(_ dict: [String: Any], _ keys: [String]) -> Int64? {
        for key in keys {
            if let n = dict[key] as? Int { return Int64(n) }
            if let n = dict[key] as? Int64 { return n }
            if let n = dict[key] as? NSNumber { return n.int64Value }
        }
        return nil
    }
}
