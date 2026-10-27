# NTFS-Silicon — User Stories

Source: `docs/screens/INDEX.md` (screenshots of Paragon NTFS for Mac 17.0.488).
No `BRIEF.md` yet — these stories are built from the screen index alone.

**Scope note.** The rebuild is a native Apple-Silicon volume manager. It shows, mounts,
verifies and formats volumes using `DiskArbitration`/`diskutil`, and uses the
installed filesystem tools (`/Library/Filesystems/*.fs`) — including Paragon's own
`ufsd_NTFS.fs` tools if they are present — when `diskutil` alone can't do the job.
It cannot and will not copy Paragon's NTFS kernel parts; NTFS writing depends on
whatever is installed on the machine.

## Milestones

- **M1 Core loop** — see volumes, see detail, mount/unmount. Usable day one.
- **M2 Volume care** — rename, eject, verify, per-volume options and status words.
- **M3 Format** — the erase sheet, progress, NTFS formatting via installed tools.
- **M4 Volume menu** — the status-bar extra.
- **M5 Settings** — mount policies, notifications, appearance, launch at login.
- **M6 Polish** — true dark mode, empty state, context menus, accessibility, About.

---

## M1 Core loop

### S-001 See every volume at a glance
As the user, I open the app and see all mounted volumes in a sidebar list with size, media type, and status, so I can pick the one I'm after.
Screens: 01-main-default.png, 17-fsmenu-panel.png
Acceptance:
- [snap] Sidebar shows one row per volume: name, capacity, status dot, media chip where relevant.
- [unit] Volumes are read from DiskArbitration; a seeded fixture with 6 volumes renders 6 rows in order.
- [self] No volume type is filtered out (APFS, HFS+, ExFAT, FAT, NTFS all listed).
- [snap] Unmounted volumes appear too (dimmed), not just mounted ones.
Status: todo

UX:
- Flow: launch -> main window -> sidebar list visible; clicking a row shows its detail
- Surface: sidebar page (a place people come back to — the list is the app)
- States: empty "No volumes found" with "Rescan" button; a volume disappearing mid-run fades its row out
- Words: "Volumes" (sidebar header), status dot always paired with a word: "Ready", "Read-only", "Unmounted"
- Access: rows reachable by arrow keys; VoiceOver reads "Macintosh HD, 994 GB, Ready"

### S-002 Show a volume's detail
As the user, I select a volume and see its mount point, device, filesystem, macOS version if present, and used/free capacity, so I know what I'm looking at.
Screens: 01-main-default.png, 03-sagessd.png, 06-windows.png
Depends: S-001
Acceptance:
- [unit] Detail fields map 1:1 to what DiskArbitration reports (name, mount point, /dev/diskXsY, filesystem).
- [snap] Capacity bar with category split (Apps, Images, Other — same categories as the reference).
- [snap] Filesystem label shows e.g. "ExFAT", "Mac OS Extended (Journaled)", "NTFS".
- [self] A volume without an OS field (any non-macOS volume) hides the row entirely.
Status: todo

UX:
- Flow: click/arrow into a sidebar row -> detail pane on the right fills in
- Surface: inspector pane next to the sidebar (details of selection while people keep working)
- States: loading a capacity summary >0.5 s shows the bar greyed with "Measuring…"; error "Can't read usage for this volume" inline under the bar
- Words: "Mounted", "Device", "File System", "Operating System" — same labels as reference, they earned their keep
- Access: VoiceOver reads the bar as "777 GB used of 2 TB"

### S-003 Unmount a volume
As the user, I press Unmount on a selected volume and it disappears from Finder until I mount it again.
Screens: 01-main-default.png, 03-sagessd.png
Depends: S-002
Acceptance:
- [manual] Unmounting AI volume works; row goes dim, status word becomes "Unmounted", Mount button appears.
- [unit] Unmount request refuses for the boot volume — button disabled with tooltip "Macintosh HD is in use".
- [self] Escape/second click while unmounting doesn't double-fire the request.
Status: todo

