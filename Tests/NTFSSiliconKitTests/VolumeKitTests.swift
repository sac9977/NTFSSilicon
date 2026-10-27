import Testing
import Foundation
@testable import NTFSSiliconKit

// Fixtures captured from real `diskutil` output shapes (shortened).
let listPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AllDisksAndPartitions</key>
  <array>
    <dict>
      <key>DeviceIdentifier</key><string>disk3</string>
      <key>APFSVolumes</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk3s1s1</string>
          <key>VolumeName</key><string>Macintosh HD</string>
          <key>MountPoint</key><string>/</string>
          <key>FilesystemType</key><string>APFS</string>
        </dict>
      </array>
    </dict>
    <dict>
      <key>DeviceIdentifier</key><string>disk6</string>
      <key>Partitions</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk6s1</string>
          <key>VolumeName</key><string>SageSSD</string>
          <key>FilesystemName</key><string>hfs</string>
          <key>VolumeSize</key><integer>2000000000</integer>
        </dict>
        <dict>
          <key>DeviceIdentifier</key><string>disk6s4</string>
          <key>VolumeName</key><string>windows</string>
          <key>FilesystemName</key><string>exfat</string>
          <key>MountPoint</key><string>/Volumes/windows</string>
        </dict>
        <dict>
          <key>DeviceIdentifier</key><string>disk6s2</string>
        </dict>
      </array>
    </dict>
  </array>
</dict>
</plist>
"""

let infoPlistForWindows = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DeviceIdentifier</key><string>disk6s4</string>
  <key>VolumeName</key><string>windows</string>
  <key>MountPoint</key><string>/Volumes/windows</string>
  <key>FilesystemType</key><string>ExFAT</string>
  <key>FilesystemName</key><string>MS-DOS (EXFAT)</string>
  <key>TotalSize</key><integer>300000000000</integer>
  <key>FreeSpace</key><integer>140000000000</integer>
  <key>VolumeUUID</key><string>3333-4444-BEEF-4242</string>
</dict>
</plist>
"""

let mountOutput = """
/dev/disk3s1s1 on / (apfs, local, journaled, nobrowse)
/dev/disk6s4 on /Volumes/windows (exfat, local, noowners)
"""

@Test("diskutil list yields volume partitions, skipping unnamed gadgets")
func partitions() throws {
    let parts = try VolumeParse.partitions(fromDiskutilList: Data(listPlist.utf8))
    #expect(parts.map(\.device) == ["disk3s1s1", "disk6s1", "disk6s4"])
    #expect(parts[0].name == "Macintosh HD")
    #expect(parts[2].fs == "exfat")
}

@Test("info plist builds one volume with sane fields")
func info() throws {
    var roots = Set<String>()
    let flags = VolumeParse.mountFlags(from: mountOutput, roots: &roots)
    let volume = try VolumeParse.volume(fromDiskutilInfo: Data(infoPlistForWindows.utf8),
                                        flags: flags["disk6s4"] ?? [],
                                        bootDevices: roots)
    #expect(volume?.name == "windows")
    #expect(volume?.mountPoint == "/Volumes/windows")
    #expect(volume?.totalBytes == 300_000_000_000)
    #expect(volume?.uuid == "3333-4444-BEEF-4242")
    #expect(volume?.isBoot == false)
    #expect(volume?.wholeDisk == "disk6")
    #expect(volume?.statusWord == "Ready")
}

@Test("boot volume and read-only flag come from mount output")
func bootAndFlags() throws {
    var roots = Set<String>()
    let flags = VolumeParse.mountFlags(from: mountOutput, roots: &roots)
    #expect(roots.contains("disk3s1s1"))
    let volume = try VolumeParse.volume(fromDiskutilInfo: Data(infoPlistForWindows.utf8),
                                        flags: flags["disk6s4"] ?? [],
                                        bootDevices: roots)
    #expect(volume?.isReadOnly == false)
    #expect(volume?.isHidden == false)
}

@Test("mount flags: read-only and nobrowse are words")
func flagsWords() {
    var roots = Set<String>()
    let flags = VolumeParse.mountFlags(
        from: "/dev/disk8s1 on /Library/Developer/CoreSimulator (apfs, local, nobrowse, read-only)",
        roots: &roots)
    #expect(flags["disk8s1"]?.contains("read-only") == true)
    #expect(flags["disk8s1"]?.contains("nobrowse") == true)
}

@Test("per-volume options round-trip and are isolated per volume")
func prefs() {
    let suite = UserDefaults(suiteName: "test.volume.prefs")!
    suite.removePersistentDomain(forName: "test.volume.prefs")
    let uuid = "ABC-123"
    var options = VolumePrefs.options(forUUID: uuid, defaults: suite)
    #expect(options == VolumeOptions())
    options.readOnly = true
    options.noAutoMount = true
    VolumePrefs.set(options, forUUID: uuid, defaults: suite)
    #expect(VolumePrefs.options(forUUID: uuid, defaults: suite) == options)
    #expect(VolumePrefs.options(forUUID: "other", defaults: suite) == VolumeOptions())
}

