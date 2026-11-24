# Full-screen apps window layout ("screens")

Date: 2026-11-23. Fork branches: `EvilBorsch/denial` `eb/screens-layout`, `EvilBorsch/denial-apps` `eb/screens-layout`, both rebased on 2026-11-23 evening onto their `eb/main` (denial `ccadf12` = `deniald` and shell of the installed package `eb16.tp1` plus this document; denial-apps `c1d0137`).

The owner agreed the behaviour below in conversation ("Behaviour" sections). The owner left the approach to the agent, so the approach and every point marked **(agent's call)** is open to correction by the owner.

## Why

The owner of the tablet (OnePlus Pad 3, Denial desktop presentation on the built-in 3392×2400 panel, keyboard cover with a touchpad) used macOS for years. They want a Mac-like way of working: every app full screen, moving between apps with swipes, overviews by gesture, and split screen made by dragging. Gestures matter more than the keyboard. Today the tablet runs `layout.windowLayout = "dwindle"`, which is keyboard-driven tiling.

## Goals

- A fourth window layout, `layout.windowLayout = "screens"`, next to stacking, dwindle and scrolling, chosen in Settings like the others.
- Every app opens full screen. Three-finger swipes move between apps.
- A screens overview (three fingers up) and an app-windows view (three fingers down), as on macOS (Mission Control and App Exposé).
- Split screen made and undone by drag and drop in the overview. The divider can be dragged with a plain mouse and with a finger, as on Windows.
- The same gestures on the touchpad and with three or four fingers on the touchscreen.

## Non-goals

- The mobile presentation (phone panel) does not change. Window layouts never apply there.
- No dock, no global search (Spotlight), no new launcher.
- The touchpad driver and libinput tuning are not touched here. A separate thread works on them (`D:\androidlinux\research\touchpad.md`).
- Stacking, dwindle and scrolling keep their behaviour. The one exception is an optional shared divider improvement (see "Split screen").

## Anti-goals (failure even if it "works")

- A window that cannot be reached. Every window is on some screen, or floats over one.
- Gestures that fire by accident during ordinary two-finger scrolling or palm contact.
- Regressions in the other layouts, in the mobile/desktop toggle, or in settings files read by an older `deniald` (owner may roll back to `eb16.tp1`).
- Workarounds instead of proper fixes (project rule).

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | New layout built on the scrolling layout's strip (`ScrollingLayout`/`ScrollingRow`/`ScrollingColumn` in `compositor/src/bin/deniald/window_layout.rs`). Each column is a screen fixed at 100% of the work area. A column's split tree is the split screen. | Most mechanics already exist: the strip and its finger-following three-finger scroll with momentum and snap to the nearest column (`window_layout.rs` ~1830–1890, `wayland_frontend/input.rs` ~1770–1792), split trees inside columns, and drop rules that stack a tile into a column or drop it into a gap as its own column. New work is the overview, the app-windows view, gesture routing, the divider and Settings. |
| B | Dwindle with one dynamic workspace per app. | The workspace count is fixed (`layout.workspaceCount`, Super+1..9, the top-bar indicator), and workspace switching is a discrete transition, not finger-following. Dynamic workspaces touch many places. |
| C | A new layout written from scratch. | Cleanest semantics, but it re-implements strip scrolling, animation and snapping that already exist and are tested. |

A was chosen because it reuses the most tested code and leaves only the user-visible parts as new work.

## Behaviour: screens

- Per output there is one ordered strip of screens. Each screen fills the output's work area (the output minus the top bar). At rest a neighbouring screen is never visible: no peeking, and the gap is outside the viewport.
- A new toplevel window becomes a new screen immediately to the right of the current one. It is focused, and the strip animates to it.
- Floating windows are not screens. These are the ones the layout already floats (`wayland_frontend/window_layout.rs` ~1675–1692): transients and dialogs, fixed-size windows (min = max, e.g. calculator), X11 auxiliary and override-redirect windows, and always-on-top windows. They float centred over the screen of their parent (or the current screen) and move with that screen.
- When the last tiled window of a screen closes, the screen is removed. Focus goes to the left neighbour, or to the right one if the screen was first. **(agent's call)**
- Maximize is meaningless here and does nothing. Fullscreen (Super+F) still works and covers the top bar.
- **Workspaces are not used in this layout.** The owner sees exactly one strip per output, the top-bar workspace indicator is hidden, and workspace actions do nothing. Switching into the layout gathers the windows of all workspaces into the strip, workspace by workspace in their order. Switching out puts them on workspace 1. The mechanism is the builder's choice, for example letting this layout imply `workspacesEnabled = false`, as long as no window is lost. **(agent's call)**

## Behaviour: gestures

The touchpad and touchscreen three- and four-finger gestures share one recognizer (`compositor/src/bin/deniald/touchpad_gestures.rs`, `wayland_frontend/touch_gestures.rs` ~280–293). In this layout the compositor routes them as below regardless of `shortcuts.json`. The scrolling layout already overrides three-finger horizontal swipes the same way; follow that precedent and document it.

| Gesture | In the screens layout |
|---|---|
| 3 fingers left/right | The strip follows the fingers. On release it snaps to the previous, next or current screen (existing logic). Direction is as on macOS: fingers moving left bring in the screen on the right. Verify that the existing scroll direction matches, and that it also works with three fingers on the touchscreen. |
| 3 fingers up | Opens the screens overview. If the app-windows view is open, closes it. |
| 3 fingers down | Opens the app-windows view. If the screens overview is open, closes it. |
| 4 fingers up | Opens the launcher (`denial_launcher.openApplications`), like Launchpad. |
| 4 fingers down/left/right | Nothing. |

- Three fingers down is not recognized today. Add it to `SWIPE_BINDINGS` and the `ShortcutGesture` enum; the comment there says that is the intended way. Give it no default binding in the other layouts.
- Two-finger scrolling must never trigger these gestures.

## Behaviour: screens overview (3 fingers up, also Super+A)

- One card per screen, in strip order. The card is a thumbnail of the screen, including its split, and shows the app icon and name under it.
- Screens that hold a single full-screen window of the same app collapse into one stack with a count badge. The stack sits where the first of them is. Tapping the stack goes to the most recently focused window of that app. Clicking the badge expands the stack in place into separate cards **(agent's call)**. Split screens are always their own card.
- Tapping a card goes to that screen and closes the overview. Esc, three fingers down, or a tap on empty space closes it and returns to the current screen.
- Keyboard: arrows, Enter and Esc, as in the current overview.

### Drag and drop in the overview

- Start a drag with a mouse press and drag, or on the touchscreen with a long press and drag. In a split card each window inside the thumbnail is its own drag handle.
- **Joining.** Dropping onto a card makes the window join that screen's split, on the side of the card where it was dropped: left, right, top or bottom. With two windows the result is exactly 50/50. A third or fourth window splits the side it lands on, so up to quarters, as on Windows. Reuse the existing edge-zone rules of the layout grab (`wayland_frontend/window_layout.rs` ~1727–1846) where they fit. While dragging, highlight where the window will land.
- **Separating and reordering.** Dropping into a gap between cards, or before the first or after the last, makes the window its own screen at that position. Dragging a single-window card into a gap reorders screens.
- Dropping back where the window came from, or outside the cards, cancels.
- Dropping onto a collapsed stack joins the screen of the stack's most recent window. **(agent's call)**

## Behaviour: app windows (3 fingers down)

- Shows all windows of the focused window's app (by app id): full-screen ones, ones inside splits, and floating ones, as thumbnails with the most recent first. It shows even when there is only one window, as on macOS.
- Tapping a thumbnail goes to its screen and focuses that window. Esc, three fingers up, or a tap on empty space closes the view.

## Behaviour: split screen

- The divider between split windows can be dragged with a plain mouse (no Super) and with a finger. The hit zone is at least 16 logical px wide (the visible gap is `layout.maximizePadding`, 8 px), and the cursor shows a resize shape on hover.
- Double-clicking or double-tapping the divider returns that split to equal sizes.
- The existing limits stay: ratio 10–90% and client minimum sizes. Two-finger pinch on the touchscreen and Super+Minus/Equal keep working.
- The builder may put the divider drag into the shared split code so that dwindle and scrolling get it too, provided their other behaviour does not change. **(agent's call)**

## Keyboard (secondary, keep working)

- Super+Left/Right: previous or next screen.
- Super+Up/Down: focus within a split.
- Super+Ctrl+arrows: swap within a split, or move the screen along the strip.
- Super+K closes, Super+Tab opens the window switcher, Super alone opens the launcher, and Super+A opens the screens overview.

## Settings

- `DesktopWindowLayout` in `packages/denial_flutter_sdk/lib/src/settings/shell_settings.dart` gains `screens`, and `deniald`'s settings parser accepts `"screens"`.
- **Compatibility.** Check what an older `deniald` (`eb16.tp1`) does with an unknown `windowLayout` value. If it would reject the whole settings file, choose a scheme where a rollback still loads the user's settings, for example by falling back to the default layout. The `eb14` work kept the schema version for the same reason (see `D:\androidlinux\CHANGES.md`, 14:30 entry).
- Settings app (denial-apps fork, `apps/settings/src/catalog.rs`, `words_ru.rs`):
  - Add the option on «Компоновка рабочего стола» → Window layout, and on the «Монитор» page.
  - English label "Full screen", Russian «На весь экран».
  - Also translate the currently untranslated "Windows", "Window layout", "Stacking", "Dwindle" and "Scrolling", consistent with the SDK's Russian strings («Раскладка окон», «Мозаика»). **(agent's call)**
- l10n for en, ru and zh in the SDK for every new string.

## Mobile presentation and monitors

- The phone panel in mobile presentation is unchanged.
- With an external monitor, the layout applies to the monitor exactly as the other layouts do. Each output has its own strip.

## Constraints

- Work in worktrees `~/androidlinux/components/denial-screens` and `~/androidlinux/components/denial-apps-screens` (Windows: `D:\androidlinux\components\…`). Run git, builds and tests inside WSL (see `D:\androidlinux\AGENTS.md`).
- Build per `docs/EB-BUILD.md` into package `denial 0.6.8-1+eb17` in `D:\androidlinux\images\debs\`. Write an install script `D:\androidlinux\tools\tab\install-denial-eb17.sh` modelled on `install-denial-eb16.sh`, with a SHA-256 check and `NO_RESTART=1`.
- Tests:
  - The suites of `docs/EB-BUILD.md` (`deniald` under qemu, shell on `flutter_tester`, SDK, Settings). Run them on the untouched base first and report the new counts against that baseline; known failures are listed in EB-BUILD.
  - New tests for layout operations (insert, close, join on each side, separate, reorder, snap), gesture routing per layout, overview grouping, drop-zone hit testing, divider hit testing and drag, and the settings fallback.
- Installing on the tablet restarts the Denial session and closes the owner's windows. It happens only with the owner's explicit consent at that moment, asked by the main thread.
- One commit per finished change, with English kernel-style messages and a `Co-Authored-By:` line. Push `eb/` branches to `origin`, never to `upstream`. Merge into `eb/integration` only after the tablet check.
- Proper fixes only: no workarounds.

## Left to the builder

- How workspaces are suppressed.
- Exact drop-zone geometry and animations, and how overview thumbnails are rendered (reuse the existing overview previews where possible).
- The stack expansion UI.
- Strings not fixed above.
- Whether the divider drag also applies to dwindle and scrolling.

# Iteration 2: eb18 (2026-11-23 night)

The owner installed eb17, and the agent tested it on the tablet (`D:\androidlinux\device-logs\eb17-check\`, `eb17-explore\`, CHANGES.md entry of 22:44). The owner then asked for a Mac-like, gesture-first mode with search, Alt+Tab and Mac shortcuts, and for the useful parts to reach the mobile presentation too. They want the work done autonomously without questions, so every decision below is the agent's call unless quoted from the owner.

## Bugs found on the tablet (fix first)

- **Four fingers up:** the launcher opens and closes at once. It is visible at 0.3 s and gone at 1.5 s, while a Super tap keeps it open. Suspect a toggle fired twice (a repeat or end event).
- **Divider by touch:** a finger on the split divider does not take it (no "took a split divider" in the journal; `vinput swipe 0.5 0.5 0.62 0.5`).
- **Overview leftovers:** after a join an empty card frame stays. The desktop clock widget shows through the overview.
- **Desktop mode is forgotten:** after a session restart the shell came up mobile and had to be switched with the tile. Persist the presentation the owner chose last (a settings key), and start in it.

## The owner's requests (quoted) and the decided design

- "A logical mode built on touchpad swipes, or on the mouse with the middle button held":
  - **Middle-button drag** acts as a three-finger swipe in the screens layout: sideways moves the strip with the pointer, up opens the overview, down opens the app windows.
  - A middle click without movement (past a small threshold) still reaches the client as a normal press and release (links in new tabs, paste).
  - Cost: clients lose middle-button drags (canvas pan, autoscroll). There is a Settings toggle, on by default in the screens layout.
- "If an app spawns several windows they are easy to find":
  - The app-windows view (three fingers down) shows every window of the app with its title, plus the app icon and name, even for one window.
  - The overview stacks windows of one app (eb17). Verify it with an app that really opens two windows.
- "Easy to find the right app with a swipe up, with search there" (the overview becomes the hub):
  - A search field at the top takes typing immediately. Typing filters screens and windows by app name and window title.
  - Below the open windows, matching apps from the launcher catalog can be started (Spotlight-like). Enter goes to the first match or starts it.
  - The background is dimmed and blurred, labels are larger and carry icons. The overview follows the fingers as it opens (Mission Control feel).
- **Global search** (desktop presentation; "Alt+F … through our Spotlight"): the same search, as an overlay over the current screen, on Alt+F in the Mac preset. In the default (Super) preset Super+F is fullscreen and Super+Space switches the layout, so search gets a free Super combination of the builder's choice (documented).
- **"Alt+Tab must work":**
  - An app switcher like ⌘Tab. Hold the modifier and Tab cycles apps (all windows of an app are one icon); Shift+Tab goes back; releasing switches. Grave (`) cycles the windows of the current app.
  - In the default preset it is Alt+Tab as well (a PC habit). It replaces nothing the owner uses (Super+Tab stays the window switcher).
