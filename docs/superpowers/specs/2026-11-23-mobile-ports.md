# Tablet (mobile) presentation: what eb17/eb18 brings to fingers

Date: 2026-11-23 (night). Track C of eb18, branch `eb/tablet-ports`. Parent
design: `2026-11-23-full-screen-apps-layout-design.md`, section "Tablet
(mobile) presentation: fingers only, a full track". Every decision here is
the agent's call (the owner asked for autonomous work); the owner's settled
rule is quoted where it decides something.

The owner's rule for this presentation: "In tablet mode you work only with a
finger, without keyboard or mouse, so there is no point improving keyboard
things for it." So nothing below adds keyboard, touchpad or pointer
behaviour to the tablet presentation.

## The panel

OnePlus Pad 3: 3392x2400 at 13.2" (315 ppi), landscape with its cover. In
eb18 the shell runs at output scale 2.5 (`eb/tablet-density`, 1357x960
logical px; eb17 ran it at 1.5), apps at 3.0. One logical shell pixel is
then about 0.20 mm, as an iPad Pro point (0.19 mm): iPadOS' sizes apply
as they are, a 44 px finger target and 17 px body text. Sizes below are at
2.5. The eb17 screenshots `m*.png` were taken at 1.5, where everything was
40% smaller; `s04-home-2.5.png` shows home at 2.5 (6 columns).

## Audit: the tablet presentation as eb17 left it

Baseline screenshots: `D:\androidlinux\device-logs\eb18-baseline\m*.png`.

| Area | Today (eb17) | Finger feature in eb17/eb18 or iPadOS it lacks |
|---|---|---|
| Home grid (`launcher/home_surface.dart`, `home_pager.dart`) | At 2.5: 6 columns, icons 85 px (17 mm), labels 13 px (s04). Long press on the background opens the page editor. | Nothing at 2.5 (at 1.5 the labels were too small; the scale change fixed that). |
| App drawer (`launcher/widgets/home_app_drawer.dart`) | Exists but is off by default (page editor switch, stored as `drawer` in the home layout file). A swipe up on home does nothing (m05). Alphabetical grid, no search. | iPadOS App Library has a search field; eb18 desktop gets search in the overview. |
| Search | None in the tablet presentation. | iPadOS: a pull down on home opens Spotlight. eb18 desktop: the overview's search field and the global overlay, both on the shared `searchShell` (apps and open windows). |
| Recents (`state/app_deck.dart`, `widgets/overview/app_deck_layer.dart`) | A landscape stack carousel, one card per window, label above it: app icon and app name, 17 px. Tap opens, fling up closes the window, tap beside goes home. | Windows of one app are scattered by recency and look alike: only the app name, no window title (eb18 desktop: app windows view with titles). No way to close an app with several windows at once. |
| Bottom pill (`widgets/bottom_gesture_handle.dart`) | Up: home; hold: Recents; sideways: next/previous app. | Equivalent to the screens layout's three-finger swipes; nothing to port. |
| Edges | Left/right edge: Back. Top: the shade (notifications left, quick settings right). | Nothing to port. |
| Shade | Tiles and labels fine at 2.5 (s05). | Nothing. |
| Split screen | None: every app fills the screen, one at a time. | eb17 desktop: screens with splits, dividers. iPadOS: Split View (two apps side by side, a divider with thirds and halves, drag an app off by its top handle). |
| App windows view (eb18 desktop, three fingers down) | None. | Recents grouping covers it for fingers. |

## Ports chosen

### 1. Search by finger

- **A search field at the top of the app drawer.** Empty, the drawer shows
  every app alphabetically, as now. Typing replaces the grid with results
  from the shared `searchShell` (package `denial_flutter_sdk/launcher.dart`):
  matching open windows first (one finger-sized row each: app icon, app name
  and window title), then matching apps (tiles, best first). A tap on a
  window brings it to the front (as a Recents card does); a tap on an app
  starts it (as its home icon does). Enter on the keyboard acts on
  `ShellSearchResults.first`.
