//! Split dividers: the gap between the two sides of a split, which a plain
//! mouse drag or a finger moves and a double click or double tap evens out.
//!
//! Every managed layout shares the split trees (`DwindleNode`), so Dwindle,
//! scrolling columns and the screens of the full-screen apps layout all get
//! the same dividers. A gap between scrolling columns is no divider. The gap
//! is `layout.maximizePadding` wide; the zone a press takes is at least
//! [`DIVIDER_ZONE`] wide, centred on it, so it reaches a few pixels into the
//! tiles beside it.
//!
//! The shell owns the scene between windows (its input layout gives it
//! everything no window covers), so the gap itself is the shell's desktop
//! background. That lies beneath the tiles, not above them: a press the
//! shell has in the gap still takes the divider when nothing lies above the
//! tiles on both sides of it ([`divider_press_reachable`]).
//!
//! A tiled client may also ask to be resized from one of its own edges
//! (`xdg_toplevel.resize`, an X11 client's `_NET_WM_MOVERESIZE`). The edge
//! it names is a divider when a split neighbour shares it
//! ([`edge_dividers`]): the request then drags that split, as a press on
//! the divider would, so both sides keep filling the screen. A corner
//! drags the split on each of its two edges. An edge on the screen's outer
//! border has nothing to give way and stays put.

use std::time::{Duration, Instant};

use smithay::desktop::Window;
use smithay::reexports::wayland_server::Resource;
use smithay::reexports::wayland_server::backend::ObjectId;
use smithay::utils::{Logical, Point, Rectangle, Size};

use super::super::window_layout::{LayoutAxis, LayoutDivider, LayoutResizeEdges, LayoutSpace};
use super::WaylandFrontend;

/// The narrowest a divider's zone gets for the pointer, in logical pixels
/// (3 mm on the tablet's 1357 px wide scene; the visible gap is 8 px).
pub(crate) const DIVIDER_ZONE: i32 = 16;

/// The narrowest it gets for a finger: about 4.6 mm on the tablet, reaching
/// 8 px (1.5 mm) into the tiles beside the default gap. A finger lands less
/// precisely than the pointer, but a wider zone would take taps meant for
/// the controls at the tiles' edges.
pub(crate) const FINGER_DIVIDER_ZONE: i32 = 24;

/// What presses a divider: the zone it takes is wider for a finger.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DividerPress {
    Pointer,
    Finger,
}

impl DividerPress {
    const fn zone(self) -> i32 {
        match self {
            Self::Pointer => DIVIDER_ZONE,
            Self::Finger => FINGER_DIVIDER_ZONE,
        }
    }
}

/// Two presses on one divider within this time are a double click or tap.
const DOUBLE_PRESS: Duration = Duration::from_millis(400);

/// How far into the tiles beside a gap a press on the gap looks for what
/// lies above them: past a frame the shell draws around a window (1 px), and
/// within the zone's reach into the tiles beside the default 8 px gap.
const TILE_PROBE_DEPTH: f64 = 4.0;

/// What is on top at one point of the scene, as far as a press on a divider
/// cares.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DividerCover {
    /// No input region at all.
    Nothing,
    /// A tile of the layout.
    Tile,
    /// Another window: a floating, fullscreen or pinned one, a local Flutter
    /// window, a layer surface.
    Window,
    /// The shell: its desktop background between windows, or its own UI.
    Shell,
}

impl DividerCover {
    /// Nothing above the tiles here.
    const fn leaves_tiles_bare(self) -> bool {
        matches!(self, Self::Nothing | Self::Tile)
    }
}

/// Whether a press at `position`, in the zone of `divider`, takes it:
/// nothing but the tiles of the layout lies above the zone there. `cover`
/// says what is on top at a point of the scene.
///
/// Where the shell has the press, it is either the shell's desktop
/// background in the gap, beneath the tiles, or shell UI above them. The
/// tiles on both sides of the gap, level with the press, tell them apart:
/// UI over the gap covers them too, the background never does.
pub(crate) fn divider_press_reachable<WindowId>(
    divider: &LayoutDivider<WindowId>,
    position: Point<f64, Logical>,
    cover: impl Fn(Point<f64, Logical>) -> DividerCover,
) -> bool {
    match cover(position) {
        DividerCover::Nothing | DividerCover::Tile => true,
        DividerCover::Window => false,
        DividerCover::Shell => tile_probes(divider, position)
            .into_iter()
            .all(|probe| cover(probe).leaves_tiles_bare()),
    }
}

/// A point a few pixels inside each tile beside the gap of `divider`, level
/// with `position`.
fn tile_probes<WindowId>(
    divider: &LayoutDivider<WindowId>,
    position: Point<f64, Logical>,
) -> [Point<f64, Logical>; 2] {
    let rect = divider.rect;
    let (left, top) = (f64::from(rect.loc.x), f64::from(rect.loc.y));
    let (right, bottom) = (left + f64::from(rect.size.w), top + f64::from(rect.size.h));
    // Pixel centres, so a probe never sits on a tile's edge.
    let before = |start: f64| start - TILE_PROBE_DEPTH + 0.5;
    let after = |end: f64| end + TILE_PROBE_DEPTH - 0.5;
    match divider.axis {
        LayoutAxis::Horizontal => {
            let y = position.y.clamp(top, (bottom - 0.5).max(top));
            [
                Point::from((before(left), y)),
                Point::from((after(right), y)),
            ]
        }
        LayoutAxis::Vertical => {
            let x = position.x.clamp(left, (right - 0.5).max(left));
            [
                Point::from((x, before(top))),
                Point::from((x, after(bottom))),
            ]
        }
    }
}