- **Mac preset** ("Alt is my Super: Alt+Tab, Alt+C, Alt+V, Alt+Space switches the language as now, Alt+F searches apps"):
  - Settings → Shortcuts gets a choice "Как на Mac" / "Like a Mac". Physical Alt acts as ⌘, physical Super acts as Option, Ctrl stays Ctrl.
  - Implemented in deniald, which knows the focused client: per-client key translation, not an external remapper.
  - Shell bindings on Alt: Alt+Tab, Alt+`, Alt+F (search), Alt+Space and Alt+Shift+Space (keyboard layout, as now), Alt+Shift+3 (screenshot of the screen), Alt+Shift+4 (region), Ctrl+Alt+Q (lock), Ctrl+Alt+F (fullscreen), Alt+M (minimize), Alt+H (hide the app).
  - Every other Alt+key goes to clients as Ctrl+key (Alt+C/V/X/Z/Shift+Z/A/S/T/W/Q/N/L/R/P…).
  - In terminals (detected by app id: GNOME Console/kgx, gnome-terminal, ptyxis, foot, alacritty, kitty, wezterm, xterm, konsole) it goes as Ctrl+Shift+key.
  - Text navigation as on macOS:
    - Alt+←/→ → Home/End, Alt+↑/↓ → Ctrl+Home/End, Alt+Backspace → delete to line start;
    - Super(Option)+←/→ → Ctrl+←/→, Option+Backspace → Ctrl+Backspace;
    - Super(Option)+letters → Alt+letters for clients (menus).
  - With the preset off, everything is as today.
  - The owner's choice on the search key stands: Alt+F searches, so find-in-app is Ctrl+F. All of these bindings remain editable in Shortcuts.
- **"Beautiful animations":** the overview, app windows, the switcher and search open and close smoothly. Gesture-driven ones track the fingers and settle with a spring. Strip moves already follow the fingers.

## Presentation follows the keyboard cover (owner's rule, 2026-11-23 night)

Owner, quoted: "keyboard attached = we are in desktop mode (and in the new layout if the user chose it in Settings); detached = tablet mode (or if you switch with the toggle on purpose). Tablet mode is purely for fingers on a small screen; desktop mode is for mouse and trackpad gestures, on the tablet's screen or a big screen, but touch still works there. Proper scaling, proper animations and usability are always the baseline. In tablet mode you work only with a finger, without keyboard or mouse, so there is no point improving keyboard things for it."

- **Automatic switching.**
  - Attaching a physical keyboard switches the shell to the desktop presentation, with the window layout chosen in Settings (for the owner, the screens layout). Physical keyboards are the cover, USB and Bluetooth; virtual uinput devices such as `erhai test keyboard` do not count, so tests do not flip the mode.
  - Detaching the last physical keyboard switches to the tablet (mobile) presentation.
  - deniald already tracks `keyboard_attached` (`settings.rs` ~1997, `flutter_settings_sync.rs` ~744, `docs/APPS_FOLLOW_MODE.md`). Build on that.
- **Manual override.**
  - The «Настольный режим» tile still switches by hand, and the choice holds until the next attach or detach event.
  - A Settings switch "Режим по клавиатуре" / "Follow the keyboard" turns the automation off, on by default.
  - With it off, the last chosen presentation is remembered across session restarts (this also fixes the eb17 bug).
- **Desktop presentation:** made for mouse, trackpad and keyboard, while touch keeps working (the existing touch window gestures, tapping, scrolling).
- **Scaling, animations and usability are the baseline in both presentations.**
  - Audit scaling of the shell UI, Wayland apps, X11 apps and Android (Droidloom) apps in each presentation on the 3392×2400 12.1" panel (the owner has `apps.scale = 2.0`), and on an external monitor if one appears.
  - Fix what looks wrong: text too small or large, blurry X11, mismatched shell vs apps.
  - Mode switches must be smooth and must not lose windows.

## Tablet (mobile) presentation: fingers only, a full track

The owner wants the useful parts of this work in the tablet presentation, for the best finger UX on this tablet. In it the owner uses only fingers, so **no keyboard or touchpad work goes into it** (no Alt+Tab, no Mac preset, no touchpad swipes there; those live in the desktop presentation, which the keyboard brings up anyway).

1. **Audit first.** Compare the mobile shell (home grid, drawer, Recents, bottom pill, edges, shade) with the finger-relevant features of eb17/eb18. Write the gaps and the chosen ports to `docs/superpowers/specs/2026-11-23-mobile-ports.md`.
2. **Ports, at least:**
   - **Search by finger:** a search field in the app drawer, and pulling down on the home screen opens search, as on iPadOS. The search is shared with the desktop overview: apps and open windows.
   - **Drawer on by default,** if that does not disturb existing home layouts.
   - **Recents:** windows of one app grouped, with the app name and window titles.
3. **Split View in the tablet presentation:** two apps side by side, as on iPadOS.
   - Choose "split with the current app" from Recents (long press or drag).
   - Drag the divider with a finger.
   - Drag an app off to make it full screen again.
   - Reuse the compositor's screen and join logic where it fits.
   - This comes after the ports in 2. Ship it if it is solid, otherwise report how far it got.
4. Anything else from this work that clearly helps finger use on the tablet, at the builder's judgement. List it in the report.

## Delivery

- Package `denial 0.6.8-1+eb18`, from `eb/screens-layout` in both forks (on top of eb17).
- The agent installs it on the tablet and tests it there itself (owner's standing permission for this work: install packages, restart the Denial session, unlock with the owner's password from the T3 secret file, use Stay awake during tests). Then it iterates until the checks pass.
- No partitions and no reboots.
- At the end: if the checks pass, the owner's session is left in desktop mode with the screens layout and the Mac preset on, Stay awake off. The report says how to switch back.

# Iteration 3: eb19 (2026-11-24)

The owner used eb18 and said "all great, but" listed six points (quoted, translated). They still want autonomous work without questions; every interpretation below is the agent's call.

1. **"In the tablet presentation, a button at the bottom to close the active windows instead of swiping each one away."**
   - A "Close all" button («Закрыть все») at the bottom of Recents, as on Android and iPadOS app switchers.
   - It closes every app in Recents. Windows get a normal close request; apps that ask to save (unsaved documents) are not killed and keep their dialog.
   - Recents then goes home.
2. **"Animations, at least in the desktop presentation, don't feel like 120 FPS. Animations must run at 120 fps with no lag or stutter."**
   - Target: every shell animation and gesture-driven motion on the 120 Hz panel presents a new frame on every vblank. A missed frame is a bug.
   - This covers: strip swipe and snap, overview and app windows following the fingers, the switcher, search, the launcher, Split View, and the presentation switch.
   - Measure first, on the tablet, before and after each fix:
     - prior work and tools are in `D:\androidlinux\research\smooth-frames.md`, `tools/tab/smooth-sample.sh` and `tools/smooth-analyze.py` (vblank, flips, GPU jobs, GPU/CPU frequencies);
     - also use deniald's render audit (`docs/RENDER_AUDIT.md`) and Flutter frame timings.
   - Find the real causes: blur cost, too many layers, shader compilation (jank on first use), CPU or GPU frequency ramp, scheduling, client buffers, allocation on the frame path, and so on. Fix them properly.
   - Report per-animation numbers (frames presented / vblanks, worst gap) before and after.
3. **"Window search in the multitasking menu must go over the active apps."**
   - The overview (three fingers up) searches only what is open: running apps and their windows.
   - It no longer lists apps to launch. Launching is the job of the one search in 4.
4. **"Super and Alt+F: search must be one, not two different ones."**
   - One search UI (Spotlight-like) for every entry point: a bare Super tap, Alt+F in the Mac preset, Super+S, and four fingers up.
   - The separate small launcher strip goes away in the desktop presentation, replaced by this search.
   - With an empty query it shows recent apps and the full app list (Launchpad-like, scrollable grid). Typing filters apps first and open windows second. Enter launches or switches.
   - In the tablet presentation, the drawer search and the pull-down search use the same component.
   - **One search backend, not only one UI** (owner's clarification, 2026-11-24). eb18 has two: the shared search model (`searchShell`, eb18 `f5e5d84`, with English-name matching) and the old matching inside the `denial_launcher` plugin (`plugins/denial_launcher/lib/src/launcher_components.dart`, its own substring filter over app id, name, categories and keywords), plus any other separate filter, for example in the tablet drawer.
     - Exactly one backend: one model for app indexing, matching and ranking, and one for open windows. Every entry point uses it: bare Super, Alt+F, Super+S, four fingers up, the overview (restricted to open apps and windows), the tablet drawer and the pull-down search.
     - The old launcher's own matching is removed or replaced, so no second code path filters apps anywhere. A component that has to stay for other reasons calls the shared backend.
     - A test fails if a second matcher is introduced or used, for example one asserting that every search UI takes its results from the shared backend.
5. **"After opening windows 50/50 I must be able to resize them with the mouse, and resizing one window resizes the other so both fill the screen. With the mouse I must also be able to detach a window from this mode back to full screen, by dragging it out in the three-fingers-up view. Now that only works by dropping it into the narrow gap between two full-screen windows."**
   - **Resize from the window's own edge.** Tiled clients send `xdg_toplevel.resize` (and X11 equivalents) when their client-side edge is dragged, and today those requests are refused. Turn such a request on a shared edge into a drag of that split, so both windows resize and together fill the screen.
   - **The divider zone itself** must be easy to hit with the touchpad cursor: a resize cursor on hover, at least 16 logical px.
   - **Verify with real clients** (GTK4 with CSD, Firefox, an X11 app) and a real pointer, not only the virtual mouse.
   - **Detach in the overview.** Dragging a window out of a split card and dropping it anywhere that is not another card makes it its own full-screen screen, placed right after its former screen. That covers empty overview space, the margins, and below or above the cards.
     - A clear drop hint shows while dragging, for example a "new screen" placeholder that appears as soon as the window leaves its card.
     - The gap drop for exact placement stays.
6. **"There are bugs with windows when switching from the tablet to the desktop presentation. This switch must be seamless."**
   - Reproduce with several apps open, including a Split View pair in the tablet presentation and a split screen in the desktop one, in both directions, using `erhai-pogo-replug` and the tile.
   - Requirements:
     - no window lost, duplicated, off-screen, black or wrongly sized;
     - focus and order kept: the tablet's current app becomes the current screen;
     - Split View maps to a split screen and back;
     - floating dialogs stay with their parents;
     - the change is animated smoothly at 120 fps, without flashes of the wallpaper or a lock-screen flicker.
   - Write down each bug found with its cause and fix.
7. **"This panel in the desktop presentation must not slide out from the side when the mouse reaches the left part of the screen. It should open on a click on a new icon or the clock (the new icon means a control center) and slide out from the top."** (added 2026-11-24)
   - "This panel" is read as Denial's desktop Dashboard (notifications, quick settings, the «Мобильный режим» button), opened today by the hover edge trigger (`plugins/denial_desktop/lib/src/desktop/desktop_workspace.dart`, `desktop_panel_edges.dart`) and by the clock in `denial_top_bar`. If a left-edge hover opens another panel, the same rule applies to it.
   - Like the macOS Control Center:
     - No hover-to-open in the desktop presentation: no edge hover trigger and no pointer edge swipe. A pointer never opens it by accident. Whether a finger swipe from the top edge still opens it in the desktop presentation is the builder's call.
     - A new control-center icon in the top bar near the clock (a glyph like macOS's two toggles; Denial's icon set if a fitting one exists). Clicking it or the clock toggles the panel.
     - The panel drops down from the top, anchored under the icon at the top right, and opens and closes with a smooth 120 fps animation. A click outside, Esc or a second click on the icon closes it.
   - The tablet presentation's top shade stays as it is.
   - Old settings (dashboard placement or hover keys in `settings.json`) do not bring back the side hover in the desktop presentation. Rollback safety as for the other keys.
   - Tests, and a section of `eb19-check.sh` with the virtual mouse: a hover at the left edge opens nothing; a click on the icon drops the panel from the top.
   - Decided while building (track C, `eb/control-center`):
     - A finger still opens it in the desktop presentation: a swipe down from the top edge over the panel, up to the screen's right corner, as the top-right corner opens Control Center on an iPad. Only touch: deniald hands only touch contacts to edge swipes, and the shell's strip takes only touch, so a mouse or touchpad never opens it from an edge.
     - It rests under the bar's trailing end and comes out from under the bar, clipped at the bar's edge, so it never crosses the bar's cards. A bar on another side works the same way (up from a bottom bar, sideways from a side bar); with the bar hidden it drops from the top right. Its size and edge distance stay configurable; Settings no longer offers its anchor and hover trigger (`denial-apps` `eb/control-center`), and the keys stay in the file untouched for older builds.
     - Motion: 280 ms ease-out in, 200 ms ease-in out, one translation of the painted panel under its one glass blur; the panel is built offstage once the shell is idle after it starts, so the first opening does not build it.
     - It takes the keyboard when it opens (Escape closes it, Tab walks it), and the icon stays lit while it is open. While it is open the dismiss barrier lies over the bar, so a click on the battery or another bar card only closes it (macOS would also act on that card).
8. **"I set scale to 200% and the screen to 100%. Having two different settings is not convenient at all, and there are probably more settings tied to them."** (added 2026-11-24; on the tablet then: `scale=DSI-1,2` in `outputs.conf`, `apps.scale` 1.0)
   - Today several independent controls decide how big things look (denial-apps `apps/settings/src`): the display's «Масштаб» / «Свой масштаб» (output scale, `denial.rs` `try_scale`); «Размер приложений» (`apps.scale`, `settings/panel.rs` `APP_SIZES` 1.0–3.0, a multiplier for apps over the shell); the Android «Размер» (`settings/android.rs`, Small/Default/Large/Larger, `DEFAULT_DPI` 230 per unit of scale, through `droidloom::set_density`/`set_densities`; Droidloom ignores `apps.scale`, so Android apps came out about 1.2× bigger than GTK in eb18); `appearance.cursorSize`.
   - Like macOS "Larger text / More space", iPadOS Display Zoom and Android "Display size":
     1. One control per display, «Масштаб»: a picker of a few sensible steps, each saying what it looks like ("выглядит как 1357×960"), the default marked. It scales everything together: the shell, Wayland apps, X11 apps through Xwayland, Android apps and the cursor.
     2. «Размер приложений» leaves Settings; `apps.scale` stays 1.0 in effect. Existing documents migrate by folding the old product into the display scale, so nobody's look jumps on upgrade. Rollback safety: eb18 and eb17 still load the files and look the same (as eb18's explicit scale line did).
     3. Android follows the same scale by itself and matches GTK text size at every step, verified on the tablet with screenshots of Android «Настройки» or «Файлы» next to a GTK app (`DEFAULT_DPI` adjusted if needed). The separate Android «Размер» picker goes, or becomes a text-size preference if Android needs one; the builder says which and why.
     4. The cursor's logical size stays constant across scales. The cursor-size choice goes if redundant or stays as an accessibility option (builder's call, documented).
     5. Every other setting that depends on scale (corner radii, bar thickness, Xwayland DPI, the lock screen, the tablet presentation's touch targets) stays consistent after one scale change.
   - Tests for the migration and the single control; on-tablet screenshots at two scale steps in `eb19-check.sh`.

## Both presentations, and the tablet not left behind (owner, 2026-11-25)

Owner, translated: "the tablet presentation is my main mode, so the most important thing is to get it right with the new features: no bugs, ease of use, and so on. Don't neglect it. One of the goals was to improve the tablet mode based on the new desktop work." Then: "Not only in the tablet mode: it has to work in both the tablet and the desktop mode."

- Every eb19 feature works and is verified in both presentations: the tablet one with fingers, the desktop one with keyboard, touchpad and mouse, touch still working there. eb19 is done only when both pass their checks; neither is judged alone.
- A dedicated track (T) makes sure the tablet presentation, the owner's everyday mode, is not left behind: it gets the full finger-only pass below. That pass does not replace any desktop verification.
- Every eb19 feature that applies to the tablet works and feels right there, verified on the device with fingers: «Закрыть все», the one search (drawer and pull-down), the one scale (Android text against GTK, touch targets), 120 fps for the tablet's own animations (home, drawer, Recents, the bottom pill's gestures, back, the shade, Split View enter, resize and exit, app open and close), the switch in both directions, and Split View with the eb19 split improvements. The glass stays.
- A finger-only usability and bug pass as a demanding iPad user would make it: unlock and home; opening apps from home, the drawer and search; switching with the pill and Recents; Split View; notifications and quick settings in the shade; the on-screen keyboard in GTK, Firefox and Android apps; rotation; the lock screen; closing apps. Bugs and rough edges are fixed properly; what is left is listed with its reason.
- When a tablet item and a desktop item compete for the tablet or for build time, the tablet item may go first, but no desktop item is skipped.

Delivery as before: package `denial 0.6.8-1+eb19`. Build, install and verify on the tablet autonomously, under the same permissions and limits (no partitions, no reboots, battery ≥ 40 %, Stay awake only during tests). Merge into the forks' `eb/main` once verified on the tablet. End state as for eb18.
