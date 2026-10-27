import SwiftUI
import NTFSSiliconKit

/// The status-bar volume menu (S-021): every volume with a capacity bar
/// and quick actions, straight from the same AppModel as the window.
struct VolumeMenu: Scene {
    var body: some Scene {
        MenuBarExtra("Volumes", systemImage: "internaldrive.fill") {
            VolumeMenuPanel()
        }
        .menuBarExtraStyle(.window)
    }
}

struct VolumeMenuPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.xs) {
                Image(systemName: "internaldrive.fill")
                Text("NTFS-Silicon")
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Rescan volumes")
            }
            .padding(Space.sm)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.volumes) { volume in
                        VolumeMenuRow(volume: volume)
                    }
                    if model.volumes.isEmpty {
                        Text("No volumes")
                            .foregroundStyle(.secondary)
                            .padding(Space.md)
                    }
                }
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 380)
        .task { await model.refresh() }
        .alert("Volume", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}

struct VolumeMenuRow: View {
    @Environment(AppModel.self) private var model
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: Space.sm) {
            Dot(status: volume.statusWord)
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(volume.name)
                    Spacer()
                    Text(volume.mountPoint != nil ? "\(VolumeRow.size(volume.freeBytes)) Free" : "Unmounted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let total = volume.totalBytes, let free = volume.freeBytes, total > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(.tint)
                                .frame(width: max(4, geo.size.width * CGFloat(Double(total - free) / Double(total))))
                        }
                    }
                    .frame(height: 6)
                }
            }
            if volume.isMounted && !volume.isBoot {
                Button {
                    Task { await model.act("Ejecting \(volume.name)…") { await $0.eject(volume) } }
                } label: {
                    Image(systemName: "eject")
                }
                .buttonStyle(.plain)
                .help("Eject \(volume.name)")
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
        .contextMenu {
            if volume.isMounted {
                Button("Unmount") { Task { await model.unmountTarget(volume) } }
            } else {
                Button("Mount") { Task { await model.mountTarget(volume) } }
            }
            Button("Eject…") { Task { await model.act("Ejecting \(volume.name)…") { await $0.eject(volume) } } }
            Divider()
            Button("Open NTFS-Silicon") {
                NSApp.activate()
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension AppModel {
    @MainActor
    func mountTarget(_ volume: VolumeInfo) async {
        await act("Mounting \(volume.name)…") { await $0.mount(volume) }
    }

    @MainActor
    func unmountTarget(_ volume: VolumeInfo) async {
        await act("Unmounting \(volume.name)…") { await $0.unmount(volume) }
    }
}