/// Presses on split dividers, for double clicks and double taps.
#[derive(Debug)]
pub(crate) struct DividerPresses<WindowId> {
    last: Option<(LayoutDivider<WindowId>, Instant)>,
}

impl<WindowId> Default for DividerPresses<WindowId> {
    fn default() -> Self {
        Self { last: None }
    }
}

impl<WindowId: Clone + PartialEq> DividerPresses<WindowId> {
    /// Notes a press on `divider` at `now`; true when it is the second of a
    /// double click or double tap on the same split. A third press starts
    /// over.
    pub(crate) fn note(&mut self, divider: &LayoutDivider<WindowId>, now: Instant) -> bool {
        let double = self.last.as_ref().is_some_and(|(previous, at)| {
            previous.path == divider.path
                && previous.owner == divider.owner
                && now.saturating_duration_since(*at) <= DOUBLE_PRESS
        });
        self.last = if double {
            None
        } else {
            Some((divider.clone(), now))
        };
        double
    }
}

/// What a tiled client's resize from its own edges drags.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct TiledEdgeResize {
    /// The split beside each requested edge that has one.
    pub(crate) hits: Vec<DividerHit>,
    /// The cursor while they move.
    pub(crate) cursor: &'static str,
    /// The requested edges on the screen's outer border (or a scrolling
    /// strip's column edge): nothing gives way there, they stay put.
    pub(crate) outer: LayoutResizeEdges,
}

/// A divider under a press, and where its boundary was then.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct DividerHit {
    pub(crate) space: LayoutSpace,
    pub(crate) divider: LayoutDivider<ObjectId>,
}

impl DividerHit {
    /// The cursor over it: the boundary moves left and right, or up and
    /// down.
    pub(crate) const fn cursor(&self) -> &'static str {
        match self.divider.axis {
            LayoutAxis::Horizontal => "col-resize",
            LayoutAxis::Vertical => "row-resize",
        }
    }

    /// A position's coordinate along the axis the boundary moves on.
    pub(crate) fn along(&self, position: Point<f64, Logical>) -> f64 {
        match self.divider.axis {
            LayoutAxis::Horizontal => position.x,
            LayoutAxis::Vertical => position.y,
        }
    }

    /// Where the boundary is now, along its axis: the middle of the gap.
    pub(crate) fn boundary(&self) -> f64 {
        boundary(&self.divider)
    }
}

fn boundary<WindowId>(divider: &LayoutDivider<WindowId>) -> f64 {
    let rect = divider.rect;
    match divider.axis {
        LayoutAxis::Horizontal => f64::from(rect.loc.x) + f64::from(rect.size.w) / 2.0,
        LayoutAxis::Vertical => f64::from(rect.loc.y) + f64::from(rect.size.h) / 2.0,
    }
}

/// The zone a press on `divider` takes: its gap, widened across the
/// boundary to `zone` ([`DIVIDER_ZONE`], [`FINGER_DIVIDER_ZONE`]).
pub(super) fn divider_zone<WindowId>(
    divider: &LayoutDivider<WindowId>,
    zone: i32,
) -> Rectangle<i32, Logical> {
    let rect = divider.rect;
    match divider.axis {
        LayoutAxis::Horizontal => {
            let width = rect.size.w.max(zone);
            Rectangle::new(
                Point::from((rect.loc.x - (width - rect.size.w) / 2, rect.loc.y)),
                Size::from((width, rect.size.h)),
            )
        }
        LayoutAxis::Vertical => {
            let height = rect.size.h.max(zone);
            Rectangle::new(
                Point::from((rect.loc.x, rect.loc.y - (height - rect.size.h) / 2)),
                Size::from((rect.size.w, height)),
            )
        }
    }
}

/// The divider whose zone holds `point`. Where zones cross (quarters), the
/// one whose gap is nearest wins.
pub(super) fn divider_at<WindowId>(
    dividers: &[LayoutDivider<WindowId>],
    point: Point<i32, Logical>,
    press: DividerPress,
) -> Option<&LayoutDivider<WindowId>> {
    dividers
        .iter()
        .filter(|divider| divider_zone(*divider, press.zone()).contains(point))
        .min_by_key(|divider| {
            let along = match divider.axis {
                LayoutAxis::Horizontal => point.x,
                LayoutAxis::Vertical => point.y,
            };
            (f64::from(along) - boundary(*divider)).abs().round() as i64
        })
}

/// The same split as `hit` in a fresh list: the same tree, the same place
/// in it, the same orientation.
fn same_split<'a>(
    dividers: &'a [LayoutDivider<ObjectId>],
    hit: &LayoutDivider<ObjectId>,
) -> Option<&'a LayoutDivider<ObjectId>> {
    dividers.iter().find(|divider| {
        divider.path == hit.path && divider.axis == hit.axis && divider.owner == hit.owner
    })
}

