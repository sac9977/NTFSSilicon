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

struct GeneralSettings: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Section("Startup") {
            Toggle("Launch on system startup", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    enabled ? try? SMAppService.mainApp.register()
                            : try? SMAppService.mainApp.unregister()
                }
        }
    }
}

/// (Launch-at-login writes straight to SMAppService from the toggle's
/// onChange; the registry state is read by the system at startup.)
