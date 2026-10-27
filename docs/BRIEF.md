# NTFSSilicon (display name: NTFS-Silicon)

A native Apple-Silicon volume manager that shows, mounts, unmounts, ejects, verifies and formats the Mac's volumes — for people who manage external disks (Windows/NTFS drives especially) and want the missing "volumes" app Apple never shipped.

## Replaces
Paragon NTFS for Mac 17's GUI (cloned, see docs/screens/INDEX.md; rebuild rationale: 2021-era UI, forced-Light, macOS 11 SDK — and this install already runs arm64).

## Main jobs
1. See every volume (mounted or not) with name, size, filesystem, status — in a window and in the menu bar.
2. Mount / unmount / eject a volume in one click, with per-volume options (read-only, no auto-mount, Spotlight).
3. Erase a volume with a filesystem picker (Microsoft NTFS when installed tools allow), verify before/without risking data.

## Data
- Live system state only — no durable user data model. Volumes come from DiskArbitration each launch.
- Per-volume user prefs keyed by volume UUID: `readOnly`, `noAutoMount`, `spotlight` (stale values for missing volumes are ignored).
- App prefs: app policies (dirty-volume behavior, notifications), appearance, launch-at-login, volume-menu on/off.

## Shape
One window: dark sidebar of volumes + detail inspector, plus an optional status-bar volume menu (MenuBarExtra). macOS 26+ (per BAMA toolchain), local only. No accounts.

## System hooks
Menu-bar item (volume menu). Launch at login (SMAppService). Notifications for mount/unmount. No Shortcuts/CLI in v1.

## Reference
Paragon NTFS for Mac 17 (screenshots in docs/screens/). Structure copied; look refreshed.

## Look
Native macOS with own dark sidebar chrome (the one thing worth keeping from the reference design), otherwise standard AppKit/SwiftUI parts, system accent. True dark mode — the reference forces Light.

## Not in version one
- Any NTFS write driver of its own (uses installed `/Library/Filesystems/*.fs` tools; read-only NTFS otherwise)
- Erase-to-NTFS when no NTFS formatter is installed (explains itself in the sheet)
- Accounts, licenses, telemetry, promo windows, uninstaller, vendor updater (drop list in STORIES.md)

Decided by the agent: name (folder `NTFS-Silicon` already in use), bundle id `com.saslu.ntfssilicon`, scope = M1+M2+M4-essentials from docs/STORIES.md.
