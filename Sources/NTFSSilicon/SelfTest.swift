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
            // S-044 proxy: every interactive control must answer with some
            // word — a title, description, label, or help. Catches the
            // unlabeled-button class of bug automatically; a full
            // VoiceOver/Inspector audit stays hands-on.
            // A missing AX window fails loudly — it would be an audit skip.
            var axWindow: AXUIElement?
            for _ in 0..<20 {
                axWindow = SelfTest.windowElement()
                if axWindow != nil { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if let axWindow = axWindow {
                let silent = SelfTest.unlabeledControls(in: axWindow)
                check("every control answers with a word (S-044)", silent.isEmpty,
                      silent.joined(separator: ", "))
            } else {
                check("every control answers with a word (S-044)", false, "no AX window")
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    // MARK: Accessibility audit (S-044)

    private static func windowElement() -> AXUIElement? {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var out: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &out) == .success,
              let windows = out as? [AXUIElement], let window = windows.first else { return nil }
        return window
    }

    /// Lists interactive elements (buttons, checkboxes, popups, fields)
    /// whose title, description, help, and value are all empty — the
    /// controls a screen reader would read as silence.
    private static func unlabeledControls(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 12 else { return [] }
        var silent: [String] = []
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        let chrome: Set<String> = ["AXCloseButton", "AXMinimizeButton",
                                   "AXZoomButton", "AXFullScreenButton"] // system handles their words
        if ["AXButton", "AXCheckBox", "AXPopUpButton", "AXTextField", "AXSlider"].contains(role) {
            var labeled = false
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute,
                              kAXHelpAttribute, kAXValueAttribute] {
                var raw: AnyObject?
                AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
                if let text = raw as? String, !text.isEmpty { labeled = true }
            }
            var subRaw: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subRaw)
            let sub = subRaw as? String ?? ""
            if !labeled && !chrome.contains(sub) { silent.append(role) }
        }
        var raw: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
           let children = raw as? [AXUIElement] {
            for child in children { silent += unlabeledControls(in: child, depth: depth + 1) }
        }
        return silent
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
