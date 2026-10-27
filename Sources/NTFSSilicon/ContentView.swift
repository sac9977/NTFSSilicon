import AppKit
import SwiftUI
import NTFSSiliconKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            List(model.volumes, selection: selection) { volume in
                VolumeRow(volume: volume, options: model.options(for: volume))
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .overlay {
                if !model.loaded {
                    ProgressView("Reading volumes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.volumes.isEmpty {
                    ContentUnavailableView("No volumes", systemImage: "internaldrive",
                        description: Text("Rescan — or grant the app disk access in System Settings."))
                }
            }
        } detail: {
            if let volume = model.selected {
                VolumeDetail(volume: volume)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right")
            }
        }
        .task {
            await model.refresh()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selection },
            set: { model.selection = $0 }
        )
    }
}

/// One sidebar row: status dot (with a word for accessibility), name,
/// size, and a chip for the non-obvious states.
struct VolumeRow: View {
    let volume: VolumeInfo
    let options: VolumeOptions

    var body: some View {
        HStack(spacing: Space.sm) {
            Dot(status: volume.statusWord)
            Label(volume.name, systemImage: "internaldrive")
            Spacer()
            Text(Self.size(volume.totalBytes))
                .font(.callout)
                .foregroundStyle(.secondary)
            if volume.isReadOnly {
                chip("read-only")
            } else if volume.isHidden {
                chip("nobrowse")
            }
        }
        .help("\(volume.name), \(volume.statusWord)\(volume.totalBytes.map { ", \(Self.size($0))" } ?? "")")
    }

    private func chip(_ word: String) -> some View {
        Text(word)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// The status dot: green Ready, orange Read-only, gray Unmounted. The
/// dot never stands alone — the detail pane and the tooltip say the word.
struct Dot: View {
    let status: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8) // grid: ok
            .accessibilityLabel(status)
    }

    private var color: Color {
        switch status {
        case "Ready": .green
        case "Read-only": .orange
        default: .secondary.opacity(0.5)
        }
    }
}

