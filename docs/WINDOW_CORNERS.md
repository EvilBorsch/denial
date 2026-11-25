# Square windows and the rounded window frame (eb20)

The tablet's owner: "It annoys me that windows have rounded corners and this
border. Add a setting to turn it off, and make it off by default." And then:
"A lot of free space around the windows' corners goes to waste. If it's
square, that's fine."

## The setting

| Key | Default | Meaning |
|---|---|---|
| `appearance.roundedWindowFrame` | `false` | Rounded window corners, the window frame's line and the padding around windows. |
| `appearance.windowCornerRadiusScale` | `0.5` | How round window corners are while the frame is rounded, 0 to 2 (28 px × scale). |

Settings shows one switch, «Скруглённые углы и рамка окон» ("Rounded window
corners and border") on the Wallpaper and style page. The window roundness
slider, the focused-window border switch and the maximized-window padding
slider show only while it is on.

`appearance.cornerRadiusScale` ("Roundness") rounds the shell's own surfaces
only: panels, cards, tiles, notifications. `monitorCornerRadiusScale` is the
screen corners, as before.

## Defaults and older documents

A missing `roundedWindowFrame` reads as `false`, so new users and every
document written before eb20 get square windows. Nothing is migrated: the
owner's `cornerRadiusScale` 1.6 and `focusedWindowBorderEnabled` false stay as
they are. `focusedWindowBorderEnabled` keeps its meaning (the accent around the
focused window) and takes effect only while the frame is rounded.

Rollback: eb19 and earlier ignore the two keys and keep them in the file (the
shell merges its projection into the stored document), so a rollback shows the
old rounded look and a return to eb20 the owner's choice.

## What follows the windows' setting

Square while the frame is off:

- every client window's corners, its shadow's corners and its frame, in both
  presentations: screens, splits, floating windows and dialogs, windows in the
  desktop overview, apps sliding side by side on the tablet, a Split View app
  lifted by its handle;
- the frame's line: no hairline and no accent, only the frame surface
  (`windowFrameSurface`); a pinned window keeps its mark.

Kept by the shell's roundness, as shell surfaces previewing windows: the
tablet's Recents cards, the app-launch flight's card, the desktop overview's
screen cards and their drop slot.

## Using the whole screen

Square windows waste no space (geometry, not a clip, so clients are configured
to the larger size):

- Desktop: the shell sends deniald a window padding of 0
  (`ShellRuntimeBindings`), and deniald's layouts use that padding as the gap
  between tiles too. Maximized windows and screens of the full-screen apps
  layout fill the work area edge to edge; split tiles meet. Their 1 px frames
  make a 2 px line between them. A tile that decorates itself has no shell
  frame, so the shell draws the same 1 px edge over its border: every seam is
  the same two frames. Tiles of the full-screen apps layout drop their shadow,
  which would fall on the neighbour; floating windows keep it.
- The divider's zone stays 16 px (24 px for a finger) around the seam: it
  reaches 8 px into each tile (deniald `dividers.rs`).
- Tablet: deniald lays a Split View pair 2 px apart
  (`SQUARE_SPLIT_VIEW_GAP`) instead of 10, and the shell draws its divider in
  that gap. deniald follows the setting at start and after every settings
  change (`synchronize_window_corners`) and lays the pairs out again.

Turned on, everything comes back as it was: rounded corners, the hairline and
the focused-window accent, the padding from `layout.maximizePadding`, the
10 px Split View divider.

Open: dwindle and scrolling layouts report no tile flag to the shell, so their
self-decorated tiles get no drawn edge and their framed tiles keep the shadow.

Checked on the tablet by `tools/tab/eb20-check-corners.sh` in the workspace.