/// The splits a client's resize from `edges` of `tile` drags: for each
/// requested edge, the divider right beside it, whose gap starts where the
/// tile ends and which spans the whole tile. `dividers` and `tile` come
/// from one arrangement of the layout, so the edges meet exactly. Also the
/// requested edges with no divider beside them: the screen's outer border,
/// or a scrolling strip's column edge, which no split owns.
pub(crate) fn edge_dividers<WindowId>(
    dividers: &[LayoutDivider<WindowId>],
    tile: Rectangle<i32, Logical>,
    edges: LayoutResizeEdges,
) -> (Vec<&LayoutDivider<WindowId>>, LayoutResizeEdges) {
    let (left, top) = (tile.loc.x, tile.loc.y);
    let (right, bottom) = (left + tile.size.w, top + tile.size.h);
    let spans_rows =
        |rect: Rectangle<i32, Logical>| rect.loc.y <= top && rect.loc.y + rect.size.h >= bottom;
    let spans_columns =
        |rect: Rectangle<i32, Logical>| rect.loc.x <= left && rect.loc.x + rect.size.w >= right;
    let beside =
        |wanted: bool, axis: LayoutAxis, meets: &dyn Fn(Rectangle<i32, Logical>) -> bool| {
            if !wanted {
                return None;
            }
            Some(
                dividers
                    .iter()
                    .find(|divider| divider.axis == axis && meets(divider.rect)),
            )
        };
    let sides = [
        beside(edges.left, LayoutAxis::Horizontal, &|rect| {
            rect.loc.x + rect.size.w == left && spans_rows(rect)
        }),
        beside(edges.right, LayoutAxis::Horizontal, &|rect| {
            rect.loc.x == right && spans_rows(rect)
        }),
        beside(edges.top, LayoutAxis::Vertical, &|rect| {
            rect.loc.y + rect.size.h == top && spans_columns(rect)
        }),
        beside(edges.bottom, LayoutAxis::Vertical, &|rect| {
            rect.loc.y == bottom && spans_columns(rect)
        }),
    ];
    let mut found = Vec::new();
    let mut outer = LayoutResizeEdges::default();
    let outer_flags = [
        &mut outer.left,
        &mut outer.right,
        &mut outer.top,
        &mut outer.bottom,
    ];
    for (side, outer_flag) in sides.into_iter().zip(outer_flags) {
        match side {
            Some(Some(divider)) => found.push(divider),
            Some(None) => *outer_flag = true,
            None => {}
        }
    }
    (found, outer)
}

/// The cursor of a drag that moves `dividers`: the boundary's own resize
/// shape, or a diagonal one for a corner that moves two.
pub(crate) fn edge_resize_cursor<WindowId>(
    dividers: &[&LayoutDivider<WindowId>],
    edges: LayoutResizeEdges,
) -> &'static str {
    let upright = dividers
        .iter()
        .any(|divider| divider.axis == LayoutAxis::Horizontal);
    let level = dividers
        .iter()
        .any(|divider| divider.axis == LayoutAxis::Vertical);
    match (upright, level) {
        (true, true) if (edges.left && edges.top) || (edges.right && edges.bottom) => "nwse-resize",
        (true, true) => "nesw-resize",
        (false, true) => "row-resize",
        _ => "col-resize",
    }
}

/// One split a drag moves: the split as it was when the press came down,
/// and where its boundary and the press were along its axis then.
#[derive(Clone, Debug)]
pub(crate) struct DividerHandle {
    pub(crate) hit: DividerHit,
    start_boundary: f64,
    start_along: f64,
}

impl DividerHandle {
    pub(crate) fn new(hit: DividerHit, position: Point<f64, Logical>) -> Self {
        Self {
            start_boundary: hit.boundary(),
            start_along: hit.along(position),
            hit,
        }
    }

    /// Where the boundary goes for the press at `position`: it keeps its
    /// offset from the press, and does not drift when the press comes back
    /// from past a limit.
    pub(crate) fn boundary_at(&self, position: Point<f64, Logical>) -> f64 {
        self.start_boundary + self.hit.along(position) - self.start_along
    }
}

/// A finger holding a divider, or two for a client's corner resize.
#[derive(Clone, Debug)]
pub(crate) struct TouchDivider {
    pub(crate) slot: i32,
    pub(crate) handles: Vec<DividerHandle>,
    /// The second tap of a double tap evened the split out: the finger
    /// holds the divider without moving it, so its jitter cannot undo that.
    pub(crate) evened: bool,
    pub(crate) moved: Vec<Window>,
}

impl TouchDivider {
    /// Where each boundary goes for the finger at `position`; none while
    /// the finger only holds the divider.
    pub(crate) fn boundaries_at(&self, position: Point<f64, Logical>) -> Vec<(DividerHit, f64)> {
        if self.evened {
            return Vec::new();
        }
        self.handles
            .iter()
            .map(|handle| (handle.hit.clone(), handle.boundary_at(position)))
            .collect()
    }
}

/// The finger that holds a split divider, if one does. Only the first finger
/// down takes a divider: a finger that joins others already on a client,
/// the shell or a divider keeps its own route, so multi-finger gestures and
/// pinches keep working.
#[derive(Debug, Default)]
pub(crate) struct TouchDividers {
    held: Option<TouchDivider>,
}

impl TouchDividers {
    /// Whether a finger coming down now may take a divider: no other
    /// contact is down (`others_down`: contacts on a client or the shell).
    pub(crate) fn may_take(&self, others_down: bool) -> bool {
        self.held.is_none() && !others_down
    }

    /// The finger `slot` came down at `position` and took `hits`, the
    /// dividers as they are now (one, or two for a client's corner resize);
    /// `evened`: its press evened the split out.
    pub(crate) fn take(
        &mut self,
        slot: i32,
        position: Point<f64, Logical>,
        hits: Vec<DividerHit>,
        evened: bool,
    ) {
        self.held = Some(TouchDivider {
            slot,
            handles: hits
                .into_iter()
                .map(|hit| DividerHandle::new(hit, position))
                .collect(),
            evened,
            moved: Vec::new(),
        });
    }

