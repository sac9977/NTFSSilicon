import Foundation

/// Runs `diskutil` and friends. All side effects live here, so views just
/// pick a volume and a verb.
public final class VolumeStore: Sendable {
    public init() {}

    let diskutil = "/usr/sbin/diskutil"

    // MARK: - Reading

    /// Lists every volume the system knows. Boot volume first, then by name.
    public func refresh() async throws -> [VolumeInfo] {
        let (listCode, listOut) = await runTool(diskutil, ["list", "-plist"])
        guard listCode == 0 else { throw VolumeParse.ParseError.unexpectedShape }
        let partitions = try VolumeParse.partitions(fromDiskutilList: Data(listOut.utf8))
        let (_, mountOut) = await runTool("/sbin/mount", [])
        var roots = Set<String>()
        let flags = VolumeParse.mountFlags(from: mountOut, roots: &roots)

        var volumes: [VolumeInfo] = []
        let found = await withTaskGroup(of: VolumeInfo?.self) { group in
            for entry in partitions {
                // Copy the Sendable state into lets, so the child task is
                // clean: it sees only values, not a mutable region.
                let diskutilPath = diskutil
                let deviceFlags = flags[entry.device] ?? []
                let bootDevices = roots
                group.addTask {
                    let (code, out) = await self.runTool(diskutilPath, ["info", "-plist", entry.device])
                    guard code == 0,
                          let volume = try? VolumeParse.volume(fromDiskutilInfo: Data(out.utf8),
                                                               flags: deviceFlags,
                                                               bootDevices: bootDevices) else { return nil }
                    return volume
                }
            }
            var results: [VolumeInfo] = []
            for await volume in group {
                if let volume { results.append(volume) }
            }
            return results
        }
        volumes.append(contentsOf: found)
        volumes.sort { a, b in
            if a.isBoot != b.isBoot { return a.isBoot }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        var seen = Set<String>()
        let unique = volumes
            .filter { seen.insert($0.device).inserted }
            .filter { !$0.isSystemInternal }
        return Self.dedupTwins(unique)
    }

    /// Same name on the same disk means the sealed-system twins
    /// ("Macintosh HD" + its mounted snapshot); keep the mounted one.
    public static func dedupTwins(_ volumes: [VolumeInfo]) -> [VolumeInfo] {
        var best: [String: VolumeInfo] = [:]
        var order: [String] = []
        for volume in volumes {
            let key = volume.wholeDisk + "/" + volume.name
            if let current = best[key] {
                best[key] = current.isMounted ? current : volume
            } else {
                best[key] = volume
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    // MARK: - Actions

    public func mount(_ volume: VolumeInfo, readOnly: Bool = false) async -> String? {
        var arguments = ["mount"]
        if readOnly { arguments.append("readOnly") } // native: `diskutil mount readOnly`
        arguments.append(volume.device)
        let (code, out) = await runTool(diskutil, arguments)
        return code == 0 ? nil : errorMessage(out, verb: "mount")
    }

    public func unmount(_ volume: VolumeInfo) async -> String? {
        let (code, out) = await runTool(diskutil, ["unmount", volume.device])
        return code == 0 ? nil : errorMessage(out, verb: "unmount")
    }

    public func eject(_ volume: VolumeInfo) async -> String? {
        guard !isBootDisk(volume) else { return "The boot disk can't be ejected." }
        let (code, out) = await runTool(diskutil, ["eject", volume.wholeDisk])
        return code == 0 ? nil : errorMessage(out, verb: "eject")
    }

    public func rename(_ volume: VolumeInfo, to newName: String) async -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return "Volume names can be 1–40 characters, no control characters."
        }
        let (code, out) = await runTool(diskutil, ["rename", volume.device, trimmed])
        return code == 0 ? nil : errorMessage(out, verb: "rename")
    }

    public enum VerifyOutcome { case passed(String); case failed(String) }

    public func verify(_ volume: VolumeInfo) async -> VerifyOutcome {
        let (code, out) = await runTool(diskutil, ["verifyVolume", volume.device])
        return code == 0 ? .passed(tail(out)) : .failed(tail(out))
    }

    // MARK: - Formats

    public enum EraseFormat: String, CaseIterable, Sendable, Hashable {
        case apfs = "APFS"
        case jhfsPlus = "Mac OS Extended (Journaled)"
        case hfs = "Mac OS Extended"
        case fat32 = "MS-DOS (FAT32)"
        case exfat = "ExFAT"
        case ntfs = "Microsoft NTFS"

        public var diskutilType: String? {
            switch self {
            case .apfs: "APFS"
            case .jhfsPlus: "JHFS+"
            case .hfs: "HFS+"
            case .fat32: "FAT32"
            case .exfat: "ExFAT"
            case .ntfs: nil // needs an installed formatter; see ntfsFormatterPath()
            }
        }
    }

    /// Formats to offer: NTFS only when a third-party formatter is installed.
    public static func availableFormats(hasNTFSFormatter: Bool) -> [EraseFormat] {
        EraseFormat.allCases.filter { format in format != .ntfs || hasNTFSFormatter }
    }

    /// True when an NTFS formatter exists under /Library/Filesystems
    /// (Paragon, Tuxera, …). Never hardcoded to one vendor.
    public func hasNTFSFormatter() -> Bool { Self.ntfsFormatterPath() != nil }

    public static func ntfsFormatterPath() -> String? {
        findExecutable(named: "newfs_ufsd_NTFS")
    }

    /// Erases and returns nil on success, else the reason.
    public func erase(_ volume: VolumeInfo, as format: EraseFormat, name newName: String) async -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return "Volume names can be 1–40 characters, no control characters."
        }
        guard !isBootDisk(volume) else { return "The boot volume can't be erased." }
        if let type = format.diskutilType {
            let (code, out) = await runTool(diskutil, ["eraseVolume", type, trimmed, volume.device])
            return code == 0 ? nil : errorMessage(out, verb: "erase")
        }
        // NTFS through an installed third-party formatter.
        guard let formatter = Self.ntfsFormatterPath() else {
            return "No NTFS formatter is installed."
        }
        if let unmountError = await unmount(volume) { return unmountError }
        // The formatter asks "Proceed with Format (y/n)?" before doing
        // anything, and aborts silently with exit 0 on EOF — answer yes.
        let (code, out) = await runTool(formatter, ["-v", trimmed, "/dev/\(volume.device)"], stdin: "y\n")
        return code == 0 ? nil : errorMessage(out, verb: "erase")
    }

