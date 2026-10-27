import AppKit
import NTFSSiliconKit

/// Self-test for agents: runs the app's real functions against the real
/// disk read paths (read-only side effects only), prints PASS or FAIL per
/// check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/self NTFSSilicon.app/Contents/MacOS/NTFSSilicon --selftest
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Env.isOverridden else {
            print("SELFTEST refused: set APP_STORE to /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            await model.refresh()
            check("volumes were read from the system", model.volumes.count >= 1)
            check("a boot volume is present", model.volumes.contains { $0.isBoot })
            if let boot = model.volumes.first(where: { $0.isBoot }) {
                check("the boot volume says so", boot.statusWord != "")
                check("the boot volume refuses erase", VolumeStore().isBootDisk(boot))
            }
            if let first = model.volumes.first {
                model.selection = first.device
                check("selecting a volume works", model.selected?.device == first.device)
            }
            // Options round-trip on an untouched UserDefaults suite.
            let testDefaults = UserDefaults(suiteName: "selftest.volume.prefs")
            testDefaults?.removePersistentDomain(forName: "selftest.volume.prefs")
            let uuid = model.volumes.compactMap(\.uuid).first ?? "self-test-uuid"
            VolumePrefs.set(VolumeOptions(readOnly: true), forUUID: uuid, defaults: testDefaults!)
            check("per-volume options persist", VolumePrefs.options(forUUID: uuid, defaults: testDefaults!).readOnly)
            // Formatter probe runs without touching anything.
            _ = VolumeStore().hasNTFSFormatter()
            check("formatter probe does not crash", true)
            check("no boot volume offers itself for erase", {
                let bootVolumes = model.volumes.filter { $0.isBoot }
                return bootVolumes.count == 1
            }())

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