    /// Whether the finger `slot` holds a divider.
    pub(crate) fn holds(&self, slot: i32) -> bool {
        self.held.as_ref().is_some_and(|held| held.slot == slot)
    }

    /// Where the boundaries the finger `slot` holds go for the finger at
    /// `position`: `None` when `slot` holds no divider, an empty list while
    /// it holds one without moving it.
    pub(crate) fn motion(
        &self,
        slot: i32,
        position: Point<f64, Logical>,
    ) -> Option<Vec<(DividerHit, f64)>> {
        let held = self.held.as_ref().filter(|held| held.slot == slot)?;
        Some(held.boundaries_at(position))
    }

    /// Notes a window the drag resized, for the placement that ends it.
    pub(crate) fn note_moved(&mut self, window: &Window) {
        if let Some(held) = self.held.as_mut()
            && !held.moved.contains(window)
        {
            held.moved.push(window.clone());
        }
    }

    /// The finger `slot` lifted, or its touch was cancelled: the divider it
    /// held.
    pub(crate) fn release(&mut self, slot: i32) -> Option<TouchDivider> {
        self.held.take_if(|held| held.slot == slot)
    }

    /// Every touch ends (a device went away, the lid closed, the session
    /// paused): the divider a finger held.
    pub(crate) fn release_all(&mut self) -> Option<TouchDivider> {
        self.held.take()
    }
}

impl WaylandFrontend {
    /// The divider under `position`, if a press there takes it: nothing but
    /// the tiles of the layout lies above its zone there
    /// ([`divider_press_reachable`]), and the shell does not hold the whole
    /// scene (an overview, the lock, a full-scene shell surface).
    pub(crate) fn layout_divider_at(
        &self,
        position: Point<f64, Logical>,
        press: DividerPress,
    ) -> Option<DividerHit> {
        if !self.window_layout.manages_geometry() || (self.mobile_shell && !self.phone_with_desk())
        {
            return None;
        }
        let layout = self.input_layout.as_ref()?;
        if layout.exclusive_shell() {
            return None;
        }
        let point =
            Point::<i32, Logical>::from((position.x.floor() as i32, position.y.floor() as i32));
        let output = self
            .outputs
            .iter()
            .find(|output| output.logical_geometry.contains(point))?;
        let space = LayoutSpace::new(output.id, self.active_workspace(output.id));
        let work_area = self.maximize_work_area(Some(&output.output), output.logical_geometry);
        let dividers = self
            .window_layout
            .dividers(space, work_area, self.layout_gap());
        let divider = divider_at(&dividers, point, press)?;
        divider_press_reachable(divider, position, |at| self.divider_cover_at(layout, at)).then(
            || DividerHit {
                space,
                divider: divider.clone(),
            },
        )
    }

    /// The splits a client's request to resize `window` from `edges` drags
    /// while a layout tiles it ([`edge_dividers`]). `None` when no layout
    /// tiles the window here: stacking, or the phone of the mobile
    /// presentation.
    pub(crate) fn tiled_edge_resize(
        &self,
        window: &Window,
        edges: LayoutResizeEdges,
    ) -> Option<TiledEdgeResize> {
        if !self.window_layout.manages_geometry() || (self.mobile_shell && !self.phone_with_desk())
        {
            return None;
        }
        let window_id = self.window_root_surface(window)?.id();
        let space = self.window_layout.space_for(&window_id)?;
        let output = self
            .outputs
            .iter()
            .find(|output| output.id == space.output)?;
        let work_area = self.maximize_work_area(Some(&output.output), output.logical_geometry);
        let gap = self.layout_gap();
        let tile = self
            .window_layout
            .arrange(space, work_area, gap)
            .into_iter()
            .find(|placement| placement.window == window_id)?
            .geometry;
        let dividers = self.window_layout.dividers(space, work_area, gap);
        let (found, outer) = edge_dividers(&dividers, tile, edges);
        Some(TiledEdgeResize {
            cursor: edge_resize_cursor(&found, edges),
            hits: found
                .into_iter()
                .map(|divider| DividerHit {
                    space,
                    divider: divider.clone(),
                })
                .collect(),
            outer,
        })
    }

    /// What is on top at `position`: the shell where its input layout gives
    /// it the point (its background between windows, or its UI), otherwise
    /// the topmost window region there, if any.
    fn divider_cover_at(
        &self,
        layout: &super::super::wire::InputLayoutSnapshot,
        position: Point<f64, Logical>,
    ) -> DividerCover {
        let scene = position - self.atlas_origin;
        if layout
            .shell_regions
            .iter()
            .any(|region| region.contains(scene.x, scene.y))
        {
            return DividerCover::Shell;
        }
        let Some(region) = layout
            .windows
            .iter()
            .find(|region| super::input::region_accepts_input(region, scene))
        else {
            return DividerCover::Nothing;
        };
        let tile = self.window_for_id(region.window_id).is_some_and(|window| {
            self.window_is_layout_managed(&window) && !self.window_has_constrained_state(&window)
        });
        if tile {
            DividerCover::Tile
        } else {
            DividerCover::Window
        }
    }

    /// The split `hit` names as the layout has it now, for a hold that
    /// starts after its own press changed it (a double press evened it out).
    pub(crate) fn refreshed_divider_hit(&self, hit: &DividerHit) -> DividerHit {
        self.current_divider(hit).map_or_else(
            || hit.clone(),
            |divider| DividerHit {
                space: hit.space,
                divider,
            },
        )
    }