UX:
- Flow: select volume -> toolbar "Unmount" (or button pad icon) -> status flips to "Unmounted" in place, no dialog
- Surface: inline toolbar button (changes one value on screen)
- States: busy replaces label with "Unmounting…"; error "Volume is in use — open the Files app to see what's using it." inline
- Words: "Unmount", tooltip "Make this volume invisible without disconnecting (⌘U)"
- Access: ⌘U shortcut; VoiceOver announces "Unmounted"

### S-004 Mount a volume
As the user, I can mount a listed-but-unmounted volume without leaving the app.
Screens: 03-sagessd.png (unmounted state = dimmed row, from post-S-003)
Depends: S-003
Acceptance:
- [manual] Mounting the unmounted AI volume makes it appear in Finder and the row goes Ready again.
- [unit] An NTFS volume mounts through the installed tools when present, else diskutil (read-only), and the status word says which ("Ready (read-only)").
- [self] Mounting an already-mounted volume is a no-op, not an error.
Status: todo

UX:
- Flow: select unmounted row -> toolbar "Mount" -> row flips to Ready
- Surface: same toolbar button, relabels per state (one control, two states)
- States: error "Mount failed: <reason from the system>" with a "Retry" button inline
- Words: "Mount", tooltip "Make this volume's files visible (⌘M)"
- Access: ⌘M; VoiceOver announces "Mounted"

### S-005 Open a volume in Finder
As the user, I click the mount point link and Finder reveals that volume.
Screens: 06-windows.png
Depends: S-002
Acceptance:
- [self] Clicking "/Volumes/AI" opens that folder in Finder; only shown when mounted.
- [snap] Link is styled as a link, has focus ring, VoiceOver reads the real path.
Status: todo

UX:
- Flow: click mount-point link in detail -> Finder opens the volume -> nothing changes in-app
- Surface: inline link
- States: link hidden when unmounted (not disabled-blurred — gone)
- Words: the mount path itself ("/Volumes/AI"), tooltip "Reveal in Finder"
- Access: Enter opens it when focused

### S-006 Volume list and per-volume state survive restart
As the user, I quit and reopen and see the same list, my selection, and whatever per-volume options I set.
Depends: S-001
Acceptance:
- [self] Relaunch restores selected row and all per-volume options stored so far.
- [unit] State lives in UserDefaults keyed by volume UUID, not by mutable disk name.
Status: todo

### S-007 Get disk-reading permission on first launch
As a first-time user, the app asks for what it needs to list volumes and tells me where to grant it.
Depends: S-001
Acceptance:
- [manual] On first launch a one-panel prompt explains the app reads disk metadata and opens System Settings at the right pane.
- [self] Launching without permission shows the empty state with a "Grant Access" button, not a crash or a blank list.
Status: todo

UX:
- Flow: first launch -> explanation panel -> "Grant Access" opens System Settings -> return to app -> list appears
- Surface: alert (a problem people must act on right now — one time only)
- States: after grant returns, the list loads without a restart
- Words: "NTFS-Silicon needs disk access to list your volumes. Grant Access…"
- Access: fully keyboard-navigable; Escape dismisses and app still runs

---

## M2 Volume care

### S-008 Rename a volume inline
As the user, I click a pencil next to a volume name and type a new name.
Depends: S-002
Screens: 01-main-default.png (pencil affordance), 06-windows.png (rename field in AX)
Acceptance:
- [manual] Renaming the SageSSD volume works and updates sidebar + detail + Finder.
- [unit] Name with >40 chars or control characters is refused inline with the reason.
- [self] Escape cancels, Return commits, Command-Z undoes the rename.
Status: todo

### S-009 Safely eject a disk
As the user, I eject a whole disk (all its volumes) from a row's button pad.
Depends: S-003
Screens: 17-fsmenu-panel.png (row eject affordance)
Acceptance:
- [manual] Ejecting a USB disk unmounts its volumes and powers it off; row disappears.
- [unit] Eject refused (inline message) when a volume is in use, with the Fix hint from unmount reuse.
- [self] Ejecting the boot disk's parent is not offered at all.
Status: todo