- **Pull down on home opens search, as on iPadOS.** A downward drag on the
  home grid (not from the top edge, which stays the shade's) pulls a search
  panel down from the top, following the finger; released past a third of
  its travel or flicked, it opens, otherwise it springs back. Open, its
  field has focus and the shell's on-screen keyboard comes up. Empty, it
  shows the open windows (most recent first) and the recently started apps
  (iPadOS' suggestions), so a pull down alone already finds a window.
- The two share one results widget and one keyboard policy: while a field
  has focus the shell captures the keyboard (`ShellInputRegion` with
  `ShellKeyboardPolicy.capture`) and opens the edge panel keyboard; closing
  the drawer or panel, Back, or a launch closes the keyboard.
- Result rows are 64 px high (13 mm) with a 44 px icon, app name 17 px,
  window title 15 px; app tiles are the home tiles.

### 2. Drawer on by default

- The home layout file (`~/.config/denia-home/layout.json`, read by
  `HomeLayoutRepository`) has stored `drawer` on every save since the
  switch existed, so a stored `false` cannot be told from the default.
  New rule: the file gets `"drawerChosen": true` once the user flips the
  switch in the page editor. A file without it (every file written so far)
  is read as "not chosen": a stored `drawer: true` stays on (only a user
  could have set it), a stored `false` becomes the new default, on. The
  owner never turned it on (m05), so for them it simply appears.
- An explicit choice made from eb18 on stays as chosen.
- It disturbs no home layout: the drawer is a separate sheet over home and
  moves no item; a swipe up on home was unused (m05).
- Rollback: eb17's shell reads `drawer` and ignores `drawerChosen`. eb18
  writes `drawer` as the effective value, so after a rollback the drawer
  stays as the user last saw it.

### 3. Recents: windows of one app together

- When Recents opens, its row groups the windows of one app next to each
  other: apps in the order of their most recent window, an app's windows in
  their own order, the window in front last. The cards slide into place as
  they shrink. The card in the middle is the app used before the one in
  front, as before.
- The home pill's sideways quick switch keeps the order the apps were in
  front in, so the app used before is always one swipe away, even when the
  app in front has several windows (grouping that row too would put the
  app's other window first).
- A card whose app has more than one window shows two lines above it: the
  app name, and that window's title under it, so cards of one app tell
  apart. A card of a single-window app keeps one line, as now (48 px icon,
  17 px name; the title line is 14 px).
- Cards of a multi-window app carry a "close all" button (× and the count,
  44 px tall) at the end of their label: it closes every window of the
  app, each card on screen leaving as a flung one does. Flinging one card
  closes that window, as now.

## Split View (iPadOS-like), two apps side by side

### Where the split lives: deniald

deniald already owns every phone window's configured size
(`insets.rs::mobile_window_geometry`: the output below the status bar,
fullscreen, desks, rotation, the switch to and from desktop). A split is a
change of exactly that rectangle, so it lives there: per phone output one
optional pair (left window, right window, the left share). deniald
configures each half, keeps it across rotation and status-bar changes and
dissolves the pair when one window closes, moves to a desk, or the
presentation leaves mobile. If the shell placed the windows instead, deniald
would have to accept shell rectangles in the mobile presentation and the
shell would have to recompute them on every output change, racing the
client's configure.

The screens layout's join logic (`screens.rs`, `window_layout.rs` split
trees, `dividers.rs`) manages workspaces of tiles with pointer-driven
dividers in the desktop presentation, and window layouts do not apply in
the mobile presentation. Of it, the split geometry itself is reused: the
pair's halves come from `window_layout::split_geometry_on_axis` (the same
gap handling and 10–90% clamp as every desktop split). Its dividers are not
reused: in the tablet presentation the shell owns touches over its own
regions, so the divider is a shell widget.

The shell owns presentation: drawing the two windows, the divider, the
handles and Recents.

### Wire (append-only, one commit)

- `WindowRequestKind.SplitView = 14`: `window_id` and `target_window_id`
  become a pair; `screen_side` 0 puts `window_id` on the left, 1 on the
  right; the new `WindowRequest.split_ratio` is the left window's share
  (snapped by the shell to 1/3, 1/2 or 2/3). Sent again for a pair, it
  changes the share or swaps the sides. A window in another pair leaves it
  first.
- `WindowRequestKind.LeaveSplitView = 15`: `window_id`'s pair dissolves;
  both windows fill the screen again.
- `Window.split_view_partner_id` (object id of the other window, 0 when
  none) and `Window.split_view_ratio` (the left share; 0 when none).
- An older deniald rejects the unknown request kinds as malformed input
  for that request only (the shell never sends them unless deniald
  published a split); an older shell ignores the new fields.

### Behaviour

- **Entering, from Recents.** Long press a card: it lifts (haptic tick),
  and the screen's left and right halves become drop zones labelled "Split
  with <app in front>". Drag the card into one and release: the card's
  window takes that side, the app that was in front the other, at 1/2, and
  Recents closes on the pair. Released elsewhere, the card settles back.
  Without an app in front (Recents opened from home) or on the front app's
  own card there is no one to split with and the long press does nothing
  but the lift.
- **The divider** is a dark bar between the windows with a grab handle;
  its touch zone is 44 px wide. Dragging it, both windows are covered by
  their app icon on glass (as on iPadOS, the apps do not resize under the
  finger) and the bar follows the finger. Released, it snaps to the nearest
  of 1/3, 1/2 and 2/3; dragged within 12% of an edge, the window on that
  side leaves the split and the other fills the screen. The covers fade out
  once both windows have their new size.
- **The handle** at the top of each half (a short bar in the status strip,
  44 px touch zone): dragging it moves that window with the finger,
  scaled down. Released over the other half, the two swap sides. Pulled
  down more than a quarter of the screen and released, the window leaves the
  split and fills the screen in front; the other goes to Recents. Otherwise
  it settles back.
- **Closing one side:** when either window closes (the app quits, or its
  card is flung in Recents), the other fills the screen.
- **Recents and switching:** a pair is one card, both windows drawn at
  their place; tapping it brings the pair back, flinging it closes both,
  and the pill moves between it and other apps like any app. Going home
  minimizes both, as leaving any app does; bringing one back restores its
  partner too.
- **Focus:** the window touched last has the keyboard focus; the other
  keeps running and drawing.
- **Fullscreen:** a split window that asks for fullscreen (a video) fills
  the screen while it is fullscreen; the pair resumes when it leaves
  fullscreen.

## Left out, and why

- Keyboard, touchpad and pointer features (Alt+Tab, the Mac preset, search
  on a key, touchpad swipes, the middle-button drag): the owner's rule.
- Three- and four-finger touchscreen gestures of the screens layout: the
  bottom pill already moves between apps, opens Recents and goes home, and
  multi-finger swipes would steal touches from apps (maps, drawing,
  Android games).
- More than two windows in a split, and top/bottom splits: on a 13" panel
  two halves keep finger-sized controls in the apps; quarters would not. iPadOS' Split View is two apps too.
- Slide Over (a floating narrow app over another): no floating windows in
  the tablet presentation today; a separate feature.
- Dragging an app from the drawer or a search result into a split: the
  Recents entry is the one way in for now.
- Enlarging anything for the old 1.5 scale: eb18's 2.5 makes the shell
  iPad-sized.
