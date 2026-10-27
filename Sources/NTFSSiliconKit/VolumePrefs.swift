import Foundation

/// Per-volume options the user can set: always read-only mount, never
/// auto-mount, Spotlight indexing. Keyed by volume UUID so it survives
/// renames and re-plugs. Volumes without a UUID get session-only state.
public struct VolumeOptions: Codable, Hashable, Sendable, Equatable {
    public var readOnly: Bool
    public var noAutoMount: Bool
    public var spotlight: Bool?

    public init(readOnly: Bool = false, noAutoMount: Bool = false, spotlight: Bool? = nil) {
        self.readOnly = readOnly
        self.noAutoMount = noAutoMount
        self.spotlight = spotlight
    }
}

public enum VolumePrefs {
    public static func key(forUUID uuid: String) -> String { "volume.options.\(uuid)" }

    public static func options(forUUID uuid: String?, defaults: UserDefaults = .standard) -> VolumeOptions {
        guard let uuid, let data = defaults.data(forKey: key(forUUID: uuid)) else { return VolumeOptions() }
        return (try? JSONDecoder().decode(VolumeOptions.self, from: data)) ?? VolumeOptions()
    }

    public static func set(_ options: VolumeOptions, forUUID uuid: String?, defaults: UserDefaults = .standard) {
        guard let uuid else { return }
        if let data = try? JSONEncoder().encode(options) {
            defaults.set(data, forKey: key(forUUID: uuid))
        }
    }
}