struct VolumeDetail: View {
    @Environment(AppModel.self) private var model
    let volume: VolumeInfo
    @State private var editableName: String = ""
    @State private var showingErase = false
    @State private var verifying = false
    @State private var verifyResult: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: Space.md) {
                    Image(systemName: "internaldrive")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    TextField("Name", text: $editableName, onCommit: commitRename)
                        .labelsHidden()
                        .onKeyPress(.escape) {
                            editableName = volume.name // cancel, like the reference's pencil
                            return .handled
                        }
                    HStack(spacing: Space.xs) {
                        Dot(status: volume.statusWord)
                        Text(volume.statusWord)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            storage
            Section("Information") {
                LabeledContent("Mounted") {
                    if let mount = volume.mountPoint {
                        Text("Yes").padding(.trailing, Space.sm)
                        Button(mount) {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mount)
                        }
                        .buttonStyle(.link)
                        .help("Reveal in Finder")
                    } else {
                        Text("No")
                    }
                }
                LabeledContent("Device", value: "/dev/\(volume.device)")
                LabeledContent("File System", value: volume.filesystem)
                if volume.isBoot {
                    LabeledContent("Operating System", value: ProcessInfo.processInfo.operatingSystemVersionString)
                }
            }
            Section("Options") {
                if !volume.isReadOnly { // read-only media can never be indexed (S-011)
                    Toggle("Enable Spotlight Indexing", isOn: spotlightBinding)
                        .disabled(!volume.isMounted)
                    Toggle("Mount in Read-only mode", isOn: boolBinding(\.readOnly))
                        .disabled(volume.isReadOnly || volume.isBoot)
                    Toggle("Do not mount automatically", isOn: boolBinding(\.noAutoMount))
                        .disabled(volume.isBoot)
                }
            }
            .toggleStyle(.checkbox)
        }
        .formStyle(.grouped)
        .navigationTitle(volume.name)
        .toolbar {
            ToolbarItemGroup {
                if volume.isMounted {
                    Button("Unmount") { Task { await model.unmountSelected() } }
                        .disabled(model.busyLabel != nil)
                        .help("Make this volume invisible without disconnecting (⌘M)")
                } else {
                    Button("Mount") { Task { await model.mountSelected() } }
                        .disabled(model.busyLabel != nil)
                        .help("Make this volume's files visible (⌘M)")
                }
                Button("Verify") {
                    verifying = true
                    Task {
                        let outcome = await model.store.verify(volume)
                        verifyResult = switch outcome {
                        case .passed(let line): line.isEmpty ? "No problems found." : line
                        case .failed(let line): line
                        }
                        verifying = false
                    }
                }
                .disabled(!volume.isMounted || volume.isReadOnly || model.busyLabel != nil)
                .help(volume.isReadOnly
                      ? "Verify is unavailable for read-only media"
                      : "Check the volume's filesystem for errors (⇧⌘V)")
                Button("Erase…") { showingErase = true }
                    .disabled(volume.isBoot || model.busyLabel != nil)
                    .help("Delete all data and create a new filesystem")
                Button {
                    Task { await model.ejectSelected() }
                } label: {
                    Label("Eject", systemImage: "eject")
                }
                .disabled(model.busyLabel != nil)
                .help("Unmount every volume of this disk and disconnect it (⌘E)")
            }
        }
        .sheet(isPresented: $showingErase) {
            EraseSheet(volume: volume)
        }
        .sheet(isPresented: Binding(
            get: { verifying || verifyResult != nil },
            set: { if !$0 { verifyResult = nil } }
        )) {
            VStack(spacing: Space.md) {
                if verifying {
                    ProgressView("Verifying \(volume.name)…")
                } else if let verifyResult {
                    Text(verifyResult.isEmpty ? "No problems found." : verifyResult)
                        .font(.callout)
                    Button("Done") { self.verifyResult = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Space.lg)
            .frame(width: 420)
            .fitsContent()
            .noInitialFocus()
        }
        .task(id: volume.device) {
            editableName = volume.name
            // The system is the truth for Spotlight; store what it says, so
            // the checkbox never lies on next launch (S-011).
            if volume.isMounted, let actual = await model.store.spotlightState(volume) {
                var options = model.options(for: volume)
                if options.spotlight != actual {
                    options.spotlight = actual
                    model.setOptions(options, for: volume)
                }
            }
        }
        .onChange(of: volume.name) { _, newName in editableName = newName }
        .alert("Volume", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }

    // MARK: - Pieces

    private var storage: some View {
        Section("Storage") {
            if let total = volume.totalBytes, let free = volume.freeBytes, total > 0 {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("\(VolumeRow.size(total - free)) used")
                        Spacer()
                        Text("\(VolumeRow.size(free)) free of \(VolumeRow.size(total))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(.tint)
                                .frame(width: max(4, geo.size.width * CGFloat(Double(total - free) / Double(total))))
                        }
                    }
                    .frame(height: 8)
                }
            } else {
                Text("Usage is not available for this volume.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions and bindings

    private func commitRename() {
        let newName = editableName
        guard newName != volume.name else { return }
        Task {
            if let failure = await model.store.rename(volume, to: newName) {
                model.error = failure
                editableName = volume.name
            } else {
                await model.refresh()
            }
        }
    }

    private func boolBinding(_ path: WritableKeyPath<VolumeOptions, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: { model.options(for: volume)[keyPath: path] },
            set: { value in
                var options = model.options(for: volume)
                options[keyPath: path] = value
                model.setOptions(options, for: volume)
            }
        )
    }

    /// Untouched (nil) means "on"; after the user toggles it, the system
    /// result is written back so the checkbox stops lying.
    private var spotlightBinding: Binding<Bool> {
        Binding<Bool>(
            get: { model.options(for: volume).spotlight ?? true },
            set: { value in
                var options = model.options(for: volume)
                options.spotlight = value
                model.setOptions(options, for: volume)
                Task {
                    if let failure = await model.store.setSpotlight(volume, on: value) {
                        model.error = failure
                    }
                    await model.refresh()
                }
            }
        )
    }
}

/// The erase sheet (S-014): names the volume, picks the filesystem,
/// only "Erase" confirms. Progress replaces content while running.
struct EraseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let volume: VolumeInfo

    @State private var format: VolumeStore.EraseFormat
    @State private var name: String
    @State private var running = false
    @State private var failure: String?

    init(volume: VolumeInfo) {
        self.volume = volume
        _name = State(initialValue: volume.name)
        let formats = VolumeStore.availableFormats(hasNTFSFormatter: VolumeStore.ntfsFormatterPath() != nil)
        _format = State(initialValue: formats.first ?? .apfs)
    }

    private var formats: [VolumeStore.EraseFormat] {
        VolumeStore.availableFormats(hasNTFSFormatter: VolumeStore.ntfsFormatterPath() != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if running {
                HStack(spacing: Space.sm) {
                    ProgressView()
                    Text("Erasing \(name)…")
                }
            } else {
                HStack(alignment: .top, spacing: Space.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Are you sure you want to erase volume \(volume.name)?")
                            .font(.headline)
                        Text("Erasing a disk volume deletes all of the data stored on that volume but does not affect other volumes of the same disk. Choose a volume filesystem (format) and enter a name.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Form {
                    Picker("Volume Filesystem (format):", selection: $format) {
                        ForEach(formats, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    TextField("Volume Name:", text: $name)
                    if let failure {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Button("Erase") { Task { await run() } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .padding(Space.lg)
        .frame(width: 440)
        .noInitialFocus()
    }

    private func run() async {
        running = true
        defer { running = false }
        if let runFailure = await model.store.erase(volume, as: format, name: name) {
            failure = runFailure
        } else {
            await model.refresh()
            dismiss()
        }
    }
}
