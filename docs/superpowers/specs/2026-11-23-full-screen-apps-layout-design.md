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
