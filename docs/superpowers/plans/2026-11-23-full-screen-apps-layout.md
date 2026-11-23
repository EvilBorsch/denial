# Full-screen apps layout ("screens"): implementation plan

Design: `docs/superpowers/specs/2026-11-23-full-screen-apps-layout-design.md`.
Branches: `EvilBorsch/denial` and `EvilBorsch/denial-apps`, `eb/screens-layout`.
Package: `denial 0.6.8-1+eb17`.

Baseline on the untouched base (denial `ccadf12`, denial-apps `c1d0137`):
`deniald` 764 of 769 pass (the 4 known qemu/WSL failures, 1 ignored);
`dart_shell` 261 pass, the 12 known failures; SDK 111 pass.

Stages, each building and passing the suites on its own.

## Stage 1: the layout, gestures, settings

1. `deniald` layout (`window_layout.rs`): `WindowLayoutKind::Screens`
   (`"screens"`), the scrolling strip in a screens mode. Every column is one
   screen at the full work-area width; no maximize, no column or lone-tile
   resizing, at most four tiles per screen. Tests: insert beside the current
   screen, close (focus left, else right), join on each side, separate,
   reorder, snap.
2. Settings (`settings.rs`): accept `screens`. On disk the document keeps a
   value every older `deniald` accepts (`windowLayout: "scrolling"`) and the
   real one in `layout.windowLayoutVariant`; served documents carry
   `"screens"`. Workspace settings are effectively off in this layout; the
   user's own `workspacesEnabled` stays as it is.
3. Frontend: switching into the layout gathers windows workspace by
   workspace in their order; floating windows stay over their screen while
   the strip moves.
4. Gestures: `ShortcutGesture::ThreeFingerSwipeDown`; in this layout 3
   fingers left/right always scroll the strip, 3 up opens the screens
   overview, 3 down the app windows, 4 up the launcher, other 4-finger
   swipes do nothing (`shell action AppWindows` on the wire).
5. SDK and shell: `DesktopWindowLayout.screens`, l10n; workspace UI hidden.
6. Settings app: the option on "Window layout" and "Monitor", Russian.

## Stage 2: the screens overview

1. Wire: each window carries its screen (one-based) and that screen's real
   rectangle; requests `JoinScreen` (window, target tile, side) and
   `MoveToScreen` (window, beside which screen, before/after).
2. Shell: overview cards per screen in strip order, single-window screens
   of one app collapsed into a stack with a count; drag a window onto a
   card side to join, into a gap to separate or reorder; highlight the
   landing area; tap goes to the screen; keyboard as in the overview.

## Stage 3: app windows and the divider

1. Shell: three fingers down shows every window of the focused app, most
   recent first, as the stacking overview does.
2. `deniald`: split dividers from the layout tree; a plain-mouse or finger
   drag on a divider (16 px zone) moves it, a double click or tap resets the
   split to equal sizes; a resize cursor on hover.

## Delivery

Package with `tools/eb-repack-deb`, `tools/tab/install-denial-eb17.sh`,
`tools/tab/eb17-check.sh` with a virtual touchpad in `tools/tab/vinput.py`,
the owner's checklist, a CHANGES entry and branch bundles.