### S-010 Verify a volume's filesystem
As the user, I press Verify and see a progress bar, then the result, without any disk data changing.
Depends: S-002
Screens: 01-main-default.png (Verify in toolbar)
Acceptance:
- [manual] Verify on AI volume completes and shows "No problems found".
- [snap] Busy state is a determinate progress sheet titled "Verifying <volume>", with Cancel (safe until the filesystem tool starts).
- [self] Result stays in the detail pane until the next action; Verify disabled for read-only media with tooltip.
Status: todo

### S-011 Turn Spotlight indexing on or off per volume
As the user, I tick "Enable Spotlight Indexing" on a volume and the setting sticks.
Depends: S-002, S-006
Screens: 01-main-default.png, 06-windows.png (checkbox in detail)
Acceptance:
- [manual] Toggling it changes the volume's indexing state (verify with `mdutil -s`).
- [unit] Checkbox hidden entirely for read-only media, matching reference 07-ios265-sim.png.
- [self] State re-reads from the system on next launch — no stale checkbox.
Status: todo

### S-012 Set mount options per volume
As the user, I can tell a volume to always mount read-only or never auto-mount.
Depends: S-004, S-006
Screens: 06-windows.png (two checkboxes), 07-ios265-sim.png (disabled variant)
Acceptance:
- [manual] "Mount in Read-only mode" on windows volume persists; next mount is read-only (status word shows it).
- [manual] "Do not mount automatically" on a volume keeps it unmounted on replug.
- [unit] Both disabled (not just unchecked) for volumes the system forbids, e.g. simulator volumes.
- [snap] Matches the locked/disabled rendering of 07-ios265-sim.png.
Status: todo

### S-013 Read a volume's state at a glance
As the user, I rely on each row's dot and chips — but they're never color-only.
Screens: 02-ios27-sim.png, 07-ios265-sim.png (read-only / nobrowse chips)
Depends: S-001
Acceptance:
- [snap] Chips "read-only", "nobrowse" render exactly like reference; a dot always has a word next to it (detail tooltip suffices on rows).
- [self] VoiceOver reads chips as words; Increase Contrast keeps chips readable.
Status: todo

---

## M3 Format

### S-014 Confirm before erasing
As the user, I pick Erase on a volume and get a destructive-action sheet that names the volume and picks the new filesystem and name.
Depends: S-008, S-009
Screens: 09-erase-sheet.png, 10-erase-format-options.png
Acceptance:
- [snap] Sheet: icon + "Are you sure you want to erase volume "<name>"?" + explanation + filesystem popup + name field + Cancel/Erase buttons — layout like 09.
- [unit] Filesystem popup offers: the volume's current filesystem, MS-DOS (FAT32), ExFAT, Mac OS Extended (Journaled); "Microsoft NTFS" appears only when an NTFS formatting tool is installed (S-016).
- [unit] Erase button stays disabled while the new name is empty.
- [manual] Left volume untouched by opening and canceling the sheet.
Status: todo

UX:
- Flow: select volume -> toolbar "Erase…" -> sheet with volume pre-filled -> Return confirms, Escape cancels -> progress sheet (S-015)
- Surface: sheet (one short task that must finish or cancel; destructive, needs confirmation — sheet + explicit verb button, per reference)
- States: error "macOS doesn't include an NTFS formatter." shown as an info line attached to the popup, with a link to the tools-install docs — not a dead-end alert
- Words: "Erase…" (toolbar, ellipsis = more input coming), confirm button "Erase", "Cancel"; title carries the volume name
- Access: Escape cancels; name field focused on appear; VoiceOver reads the full warning

### S-015 Show erase progress
As the user, during an erase I see a progress sheet with a Cancel that works before formatting starts.
Depends: S-014
Screens: (ProgressSheetController is NIB-only in the reference; new snapshot in rebuild)
Acceptance:
- [manual] Erase a small test volume end-to-end: progress, then detail pane shows the new filesystem.
- [self] Cancel after erase has already started is refused with a safe inline explanation (erase is not resumable).
- [unit] Completion returns to the volume, refreshed, selected.
Status: todo

