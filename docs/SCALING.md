# Initial scaling architecture

## Rule

Denial coordinates remain logical. Output scale only converts logical pixels to
physical pixels. We must never enlarge the finished desktop or Flutter image.

`OutputSpec.scale_120` stays the source of truth. The shared atlas uses the
largest output scale as `engine_scale_120`.

## Original bug

The atlas is already allocated at the scaled physical size, but the embedder
reports `pixel_ratio: 1.0` to Flutter. At 1.5x, Flutter therefore sees the
physical atlas size as its logical size while Dart lays out the smaller logical
desktop inside it. The remaining area is black.

## Flutter

- Keep the Flutter backing store at the atlas physical size.
- Send that physical width and height in both Flutter display and window
  metrics.
- Send `device_pixel_ratio` and `pixel_ratio` equal to the atlas engine scale.
- Keep scene geometry in logical coordinates. Flutter will lay out at the
  logical desktop size and rasterize directly at physical resolution.
- Send embedder pointer events in physical atlas pixels, as required by
  `FlutterPointerEvent`; Flutter converts them using the device pixel ratio.
- Keep structured cursor-position messages consumed directly by Dart in
  logical scene coordinates because they bypass Flutter's pointer conversion.

This requires no Dart transform and no scaling of Flutter's finished image.

## Pointer motion

Relative pointer deltas from libinput (mice, touchpads) move the pointer in
logical pixels, as in other Wayland compositors, and `zwp_relative_pointer_v1`
reports them unchanged. The output scale does not slow the pointer down: at
1.5x a touchpad stroke crosses the same share of the screen as at 1x.

## Native Wayland applications

- Register `wp_fractional_scale_manager_v1`; `wp_viewporter` already exists.
- Select a surface's preferred output with the same output-membership rule used
  for placement and presentation.
- Send that output's exact scale to the root surface and its surface tree when
  the window maps, moves to another output, or the topology changes.
- Keep toplevel sizes and positions logical. The client chooses the buffer size.

Fractional-aware clients will render at the requested scale. Older clients will
receive Smithay's existing integer ceiling through `wl_output` (2x for a 1.5x
output), then Denial will downsample their larger buffer. We should not upscale a
1x client buffer as the default policy.

## X11 applications

Xwayland is one X server, so it cannot use a different coordinate scale for each
X11 window. Use one stable session-wide Xwayland scale:

- Choose the ceiling of the largest output scale.
- Set Smithay's Xwayland `CompositorClientState` client scale before starting
  the X window manager. This maps the larger X11 buffer coordinates back to
  Denial's logical coordinates.
- Start Xwayland with matching DPI (`96 * xwayland_scale`).
- Publish matching `Xft/DPI` through XSettings when the X window manager starts.
- On a runtime topology-scale change, update the client scale and XSettings as
  one transaction, republish output state, and reconfigure managed X11 windows.

For 1.5x this asks X11 applications to render at 2x and downsamples to 1.5x. It
costs buffer memory but remains sharp and gives DPI-aware applications normal
logical sizing. Applications that ignore all X11 DPI hints cannot be fixed
without either appearing small or being blurred; Denial should not silently
choose blur for every X11 application.

## Initial implementation

1. Flutter metrics carry the atlas scale, removing the black area and keeping
   the shell sharp at 1.5x.
2. Native Wayland clients receive fractional-scale advertisement and surface
   updates.
3. Xwayland receives the global integer scale and matching DPI policy.

The initial version has been exercised at 1.5x. Follow-up validation should
cover 1x and mixed-scale outputs, moving Wayland and X11 windows between
outputs, and changing scale at runtime.

## One scale per display

Each display has one scale, and it sizes everything on it together: the
shell, Wayland apps, X11 apps through Xwayland's DPI and XSETTINGS, Android
apps through Droidloom's density per unit of scale, and the cursor, whose
size (`appearance.cursorSize`) is in logical pixels and so keeps its look
at every scale. Settings offers it as «Масштаб» on the Display page for the
built-in panel, on the Monitor page for a monitor, and on Displays for any
display: the quarter steps whose logical short side lies between 720 (a
small tablet) and 1440 (a large desktop), each with what the screen looks
like, the default marked. `outputs.get` names each output's
`default_scale`: a built-in panel's density scale, 1 for others.

`apps.scale` once drew apps larger than the shell. When deniald starts with
it above 1, it folds it into the scale of every display it knows (connected,
or remembered in the output config), writes explicit `scale=` lines and
drops the key, so apps keep their size and the shell joins them
(`compositor/src/bin/deniald/scale_fold.rs`). A running session takes no
new apps scale. Older deniald builds read the explicit scale lines and a
missing apps scale as 1, so a rollback looks the same. A display first
connected after the fold, with no saved scale, starts at its default.
