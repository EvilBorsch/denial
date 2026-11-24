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

### Recents: «Close all» (eb19)

The owner: "in the tablet presentation, a button at the bottom to close the
active windows instead of swiping each one away" (design, iteration 3,
point 1).

- **The button.** «Закрыть все» / "Close all" / «全部关闭», a pill 48 px tall
  (about 10 mm at the 2.5 scale, Material's touch target) and at least
  136 px wide, centred in the band between the cards and the bottom
  gesture's area, at least 16 px clear of that area, so a tap on it is
  never taken for the home swipe. It fades in and out with the cards'
  labels, dims while pressed, and shows only while Recents holds a card;
  with no apps Recents shows "No recent apps" as before.
- **What it closes.** Every card in Recents: each window of an app whose
  windows are grouped (each its own card), both apps of a Split View pair
  and the windows riding on a card (dialogs), Android (Droidloom) windows
  alike. Each gets the close request a swiped card's app gets (the
  compositor's `CloseWindow`: `xdg_toplevel.close`, `WM_DELETE_WINDOW` for
  X11), once its card has left the screen. Nothing is killed.
- **The motion.** Every card leaves the row where it is drawn and flies
  straight up as a flung card does; Recents goes home at once behind them
  (the scrim fades, home comes in), so the cards fly out over home. The
  deck keeps drawing a leaving card where it left, whatever Recents does
  meanwhile, until it is gone.
- **An app that asks first.** An app may answer the close request with a
  question, such as GNOME Text Editor's "Save changes?", and keep its
  window open. Recents takes an app for one that asks when it opens a
  window over its card (a dialog of its own: it counts at once) or still
  has a window of the card open a second after the last app closed with it
  (dialogs drawn inside the window, as libadwaita's). Such an app:
  - is back in Recents at once, never hidden away as a closed app (before
    eb19 a swiped app that kept its window vanished from Recents and the
    app switcher until it closed);
  - after «Close all», or whenever Recents has gone home meanwhile, comes
    to the front with its question, opening as from its home icon, so the
    question is neither hidden nor lost. With several, the one used last
    comes first, and each next one once the one in front has closed;
  - while Recents is still open (one card flung of several), only comes
    back to the row: Recents does not pull the user out of it;
  - and when the user turns elsewhere (home, another app), the rest stay in
    Recents without coming forward.

  A window of an app being closed from Recents never comes to the front
  by the compositor's focus fallback as the others close.

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
  (the shell sends 1/3, 1/2 or 2/3). Sent again for a pair, it changes the
  share or swaps the sides. A window in another pair leaves it first.
- `WindowRequestKind.LeaveSplitView = 15`: `window_id`'s pair dissolves;
  both windows fill the screen again.
- `Window.split_view_partner_id` (object id of the other window, 0 when
  none) and `Window.split_view_ratio` (the left share; 0 when none).
- An older deniald rejects the unknown request kinds as malformed input
  for that request only; a newer shell sends them only from Split View's
  controls, which appear only once deniald publishes a pair's fields
  (the Recents drop is the exception: against an older deniald its pair
  never forms, and after a second Recents opens the card alone). An older
  shell ignores the new fields. Nothing about pairs is persisted.

### Behaviour

- **A pair is one card.** In Recents and for the home pill's quick
  switch, the two windows share one card (held by the window with the
  lower object id), drawn side by side on the divider's dark bar, and
  labelled with both apps, left first. Tapping it brings the pair back
  with the app touched last in front; flinging it closes both; it is never
  grouped with other cards of its apps.
- **Entering, from Recents.** Long press a card: it lifts (haptic tick)
  and follows the finger, and the screen's left and right edges (30% of
  the width each) become drop zones labelled "Side by side with <app in
  front>". Released over one, the card's window takes that side and the
  app that was in front the other, at 1/2; Recents opens on the pair once
  deniald has made it (or opens the card alone after a second). Released
  elsewhere, the card settles back. The front app's own card, and every
  card when Recents was opened from home or beside a desk, has no lift: a
  long press stays a tap.
- **The divider** is the dark gap between the windows with a grab bar;
  its touch zone is 44 px wide. Dragging it, both apps are covered by
  their icons (as on iPadOS, the apps do not resize under the finger) and
  the bar follows the finger. Released, it rests at the nearest of 1/3,
  1/2 and 2/3 (a fling carries it on); dragged within 12% of an edge, the
  app on that side leaves the pair and the other fills the screen. The
  covers go once both apps have drawn their new widths, or after 0.7 s.
- **The handle** at the top of each half (a short bar just below the
  status bar, 96x36 px touch zone): dragging it lifts that app, which
  follows the finger, a little smaller. Released with its middle over the
  other half, the two swap sides, each keeping its width. Pulled down more
  than a quarter of the screen, it leaves the pair and fills the screen in
  front; the other app leaves the screen as an app left for another does
  (minimized, still in Recents). Otherwise it settles back.
- **Closing one side:** when either window closes (the app quits),
  deniald gives the other the whole screen.
- **Leaving and coming back:** going home or to another app minimizes
  both (deniald minimizes a pair as one); bringing either back restores
  both.
- **Focus:** a touch on either app gives it the keyboard; the other is
  not minimized and keeps drawing.
- **Fullscreen:** a split window that asks for fullscreen (a video) fills
  the screen while it is fullscreen; the pair resumes after.
- **Touches:** both windows take touches in their halves, dialogs over
  them above them; the divider and the handles are the shell's.

## Other finger improvements (item 4)

- **Back closes the drawer and search.** On home the system Back edge
  swipe did nothing; with the drawer or the pull-down search open it now
  closes the on-screen keyboard first, then the sheet, as Android's Back
  does.
- Finger targets of the new controls follow iPadOS at the eb18 scale: 64
  px search rows, 44 px close-all and divider zones, a 96x36 px handle
  zone.

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