    /// The divider `hit` names as the layout has it now.
    fn current_divider(&self, hit: &DividerHit) -> Option<LayoutDivider<ObjectId>> {
        let output = self
            .outputs
            .iter()
            .find(|output| output.id == hit.space.output)?;
        let work_area = self.maximize_work_area(Some(&output.output), output.logical_geometry);
        same_split(
            &self
                .window_layout
                .dividers(hit.space, work_area, self.layout_gap()),
            &hit.divider,
        )
        .cloned()
    }

    /// Moves the boundary of `hit` to `boundary` (along its axis) as far as
    /// the split allows. Returns every window whose tile changed.
    pub(crate) fn drag_layout_divider_to(
        &mut self,
        hit: &DividerHit,
        boundary: f64,
    ) -> Vec<(Window, Rectangle<i32, Logical>)> {
        let Some(current) = self.current_divider(hit) else {
            return Vec::new();
        };
        let delta = (boundary - self::boundary(&current)).round();
        if delta == 0.0 {
            return Vec::new();
        }
        let Some(window) = self.window_for_layout_id(&current.owner) else {
            return Vec::new();
        };
        self.resize_layout_window_with(&window, |layout, _, work_area, gap| {
            layout.drag_divider(&current, work_area, gap, delta)
        })
    }

    /// Evens out the split of `hit`. Returns every window whose tile changed.
    pub(crate) fn reset_layout_divider(
        &mut self,
        hit: &DividerHit,
    ) -> Vec<(Window, Rectangle<i32, Logical>)> {
        let Some(current) = self.current_divider(hit) else {
            return Vec::new();
        };
        let Some(window) = self.window_for_layout_id(&current.owner) else {
            return Vec::new();
        };
        self.resize_layout_window_with(&window, |layout, _, _, _| layout.reset_divider(&current))
    }

    /// Notes a press on `hit` at `now`; true when it is the second of a
    /// double click or double tap on the same divider.
    pub(crate) fn note_divider_press(&mut self, hit: &DividerHit, now: Instant) -> bool {
        self.divider_presses.note(&hit.divider, now)
    }

    /// Shows the resize cursor of the divider the pointer hovers at
    /// `position`, or stops showing it where there is none. True when that
    /// changed.
    pub(crate) fn hover_divider_cursor(&mut self, position: Point<f64, Logical>) -> bool {
        let shape = self
            .layout_divider_at(position, DividerPress::Pointer)
            .map(|hit| hit.cursor());
        self.set_divider_cursor(shape)
    }

    /// Ends a pointer grab that showed its cursor as the divider cursor (a
    /// divider drag, a middle-button drag). The pointer rests where the drag
    /// left it, often on the divider it moved, and a touchpad sends no
    /// motion after the click comes up: the cursor shows what hovering there
    /// shows now.
    pub(crate) fn end_divider_cursor_grab(&mut self) {
        self.set_compositor_pointer_grab_active(false);
        self.hover_divider_cursor(self.pointer_location);
    }

