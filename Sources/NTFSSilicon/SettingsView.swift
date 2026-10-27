import SwiftUI
import ServiceManagement

/// The Settings window (⌘,). Two tabs: General (behaviors and hooks) and
/// Appearance (accent color). Both are grouped Forms that size to content.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

/// General settings (S-031-lite, S-032, S-034). The reference's dirty-volume
/// and hibernated-Windows dicts are dropped: they only matter when a
/// proprietary NTFS driver answers the mount; `diskutil`'s standard mount
/// covers the sane paths. What is kept and enforced: verify-before-mount.
struct GeneralSettings: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("mount.verifyFirst") private var verifyBeforeMount = false
    @AppStorage("notify.mount") private var notifyMount = false
    @AppStorage("notify.unmount") private var notifyUnmount = false

    var body: some View {
        Section("Startup") {
            Toggle("Launch on system startup", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    let service = SMAppService.mainApp
                    // Guard against the programmatic set below — only act on
                    // a real change, so the system stays the source of truth.
                    if enabled && service.status != .enabled { try? service.register() }
                    if !enabled && service.status == .enabled { try? service.unregister() }
                }
        }
        Section("Mounting") {
            Picker("When mounting:", selection: $verifyBeforeMount) {
                Text("Standard").tag(false)
                Text("Verify before mount").tag(true)
            }
            .help("Check the volume for filesystem errors before polishing it in")
        }
        Section("Alerts") {
            Toggle("When a volume is mounted", isOn: $notifyMount)
                .onChange(of: notifyMount) { _, on in Notifier.enabled(on) }
            Toggle("When a volume is unmounted", isOn: $notifyUnmount)
                .onChange(of: notifyUnmount) { _, on in Notifier.enabled(on) }
        }
        .onAppear {
            // The system is the truth for launch-at-login (S-034); a stale
            // @AppStorage flag would lie after the user changed it elsewhere.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// (Launch-at-login writes straight to SMAppService; the toggle state is
/// re-read from `SMAppService.mainApp.status` every time Settings opens.)