    public func setSpotlight(_ volume: VolumeInfo, on: Bool) async -> String? {
        guard let mountPoint = volume.mountPoint else { return "The volume is not mounted." }
        let (code, out) = await runTool("/usr/sbin/mdutil", ["-i", on ? "on" : "off", mountPoint])
        return code == 0 ? nil : errorMessage(out, verb: "set Spotlight indexing")
    }

    /// The system's actual Spotlight state for a mounted volume, parsed
    /// from `mdutil -s`: "Indexing enabled." / "disabled." / "off."
    /// nil when the volume is not mounted or the output makes no sense.
    public func spotlightState(_ volume: VolumeInfo) async -> Bool? {
        guard let mountPoint = volume.mountPoint else { return nil }
        let (_, out) = await runTool("/usr/sbin/mdutil", ["-s", mountPoint])
        return Self.parseSpotlight(out)
    }

    public static func parseSpotlight(_ output: String) -> Bool? {
        let lowered = output.lowercased()
        if lowered.contains("indexing enabled") { return true }
        if lowered.contains("indexing disabled") || lowered.contains("indexing off") { return false }
        return nil
    }

    // MARK: - Internals

    public func isBootDisk(_ volume: VolumeInfo) -> Bool {
        volume.isBoot || volume.mountPoint == "/"
    }

    private func errorMessage(_ out: String, verb: String) -> String {
        let lines = out.trimmedLines
        if let first = lines.first(where: { $0.contains("failed") || $0.lowercased().contains("error") }) {
            return first.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        }
        return "Couldn't \(verb) the volume."
    }

    private func tail(_ out: String) -> String {
        let lines = out.trimmedLines
        return lines.last ?? ""
    }

    /// Runs a tool and returns exit code + combined output. `stdin` feeds the
    /// tool's standard input (the NTFS formatter asks y/n before formatting).
    func runTool(_ path: String, _ arguments: [String], stdin: String? = nil) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                if let stdin {
                    let input = Pipe()
                    process.standardInput = input
                    input.fileHandleForWriting.write(Data(stdin.utf8))
                    input.fileHandleForWriting.closeFile()
                }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                // shortcut: tool output is normally far below the 64 KB pipe
                // buffer; a chatty verify could still deadlock, upgrade to a
                // streaming reader if that shows up.
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                let drained = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (process.terminationStatus, String(decoding: drained, as: UTF8.self)))
            }
        }
    }

    /// Finds an executable by name under /Library/Filesystems, e.g.
    /// ufsd_NTFS.fs/Contents/Resources/newfs_ufsd_NTFS.
    static func findExecutable(named name: String, dir: String = "/Library/Filesystems") -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        for entry in entries {
            let candidate = dir + "/" + entry + "/Contents/Resources/" + name
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

extension String {
    var trimmedLines: [String] {
        split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