    /// Shows the resize cursor of a divider over whatever the shell or a
    /// client asks for, or stops showing it. True when that changed.
    pub(crate) fn set_divider_cursor(&mut self, shape: Option<&'static str>) -> bool {
        if self.divider_cursor == shape {
            return false;
        }
        // Once per change, never per motion: where hovering finds a divider.
        tracing::info!(
            ?shape,
            x = self.pointer_location.x.round(),
            y = self.pointer_location.y.round(),
            "split divider cursor"
        );
        self.divider_cursor = shape;
        self.divider_cursor_changed = true;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(x: i32, y: i32, width: i32, height: i32) -> Rectangle<i32, Logical> {
        Rectangle::new(Point::from((x, y)), Size::from((width, height)))
    }

    fn divider(
        axis: LayoutAxis,
        rect: Rectangle<i32, Logical>,
        path: Vec<bool>,
    ) -> LayoutDivider<u64> {
        LayoutDivider {
            owner: 1,
            path,
            axis,
            rect,
        }
    }

    #[test]
    fn a_divider_zone_is_at_least_sixteen_pixels_across_its_gap() {
        let upright = divider(LayoutAxis::Horizontal, rect(496, 40, 8, 600), vec![]);
        assert_eq!(divider_zone(&upright, DIVIDER_ZONE), rect(492, 40, 16, 600));
        let level = divider(LayoutAxis::Vertical, rect(0, 336, 1000, 8), vec![]);
        assert_eq!(divider_zone(&level, DIVIDER_ZONE), rect(0, 332, 1000, 16));
        // A wider gap is its own zone.
        let wide = divider(LayoutAxis::Horizontal, rect(490, 40, 20, 600), vec![]);
        assert_eq!(divider_zone(&wide, DIVIDER_ZONE), rect(490, 40, 20, 600));
        // A finger's zone is wider.
        assert_eq!(
            divider_zone(&upright, FINGER_DIVIDER_ZONE),
            rect(488, 40, 24, 600)
        );
    }

    /// Square windows (`appearance.roundedWindowFrame` off) meet with no
    /// gap: the divider is their seam, and its zone still reaches 8 px into
    /// each tile for the pointer and 12 px for a finger.
    #[test]
    fn square_tiles_meeting_without_a_gap_keep_the_whole_zone() {
        let seam = divider(LayoutAxis::Horizontal, rect(500, 40, 0, 600), vec![]);
        assert_eq!(divider_zone(&seam, DIVIDER_ZONE), rect(492, 40, 16, 600));
        assert_eq!(
            divider_zone(&seam, FINGER_DIVIDER_ZONE),
            rect(488, 40, 24, 600)
        );
        let dividers = [seam];
        let hit = |x| divider_at(&dividers, Point::from((x, 300)), DividerPress::Pointer);
        assert!(hit(492).is_some());
        assert!(hit(507).is_some());
        assert!(hit(491).is_none());
        assert!(hit(508).is_none());
        // A press there with only the tiles beneath takes it.
        assert!(divider_press_reachable(
            &dividers[0],
            Point::from((497.0, 300.0)),
            |_| DividerCover::Tile,
        ));
    }

    #[test]
    fn a_press_takes_the_divider_whose_gap_is_nearest() {
        // Quarters: one upright boundary, and a level one in each half.
        let dividers = vec![
            divider(LayoutAxis::Horizontal, rect(496, 40, 8, 600), vec![]),
            divider(LayoutAxis::Vertical, rect(0, 336, 496, 8), vec![false]),
            divider(LayoutAxis::Vertical, rect(504, 336, 496, 8), vec![true]),
        ];
        let at = |x, y| {
            divider_at(&dividers, Point::from((x, y)), DividerPress::Pointer)
                .map(|d| d.path.clone())
        };
        assert_eq!(at(493, 100), Some(vec![]));
        assert_eq!(at(506, 100), Some(vec![]));
        assert_eq!(at(200, 333), Some(vec![false]));
        assert_eq!(at(800, 347), Some(vec![true]));
        // Where the zones cross, the nearer gap wins.
        assert_eq!(at(500, 338), Some(vec![]));
        assert_eq!(at(495, 340), Some(vec![false]));
        // Inside a tile, away from every gap: nothing.
        assert_eq!(at(200, 100), None);
        assert_eq!(at(487, 100), None);
    }

    /// A screen split in halves as on the tablet: tiles left of 561 and
    /// right of 569 (logical px), the gap between them the shell's
    /// background, a top bar above 40.
    fn split_screen() -> LayoutDivider<u64> {
        divider(LayoutAxis::Horizontal, rect(561, 40, 8, 760), vec![])
    }

    fn halves(at: Point<f64, Logical>) -> DividerCover {
        if at.y < 40.0 {
            DividerCover::Shell
        } else if at.x < 561.0 || at.x >= 569.0 {
            DividerCover::Tile
        } else {
            DividerCover::Shell
        }
    }

    #[test]
    fn a_press_on_the_background_in_the_gap_takes_the_divider() {
        // The tablet's eb17 check: a finger at the centre of a split screen,
        // on the gap the shell's input layout gives to the shell.
        let gap = split_screen();
        for x in [561.0, 565.33, 568.9] {
            assert!(divider_press_reachable(
                &gap,
                Point::from((x, 400.0)),
                halves
            ));
        }
        // The zone's reach into the tiles beside the gap.
        assert!(divider_press_reachable(
            &gap,
            Point::from((557.2, 400.0)),
            halves
        ));
        assert!(divider_press_reachable(
            &gap,
            Point::from((572.9, 400.0)),
            halves
        ));
    }

    #[test]
    fn shell_ui_or_another_window_over_the_gap_keeps_the_press() {
        let gap = split_screen();
        let press = Point::from((565.0, 400.0));
        // A notification card across the gap: the shell covers the tiles
        // beside it too.
        let card = |at: Point<f64, Logical>| {
            if (400.0..700.0).contains(&at.x) && (350.0..450.0).contains(&at.y) {
                DividerCover::Shell
            } else {
                halves(at)
            }
        };
        assert!(!divider_press_reachable(&gap, press, card));
        // Below the card the divider is free again.
        assert!(divider_press_reachable(
            &gap,
            Point::from((565.0, 600.0)),
            card
        ));
        // A floating window over the right tile's edge, beside the gap.
        let float = |at: Point<f64, Logical>| {
            if (569.0..900.0).contains(&at.x) && (300.0..500.0).contains(&at.y) {
                DividerCover::Window
            } else {
                halves(at)
            }
        };
        assert!(!divider_press_reachable(&gap, press, float));
        // A floating window over the gap itself.
        let over = |at: Point<f64, Logical>| {
            if (500.0..900.0).contains(&at.x) {
                DividerCover::Window
            } else {
                halves(at)
            }
        };
        assert!(!divider_press_reachable(&gap, press, over));
        assert!(!divider_press_reachable(
            &gap,
            Point::from((572.0, 400.0)),
            over
        ));
    }

    #[test]
    fn a_level_gap_looks_above_and_below_it() {
        let gap = divider(LayoutAxis::Vertical, rect(0, 396, 561, 8), vec![false]);
        let quarters = |at: Point<f64, Logical>| {
            if (396.0..404.0).contains(&at.y) {
                DividerCover::Shell
            } else {
                DividerCover::Tile
            }
        };
        assert!(divider_press_reachable(
            &gap,
            Point::from((200.0, 400.0)),
            quarters
        ));
        let bar_below = |at: Point<f64, Logical>| {
            if at.y >= 404.0 && at.y < 420.0 {
                DividerCover::Shell
            } else {
                quarters(at)
            }
        };
        assert!(!divider_press_reachable(
            &gap,
            Point::from((200.0, 400.0)),
            bar_below
        ));
    }

    #[test]
    fn a_second_press_on_the_same_split_soon_after_is_a_double_press() {
        let mut presses = DividerPresses::default();
        let gap = split_screen();
        let start = Instant::now();
        assert!(!presses.note(&gap, start));
        assert!(presses.note(&gap, start + Duration::from_millis(250)));
        // A third press starts over.
        assert!(!presses.note(&gap, start + Duration::from_millis(400)));
        // Too slow.
        assert!(!presses.note(&gap, start + Duration::from_millis(900)));
        // Another split.
        let other = divider(LayoutAxis::Vertical, rect(0, 396, 561, 8), vec![false]);
        assert!(!presses.note(&other, start + Duration::from_millis(1000)));
    }

    fn touch_hit(rect: Rectangle<i32, Logical>) -> DividerHit {
        DividerHit {
            space: LayoutSpace::new(denial_core::topology::OutputId(1), 1),
            divider: LayoutDivider {
                owner: ObjectId::null(),
                path: vec![],
                axis: LayoutAxis::Horizontal,
                rect,
            },
        }
    }

    #[test]
    fn a_finger_drags_the_divider_it_came_down_on() {
        let mut fingers = TouchDividers::default();
        assert!(fingers.may_take(false));
        // Down a little left of the boundary at 565.
        fingers.take(
            0,
            Point::from((563.0, 400.0)),
            vec![touch_hit(rect(561, 40, 8, 760))],
            false,
        );
        assert!(fingers.holds(0));
        assert!(!fingers.holds(1));
        // Move: the boundary keeps its offset from the finger.
        let boundaries = fingers.motion(0, Point::from((663.0, 420.0))).unwrap();
        assert_eq!(boundaries.len(), 1);
        assert_eq!(boundaries[0].1, 665.0);
        // Another finger moving is not the drag.
        assert_eq!(fingers.motion(1, Point::from((663.0, 420.0))), None);
        // Up ends it.
        assert!(fingers.release(1).is_none());
        let released = fingers.release(0).expect("the finger held the divider");
        assert_eq!(released.slot, 0);
        assert!(fingers.may_take(false));
        assert_eq!(fingers.motion(0, Point::from((700.0, 400.0))), None);
    }

    #[test]
    fn only_the_first_finger_down_takes_a_divider() {
        let mut fingers = TouchDividers::default();
        // A finger already on a client or the shell: a pinch or a
        // three-finger swipe keeps its route.
        assert!(!fingers.may_take(true));
        fingers.take(
            2,
            Point::from((565.0, 400.0)),
            vec![touch_hit(rect(561, 40, 8, 760))],
            false,
        );
        // A second finger while one holds a divider.
        assert!(!fingers.may_take(false));
    }

    #[test]
    fn a_double_tap_holds_the_evened_divider_without_moving_it() {
        let mut fingers = TouchDividers::default();
        // The second tap came down at 663 on a divider that the tap evened
        // out to 565: the finger holds it, and its jitter moves nothing.
        fingers.take(
            0,
            Point::from((663.0, 400.0)),
            vec![touch_hit(rect(561, 40, 8, 760))],
            true,
        );
        let boundaries = fingers.motion(0, Point::from((667.0, 401.0))).unwrap();
        assert!(boundaries.is_empty());
        let held = fingers.release(0).expect("the finger held the divider");
        assert!(held.evened);
        assert_eq!(held.handles[0].hit.boundary(), 565.0);
    }

    #[test]
    fn every_touch_ending_frees_the_divider() {
        let mut fingers = TouchDividers::default();
        fingers.take(
            5,
            Point::from((565.0, 400.0)),
            vec![touch_hit(rect(561, 40, 8, 760))],
            false,
        );
        assert!(fingers.release_all().is_some());
        assert!(fingers.may_take(false));
        assert!(fingers.release_all().is_none());
    }

    #[test]
    fn a_finger_takes_a_divider_from_further_into_the_tiles_than_the_pointer() {
        let dividers = vec![divider(
            LayoutAxis::Horizontal,
            rect(561, 40, 8, 760),
            vec![],
        )];
        let at = |x, press| divider_at(&dividers, Point::from((x, 400)), press).is_some();
        // 6 px into the left tile: a finger's, not the pointer's.
        assert!(at(555, DividerPress::Finger));
        assert!(!at(555, DividerPress::Pointer));
        assert!(at(557, DividerPress::Pointer));
        // 8 px into the right tile is the finger zone's last pixel.
        assert!(at(576, DividerPress::Finger));
        assert!(!at(577, DividerPress::Finger));
        assert!(!at(552, DividerPress::Finger));
    }

    fn edges(top: bool, bottom: bool, left: bool, right: bool) -> LayoutResizeEdges {
        LayoutResizeEdges {
            top,
            bottom,
            left,
            right,
        }
    }

    const LEFT: LayoutResizeEdges = LayoutResizeEdges {
        top: false,
        bottom: false,
        left: true,
        right: false,
    };
    const RIGHT: LayoutResizeEdges = LayoutResizeEdges {
        top: false,
        bottom: false,
        left: false,
        right: true,
    };

    #[test]
    fn a_shared_edge_of_halves_is_their_divider_and_the_outer_edges_are_none() {
        let dividers = vec![split_screen()];
        let left_tile = rect(0, 40, 561, 760);
        let right_tile = rect(569, 40, 561, 760);
        let (found, outer) = edge_dividers(&dividers, left_tile, RIGHT);
        assert_eq!(found, vec![&dividers[0]]);
        assert_eq!(outer, LayoutResizeEdges::default());
        let (found, outer) = edge_dividers(&dividers, right_tile, LEFT);
        assert_eq!(found, vec![&dividers[0]]);
        assert_eq!(outer, LayoutResizeEdges::default());
        // The screen's outer border: nothing to drag.
        let (found, outer) = edge_dividers(&dividers, left_tile, LEFT);
        assert!(found.is_empty());
        assert_eq!(outer, LEFT);
        let (found, outer) = edge_dividers(&dividers, right_tile, edges(true, false, false, false));
        assert!(found.is_empty());
        assert!(outer.top);
        // A corner on a shared edge drags that edge's split; its other
        // edge is the outer border.
        let (found, outer) = edge_dividers(&dividers, left_tile, edges(false, true, false, true));
        assert_eq!(found, vec![&dividers[0]]);
        assert_eq!(outer, edges(false, true, false, false));
        assert_eq!(
            edge_resize_cursor(&found, edges(false, true, false, true)),
            "col-resize"
        );
    }

    #[test]
    fn a_corner_between_quarters_drags_the_split_on_each_of_its_edges() {
        // [A | [B / C]], and the left half split too, at the same height:
        // [[A / D] | [B / C]].
        let dividers = vec![
            divider(LayoutAxis::Horizontal, rect(496, 40, 8, 600), vec![]),
            divider(LayoutAxis::Vertical, rect(0, 336, 496, 8), vec![false]),
            divider(LayoutAxis::Vertical, rect(504, 336, 496, 8), vec![true]),
        ];
        let b = rect(504, 40, 496, 296);
        let c = rect(504, 344, 496, 296);
        let a = rect(0, 40, 496, 296);
        // B's lower edge is its own half's split, not the left half's level
        // one at the same height.
        let (found, outer) = edge_dividers(&dividers, b, edges(false, true, false, false));
        assert_eq!(found, vec![&dividers[2]]);
        assert_eq!(outer, LayoutResizeEdges::default());
        // B's lower left corner: the upright split and its own level one.
        let corner = edges(false, true, true, false);
        let (found, outer) = edge_dividers(&dividers, b, corner);
        assert_eq!(found, vec![&dividers[0], &dividers[2]]);
        assert_eq!(outer, LayoutResizeEdges::default());
        assert_eq!(edge_resize_cursor(&found, corner), "nesw-resize");
        // C's upper left corner.
        let corner = edges(true, false, true, false);
        let (found, _) = edge_dividers(&dividers, c, corner);
        assert_eq!(found, vec![&dividers[0], &dividers[2]]);
        assert_eq!(edge_resize_cursor(&found, corner), "nwse-resize");
        // A's upper right corner: the upright split; the top is the border.
        let corner = edges(true, false, false, true);
        let (found, outer) = edge_dividers(&dividers, a, corner);
        assert_eq!(found, vec![&dividers[0]]);
        assert_eq!(outer, edges(true, false, false, false));
        assert_eq!(edge_resize_cursor(&found, corner), "col-resize");
        // A's lower edge.
        let (found, _) = edge_dividers(&dividers, a, edges(false, true, false, false));
        assert_eq!(found, vec![&dividers[1]]);
        assert_eq!(
            edge_resize_cursor(&found, edges(false, true, false, false)),
            "row-resize"
        );
    }

    #[test]
    fn a_handle_keeps_the_boundary_offset_from_the_press() {
        let handle = DividerHandle::new(
            touch_hit(rect(561, 40, 8, 760)),
            Point::from((563.0, 400.0)),
        );
        assert_eq!(handle.boundary_at(Point::from((663.0, 420.0))), 665.0);
        assert_eq!(handle.boundary_at(Point::from((463.0, 0.0))), 465.0);
        let level = DividerHandle::new(
            DividerHit {
                divider: LayoutDivider {
                    axis: LayoutAxis::Vertical,
                    rect: rect(0, 336, 1000, 8),
                    ..touch_hit(rect(0, 0, 0, 0)).divider
                },
                ..touch_hit(rect(0, 0, 0, 0))
            },
            Point::from((300.0, 342.0)),
        );
        assert_eq!(level.boundary_at(Point::from((900.0, 402.0))), 400.0);
    }

    #[test]
    fn a_finger_can_hold_both_splits_of_a_corner() {
        let mut fingers = TouchDividers::default();
        let upright = touch_hit(rect(496, 40, 8, 600));
        let level = DividerHit {
            divider: LayoutDivider {
                axis: LayoutAxis::Vertical,
                rect: rect(504, 336, 496, 8),
                ..upright.divider.clone()
            },
            ..upright.clone()
        };
        fingers.take(3, Point::from((502.0, 338.0)), vec![upright, level], false);
        let boundaries = fingers.motion(3, Point::from((452.0, 398.0))).unwrap();
        assert_eq!(
            boundaries.iter().map(|(_, at)| *at).collect::<Vec<_>>(),
            vec![450.0, 400.0]
        );
    }

    #[test]
    fn the_cursor_and_the_drag_follow_the_boundary_axis() {
        let space = LayoutSpace::new(denial_core::topology::OutputId(1), 1);
        let upright = DividerHit {
            space,
            divider: LayoutDivider {
                owner: ObjectId::null(),
                path: vec![],
                axis: LayoutAxis::Horizontal,
                rect: rect(496, 40, 8, 600),
            },
        };
        assert_eq!(upright.cursor(), "col-resize");
        assert_eq!(upright.along(Point::from((120.0, 300.0))), 120.0);
        assert_eq!(upright.boundary(), 500.0);
        let level = DividerHit {
            divider: LayoutDivider {
                axis: LayoutAxis::Vertical,
                rect: rect(0, 336, 1000, 8),
                ..upright.divider.clone()
            },
            ..upright
        };
        assert_eq!(level.cursor(), "row-resize");
        assert_eq!(level.along(Point::from((120.0, 300.0))), 300.0);
        assert_eq!(level.boundary(), 340.0);
    }
}
