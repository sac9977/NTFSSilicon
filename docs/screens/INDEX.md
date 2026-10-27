# NTFS for Mac 17.0.488 — Screen Index

Source: `/Applications/NTFS for Mac.app` (bundle id `com.paragon-software.ntfs.fsapp`, executable `FSApp`).
Captured 2026-10-27 via `screencapture` + Accessibility scripting (look, not touch).
**Privacy: files contain the user's real name/email in 01–09, 17, 18 — `docs/screens/*.png` is git-ignored; keep it that way.**

## Companion processes
| Process | Role |
|---|---|
| `FSApp` | Main GUI (835×550 main window, custom chrome) |
| `FSMenuApp` | Status-bar item (own mini app in `Resources/FSMenuApp.app`) |
| `com.paragon-software.ntfsd` | Privileged daemon doing mount/verify/format |
| `NotificationAgent` | macOS notifications |

**All are universal (x86_64+arm64) — the premise "Intel-only" was wrong for this build.**
Rebuild rationale: macOS 11.1 SDK, `NSRequiresAquaSystemAppearance` = no true dark mode, 2021-era custom UI, x86_64-only bundled Swift runtime dylibs (dead weight).

## Screens (docs/screens/)

| # | File | Screen | Key observations |
|---|---|---|---|
| 01 | 01-main-default.png | Main window, Macintosh HD | Dark-navy sidebar, account row on top, "Other Volumes" table (8 rows), detail pane w/ toolbar Unmount/Verify/Erase/Startup, capacity bar, Spotlight checkbox. CampTune promo strip + "NTFS for Mac" bottom logo in sidebar column |
| 02 | 02-ios27-sim.png | iOS 27.0 Simulator volume | Virtual APFS disk, `read-only`+`nobrowse` chips, amber dot (non-writable?) |
| 03 | 03-sagessd.png | SageSSD 2 TB | Mac OS Extended (Journaled), green dot, Unmount/eject affordance |
| 04 | 04-ai.png | AI 1 TB | external USB volume |
| 05 | 05-systemfolders.png | SystemFolders 701.57 GB | |
| 06 | 06-windows.png | windows 299.86 GB | **ExFAT, not NTFS** — all three checkboxes active, Erase enabled, Startup disabled |
| 07 | 07-ios265-sim.png | iOS 26.5 Simulator | Read-only; "Mount in Read-only mode" checked *and disabled*; Enable Spotlight disabled |
| 08 | 08-account-dropdown.png | Account dropdown | Items: Account Info…, Contact Support, Sign Out |
| 09 | 09-erase-sheet.png | Erase sheet (windows) | "Are you sure you want to erase volume…" + explanation, filesystem popup, name field, Cancel/Erase |
| 10 | 10-erase-format-options.png | Erase format popup | Microsoft NTFS (default), MS-DOS (FAT32), Mac OS Extended (Journaled), Mac OS Extended, ExFAT, HFS+ Case-sensitive variants |
| 11 | 11-app-menu.png | App menu (NTFS for Mac) | About NTFS for Mac, Settings…, Services, Hide, Quit (menu uses "Settings…", macOS 13+ naming) |
| 12 | 12-prefs-general.png | Prefs: General | Driver Enabled + Disable button, Uninstall…, 3 policy popups: dirty volumes → "Verify before mount"; hibernated Windows → "Ask what to do"; System report format → "Verbose mode OFF"; own Appearance radios (System/Light/Dark); everything behind a lock button |
| 13 | 13-prefs-updates.png | Prefs: Updates | Auto-check checkbox, Check for Updates Now…, Collect analytics data |
| 14 | 14-prefs-alerts.png | Prefs: Alerts & Notifications | 4 toggles: all events / trial expiration / successful mounts / failed mounts |
| 15 | 15-prefs-menuapp.png | Prefs: NTFS for Mac Menu | ON/OFF toggle for the status item, its own Appearance radios, Launch on system startup checkbox |
| 16 | 16-about.png | About | Standard small about panel |
| 17 | 17-fsmenu-panel.png | Menu-bar extra panel | Dark panel listing volumes with type (Internal / Virtual Disk / External USB), free space, capacity bars, "macOS" badge, ⋯ button, per-row eject |
| 18 | 18-account-info.png | Account info panel | Account holder name + email + Sign Out / Close (sheet attached to main window) |

### Sidebar data model (observed)
Row = volume with: name (editable via pencil), size, colored status dot (green/amber), optional `read-only`/`nobrowse` chips, eject/unmount button. First row acts as a group header "Other Volumes".

### Detail pane data model
Toolbar buttons (Unmount, Verify, Erase, Startup — enabled per volume type), volume title + rename pencil, Mounted Yes/No (+ mount path link), Device (/dev/diskXsY), File System, Operating System, capacity bar (semantic categories: Video/Images/Apps/Other), and up to 3 checkboxes: Enable Spotlight Indexing / Mount in Read-only mode / Do not mount automatically (availability depends on filesystem + writability).

## Not captured (out of scope / gated)
- **Verify progress result** — spawns disk activity; skipped.
- **Unmount / actual Erase** — state changes to user data; skipped.
- **Startup sheet** — button enabled only for Macintosh HD but produces no visible sheet on this system (SIP-gated, `SIPStartUpSheetController.nib` exists).
- **"Enable NTFS for Mac…" banner** — visible in AX tree of main window; clicking would enable the write driver (system change). Only offered when driver is disabled; in this install driver shows Enabled.
- **BOUI activation/serial/offline-activation windows, QuickTour, Promo, Payment/Transaction, Zendesk support, SecurityLevel, KextApproval, ShareIntro, Progress/Force/Eject sheets** — NIBs exist (full screen inventory below) but they open only without a valid license / on first run / during specific operations.
- **Dark mode** — App has own Appearance setting but it sits behind an admin lock (click lock → auth prompt). Info.plist also forces `NSRequiresAquaSystemAppearance=true`. Not toggled without user permission.

## Command map (from MainMenu.strings)
Menu bar is stock Cocoa template (File/Edit/Format/View/Window/Help mostly default). App-specific surface:
- App menu: About NTFS for Mac, Settings…, Services, Hide/Show, Quit (+ Quit and Keep Windows)
- In-app: Customize Toolbar… exists in strings (toolbar may be customizable)
- Everything real lives in the window: sidebar, detail toolbar (Unmount/Verify/Erase/Startup), context actions, Settings, plus the FSMenuApp status item.

## Full NIB screen inventory (Base.lproj, 31)
AccountInfoWindowController, AlertsPreferencesViewController, BOUIActivationResultViewController, BOUIEnterSerialViewController, BOUINoLicenseViewController, BOUIOfflineActivationViewController, DetailViewController, EjectSheetController, EraseSheetController, ForceSheetController, GeneralPreferencesViewController, KextApprovalViewController, MainMenu, MenuAppPreferencesViewController, NTFSDiskAccessViewController, PUUpdateWindowController, PaymentCancelConfirmationController, PreferencesWindowController, ProgressSheetController, PromoViewController, QuickTourViewController, SIPStartUpSheetController, SecurityLevelViewController, ShareIntroWindowController, SidebarViewController, StartUpSheetController, TransactionSuccessViewController, TransactionViewController, UpdatesPreferencesViewController, ZendeskTicketSuccessWindowController + root-level PaymentWindowController/PUUpdateProgressController/ZendeskChatController/ZendeskTicketController NIBs.

## Localization
`en.lproj` + `fr.lproj` only. All app text comes from per-screen `.strings` files — key strings already mined.