### S-016 Use installed filesystem tools when macOS can't do it
As the user with a third-party filesystem tool installed (e.g. Paragon's), my NTFS volumes can be formatted without extra apps.
Depends: S-014
Screens: 10-erase-format-options.png ("Microsoft NTFS" entry)
Acceptance:
- [manual] With `/Library/Filesystems/ufsd_NTFS.fs` present, Erase to Microsoft NTFS works on a test volume.
- [unit] Tools are discovered by probing `/Library/Filesystems/*.fs` at launch — never hardcoded to Paragon paths.
- [self] Without the tool, the menu entry is absent and an inline note explains why (covered in S-014 states).
Status: todo

---

## M4 Volume menu

### S-021 Open a volume list from the menu bar
As the user, I click the status-bar item and see my volumes with capacity bars and free space.
Depends: S-001, S-002
Screens: 17-fsmenu-panel.png
Acceptance:
- [snap] Panel: header with app icon + title, list rows (icon, name, capacity, free space, capacity bar, eject affordance), scrollable at >4 volumes.
- [unit] Panel follows the same DiskArbitration model as the main window — one source of truth, two views.
- [snap] macOS badge on the boot volume like reference.
Status: todo

UX:
- Flow: click status item -> panel opens anchored to it -> click elsewhere or Escape closes
- Surface: panel (popover-style under the status item; a tool kept open beside the work)
- States: empty "No volumes" + "Open NTFS-Silicon"; mounting indicator per row "Mounting…"
- Words: same as main window — "Volumes", "Ready", "Unmounted"; row actions match main window verbs
- Access: arrow-key navigation in the list; VoiceOver row names include free space

### S-022 Mount and unmount from the menu bar
As the user, I right-click (or hover-reveal) a row in the menu panel to mount/unmount without opening the main window.
Depends: S-021, S-003, S-004
Screens: 17-fsmenu-panel.png
Acceptance:
- [manual] Unmount AI from the panel, then mount it back; main window (if open) reflects both instantly.
- [self] Row actions disabled for boot volume, same rules as main window.
Status: todo

### S-023 Eject from the menu panel
As the user, I eject a disk from the panel row.
Depends: S-021, S-009
Screens: 17-fsmenu-panel.png (eject icons)
Acceptance:
- [manual] Eject a USB disk from the panel; panel row disappears.
- [self] Same refusal flow (in-use) as the main window — shared code path.
Status: todo

### S-024 Toggle the status item in Settings
As the user, I can switch the volume menu off and on in Settings (it was a power-off trap in the reference).
Depends: S-021
Screens: 15-prefs-menuapp.png
Acceptance:
- [self] Turning it off removes the status item; on brings it back without relaunching the app.
- [snap] Control mirrors reference wording "When ON, the menu displays a brief information on your volumes…"
Status: todo

---

## M5 Settings

### S-031 Set default mount policies
As the user, I choose what to do with dirty volumes and hibernated Windows volumes in Settings.
Depends: S-026 (settings window exists), S-004
Screens: 12-prefs-general.png
Acceptance:
- [snap] General settings: three labeled popups — "What to do when mounting dirty volumes?", "What to do with hibernated Windows?", "System report format" — choices copied from reference defaults (Verify before mount / Ask what to do / Verbose mode OFF).
- [unit] Dirty-volume policy feeds the mount path used by S-004; "Ask what to do" produces the prompt sheet.
- [manual] Verify-before-mount runs a check first and reports it, then mounts.
Status: todo

### S-032 Choose notifications
As the user, I control which mount events notify me.
Screens: 14-prefs-alerts.png
Depends: S-026
Acceptance:
- [snap] Four toggles: all events, successful mounts, failed mounts, when a volume needs attention (replaces "trial expiration" which is dropped).
- [manual] Unmounting from Finder surfaces the matching notification per settings.
- [self] Toggles persist; UserNotifications framework only when at least one is on.
Status: todo

### S-033 Switch appearance without an admin password
As the user, I pick System / Light / Dark in Settings and the whole app follows immediately, no lock icon.
Depends: S-026
Screens: 12-prefs-general.png, 15-prefs-menuapp.png (appearance radios in reference, both locked)
Acceptance:
- [snap] Radios match reference layout; switching changes appearance live (native `preferredColorScheme` handling is unnecessary — the app just follows the setting everywhere).
- [self] No admin lock anywhere in the rebuild's settings; no `NSRequiresAquaSystemAppearance` in the Info.plist.
Status: todo

### S-034 Launch at login
As the user, I tick "Launch on system startup" and the app (with the volume menu) is there after a reboot.
Depends: S-026
Screens: 15-prefs-menuapp.png (checkbox)
Acceptance:
- [self] Toggle drives SMAppService; state re-reads from the system at next launch.
- [manual] Setting survives logout/login.
Status: todo

### S-035 Check for updates manually
As the user, I can check for a newer build from Settings.
Screens: 13-prefs-updates.png
Status: dropped (vendor update channel — see Dropped; revisit in Later with Sparkle if wanted)

### S-036 Reach everything from the menu bar and keyboard
As the user, I use the app menu (About, Settings…, Help, Quit) and standard shortcuts.
Depends: S-026
Screens: 11-app-menu.png, 16-about.png
Acceptance:
- [snap] App menu matches reference items minus dropped ones; menu commands wired for the actions that exist.
- [self] ⌘, opens Settings; About panel shows version + build; every toolbar button has a tooltip and shortcut.
Status: todo

---

## M6 Polish

### S-041 Native dark mode everywhere
As a user in dark mode, every surface — window, sheet, panel, menus — renders correctly.
Depends: any screen shipped
Screens: (new dark-mode snapshots in rebuild)
Acceptance:
- [snap] Light+dark snapshot pairs for every screen, compared in build-and-verify.
- [self] No hardcoded colors outside the design-token file.
Status: todo

### S-042 Empty and degraded states
As a user with no external volumes (or no disk access), the app explains itself instead of showing a blank pane.
Depends: S-001, S-007
Acceptance:
- [snap] No-volumes state with "Grant Access"/"Rescan"; offline-volume rows dimmed with word "Unmounted".
- [self] Pulling the selected volume's disk mid-session updates the UI without a crash.
Status: todo

### S-043 Right-click context menu on volume rows
As the user, I right-click a row for the same actions the toolbar offers.
Depends: S-001, S-003, S-009
Acceptance:
- [self] Context menu = Unmount/Mount, Eject…, Rename…, Verify…, Erase… — exact same handlers as toolbar.
- [snap] Menu matches the surface rules (ellipses on commands that open sheets).
Status: todo

### S-044 Accessibility pass over all milestones
As a VoiceOver or keyboard-only user, I can do everything a mouse user can.
Depends: M1–M5 shipped
Acceptance:
- [self] Full flow keyboard-only; VoiceOver labels match screen words (glossary); Accessibility Inspector reports no issues.
Status: todo

---

## Later

- **Auto-update framework** — Sparkle 2 if the app ships outside the App Store.
- **Force-mount and mount-problem repair sheets** — real value only once NTFS writing is settled; needs driver-level study first.
- **Second language (French)** — reference ships en+fr; one language until v1 ships.
- **Volume menu "…" quick-settings popover** — reference has it; only if the panel earns it in use.

## Dropped

- **Accounts, sign-in, licenses, activation (BOUI windows, payment, transactions, notification agent "trial expired")** — vendor identity system; a rebuild sells nothing.
- **CampTune promo strip and promo windows** — Pure marketing for a paid sibling product.
- **Zendesk contact support / feedback chat / ticket windows** — support infrastructure, replaced by the app's repo issues.
- **"Collect analytics data"** — no telemetry in a local-only utility.
- **"Enable/Disable NTFS for Mac" driver gate** — belongs to Paragon's proprietary driver; the rebuild works with whatever filesystem tools the system provides instead.
- **Start-up (Boot-Camp/BOOTINI) sheet** — SIP-gated and bootable-Bundle specific; no visible function on modern macOS.
- **Uninstall helper** — an App-Store-era app uninstalls by dragging itself to the Trash.
- **Quick tour / first-run promo windows** — modern onboarding is the empty state (S-042).