@Test("format list gates Microsoft NTFS on an installed formatter")
func formats() {
    #expect(VolumeStore.availableFormats(hasNTFSFormatter: false).contains(.exfat))
    #expect(!VolumeStore.availableFormats(hasNTFSFormatter: false).contains(.ntfs))
    #expect(VolumeStore.availableFormats(hasNTFSFormatter: true).contains(.ntfs))
    #expect(VolumeStore.EraseFormat.ntfs.diskutilType == nil)
}

@Test("system helper volumes are marked, user disks with nobrowse are not")
func systemFilter() {
    var roots = Set<String>()
    let flags = VolumeParse.mountFlags(from: mountOutput, roots: &roots)

    func vol(_ name: String, mount: String?) -> VolumeInfo? {
        let mountXML = mount.map { "<key>MountPoint</key><string>\($0)</string>" } ?? ""
        let plist = """
        <plist><dict>
        <key>DeviceIdentifier</key><string>disk9s1</string>
        <key>VolumeName</key><string>\(name)</string>
        \(mountXML)
        <key>FilesystemType</key><string>APFS</string>
        </dict></plist>
        """
        return try? VolumeParse.volume(fromDiskutilInfo: Data(plist.utf8), flags: flags["disk9s1"] ?? [], bootDevices: roots)
    }

    #expect(vol("Preboot", mount: nil)?.isSystemInternal == true)
    #expect(vol("VM", mount: "/System/Volumes/VM")?.isSystemInternal == true)
    #expect(vol("Macintosh HD", mount: "/System/Volumes/Data")?.isSystemInternal == true)
    #expect(vol("windows", mount: "/Volumes/windows")?.isSystemInternal == false)
    // A nobrowse user disk (disk image) stays visible.
    var imageFlags = flags["disk9s1"] ?? []
    imageFlags.append("nobrowse")
    let image = try? VolumeParse.volume(fromDiskutilInfo: Data("""
        <plist><dict>
        <key>DeviceIdentifier</key><string>disk9s1</string>
        <key>VolumeName</key><string>Backup Image</string>
        <key>MountPoint</key><string>/Volumes/Backup Image</string>
        <key>FilesystemType</key><string>hfs</string>
        </dict></plist>
        """.utf8), flags: imageFlags, bootDevices: roots)
    #expect(image?.isSystemInternal == false)
}

@Test("sealed-system twins collapse to the mounted volume")
func twins() {
    func make(_ device: String, name: String = "Macintosh HD", mounted: Bool) -> VolumeInfo {
        VolumeInfo(device: device, name: name, mountPoint: mounted ? "/" : nil,
                   filesystem: "APFS", totalBytes: 1000, freeBytes: 500, uuid: nil,
                   isReadOnly: mounted, isHidden: false, isBoot: mounted, wholeDisk: "disk3")
    }
    let unmountedFirst = VolumeStore.dedupTwins([make("disk3s1", mounted: false), make("disk3s1s1", mounted: true)])
    #expect(unmountedFirst.count == 1)
    #expect(unmountedFirst.first?.device == "disk3s1s1")
    let mountedFirst = VolumeStore.dedupTwins([make("disk3s1s1", mounted: true), make("disk3s1", mounted: false)])
    #expect(mountedFirst.count == 1)
    // Two different volumes on one disk with different names stay.
    let windows = make("disk6s4", name: "windows", mounted: true)
    let sage = VolumeInfo(device: "disk6s1", name: "SageSSD", mountPoint: "/Volumes/SageSSD",
                          filesystem: "hfs", totalBytes: 1000, freeBytes: 500, uuid: nil,
                          isReadOnly: false, isHidden: false, isBoot: false, wholeDisk: "disk6")
    let different = VolumeStore.dedupTwins([sage, windows])
    #expect(different.count == 2)
}

@Test("snapshot device disk3s1s1 lands on wholeDisk disk3, so twins dedup")
func snapshotWholeDisk() {
    var roots = Set<String>()
    let flags = VolumeParse.mountFlags(from: mountOutput, roots: &roots)
    let plist = """
    <plist><dict>
    <key>DeviceIdentifier</key><string>disk3s1s1</string>
    <key>VolumeName</key><string>Macintosh HD</string>
    <key>MountPoint</key><string>/</string>
    <key>FilesystemType</key><string>APFS</string>
    </dict></plist>
    """
    let volume = try? VolumeParse.volume(fromDiskutilInfo: Data(plist.utf8),
                                         flags: flags["disk3s1s1"] ?? [], bootDevices: roots)
    #expect(volume?.wholeDisk == "disk3")
    #expect(volume?.isBoot == true)
}
