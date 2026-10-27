import AppKit
import IOKit.pwr_mgt
import NTFSSiliconKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/self APP_SNAPSHOT=/tmp/shots …/NTFSSilicon --…
/// writes volumes-light.png / volumes-dark.png and one pair per Settings
/// tab, plus <page>-<mode>-layout.json grid probes, then quits.
/// APP_SNAPSHOT_PAGES=limits,to,these (default all). APP_ACCENT switches accent.
enum Snapshot {
    /// Six stand-in volumes spanning the states the UI must render: boot
    /// (read-only), mounted NTFS with the detail shown, mounted APFS,
    /// mounted HFS+ with per-volume prefs defaults, unmounted, read-only
    /// media. Only synthetic data ever reaches a screenshot.
    static let fixtureVolumes: [VolumeInfo] = [
        VolumeInfo(device: "disk0s1", name: "Macintosh HD", mountPoint: "/",
                   filesystem: "APFS", totalBytes: 994_663_587_840, freeBytes: 41_000_000_000,
                   uuid: "0000-BOOT-0000", isReadOnly: true, isHidden: false, isBoot: true,
                   wholeDisk: "disk0"),
        VolumeInfo(device: "disk3s2", name: "Sandbox", mountPoint: "/Volumes/Sandbox",
                   filesystem: "NTFS", totalBytes: 2_000_247_524_352, freeBytes: 512_000_000_000,
                   uuid: "0000-SNDB-0000", isReadOnly: false, isHidden: false, isBoot: false,
                   wholeDisk: "disk3"),
        VolumeInfo(device: "disk1s1", name: "Work", mountPoint: "/Volumes/Work",
                   filesystem: "APFS", totalBytes: 1_000_000_000_000, freeBytes: 250_000_000_000,
                   uuid: "0000-WRK0-0000", isReadOnly: false, isHidden: false, isBoot: false,
                   wholeDisk: "disk1"),
        VolumeInfo(device: "disk2s2", name: "Archive", mountPoint: "/Volumes/Archive",
                   filesystem: "Mac OS Extended (Journaled)", totalBytes: 701_800_000_000,
                   freeBytes: 700_100_000_000, uuid: "0000-ARCH-0000", isReadOnly: false,
                   isHidden: false, isBoot: false, wholeDisk: "disk2"),
        VolumeInfo(device: "disk4s1", name: "Installers", mountPoint: nil,
                   filesystem: "exFAT", totalBytes: 128_000_000_000, freeBytes: nil,
                   uuid: "0000-INST-0000", isReadOnly: false, isHidden: true, isBoot: false,
                   wholeDisk: "disk4"),
        VolumeInfo(device: "disk5s1", name: "Sim Images", mountPoint: "/Volumes/Sim Images",
                   filesystem: "ISO 9660", totalBytes: 8_000_000_000, freeBytes: 0,
                   uuid: nil, isReadOnly: true, isHidden: true, isBoot: false,
                   wholeDisk: "disk5"),
    ]

    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real store's write paths.
        guard Env.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to /tmp")
            NSApp.terminate(nil)
            return
        }
        let pages = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        let windowPages = ["volumes"].filter { pages?.contains($0) ?? true }
        Task {
            // A sleeping display gives screencapture nothing.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            await model.refresh()
            // Privacy: publish no real volume names, sizes or devices —
            // rendering uses a fixed fixture from here on.
            model.volumes = Self.fixtureVolumes
            // Select a non-boot volume, so the detail pane is interesting.
            if let detail = model.volumes.first(where: { !$0.isBoot }) { model.selection = detail.device }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in windowPages {
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page)-\(mode).png")
                }
            }
            if pages == nil || pages!.contains("settings") {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture; falls back to drawing
    /// the view hierarchy without Screen Recording permission.
    private static func capture(to path: String, window: NSWindow? = nil) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
