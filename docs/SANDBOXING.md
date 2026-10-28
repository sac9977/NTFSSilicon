# Sandboxing map for an App Store release

Verified on this machine (2026-10-28): under a deny-default seatbelt
(`sandbox-exec`), `diskutil list` — the read path — already fails:
"Unable to use the DiskManagement framework." Everything below anchors
on that. The definitive test is still a real `App Sandbox` entitlement
build; this map decides *what to test*, not just guesswork.

## Verdict table

| Feature | How it works today | Under App Sandbox |
|---|---|---|
| List volumes | `diskutil list` + parsers | **Rebuild**: observe via DiskArbitration (`DARegisterDiskAppearedCallback` family) — reads are sandbox-safe; parse the DA description instead of diskutil text |
| Detail pane (device, fs, size) | same diskutil output | **Rebuild** from DA description + Apple frameworks (URL volumeResourceValues for capacity) |
| Mount | `diskutil mount [readOnly]` | **Blocked**: arbitrary mount is a system-level operation; there is no MAS entitlement.MAS edition could handle *user-chosen images* via `NSWorkspace.open` (Finder-mediated, UI-confirmed) only — no arbitrary-volume mount |
| Unmount | `diskutil unmount` | **Mediated**: `NSWorkspace.unmountAndEjectDevice(at:)` is the supported path (system-owned dialog), device-wide only — per-volume unmount goes away |
| Eject | `diskutil eject` | **Mediated** via the same NSWorkspace call — likely the strongest surviving action |
| Verify / erase (incl. NTFS formatter) | child processes (`diskutil verifyVolume`, `newfs_ufsd_NTFS`) | **Drop from MAS build**: erase requires DiskManagement + root; verify same; formatter spawn implies it |
| Spotlight per volume | `mdutil` (user-supplied root) | **Drop** — mdutil is root-gated, MAS apps have no root |
| Rename | `diskutil rename` | **Blocked** in MAS (DiskManagement) |
| Per-volume options (read-only, no-auto-mount) | VolumePrefs + DA dissent | **Restricted**: the MountVeto dissent can stay (DA consults any session) — but as mounts can't happen from outside, the option loses its enforcement surface. Prefs could survive as metadata |
| Notifications (mount/unmount) | DADescriptionChanged + UNUserNotificationCenter | **Works** — observation + user notifications are MAS-safe |
| Launch at login | SMAppService.mainApp | **Works** |
| Settings / appearance / About | SwiftUI | **Works** |
| Menu-bar panel | MenuBarExtra | **Works** |
| Finder reveal | NSWorkspace.selectFile | **Works** (for it to show a volume, though, volumes must mount…) |

## The honest conclusion

An App Store build of NTFSSilicon is a **volume observer**: list, detail,
capacity, notifications, eject-by-NSWorkspace, launch-at-login — while
everything people install the app *for* outside the store (NTFS-aware
mount control, verify, erase, Spotlight, rename) is Developer-ID-only.

## Recommended release shape

**Decision (2026-10-28): skip the App Store.** The full app ships direct
via the notarized Developer-ID DMG. Point of sale and updates are a plain
website (Sparkle stays in Later) — no viewer edition gets built unless
that decision changes.
1. **Direct + notarized (Developer ID)** — the full app you already have:
   `tools/make-dmg.sh` produces it today. This is a release, no feature
   parity needed.
2. **App Store edition (viewer)** — subset above under App Sandbox,
   new target with `#if SANDBOXED`-gated feature set; worth doing
   mainly for visibility, not for capability.
3. Long shot, later: files-pickled flows (`com.apple.security.files.*-selected`)
   might restore get information-on-a-picked-volume, not system control.

## First code step to prove this out (not written yet)

Branch with `com.apple.security.app-sandbox` (Plus `files.user-selected
read-only`), swap `VolumeStore.list()` to a DiskArbitration-observer
backing, and run `tools/selftest.sh` — the checks that fail enumerate
exactly which stories the MAS edition carries vs. carries. The existing
selftest is the sandbox validator.
