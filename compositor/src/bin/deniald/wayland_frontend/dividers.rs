//! Split dividers: the gap between the two sides of a split, which a plain
//! mouse drag or a finger moves and a double click or double tap evens out.
//!
//! Every managed layout shares the split trees (`DwindleNode`), so Dwindle,
//! scrolling columns and the screens of the full-screen apps layout all get
//! the same dividers. A gap between scrolling columns is no divider. The gap
//! is `layout.maximizePadding` wide; the zone a press takes is at least
//! [`DIVIDER_ZONE`] wide, centred on it, so it reaches a few pixels into the
//! tiles beside it.

use std::time::{Duration, Instant};

use smithay::desktop::Window;
use smithay::reexports::wayland_server::backend::ObjectId;
use smithay::utils::{Logical, Point, Rectangle, Size};

use super::super::window_layout::{LayoutAxis, LayoutDivider, LayoutSpace};
use super::WaylandFrontend;

/// The narrowest a divider's zone gets, in logical pixels.
pub(crate) const DIVIDER_ZONE: i32 = 16;

/// Two presses on one divider within this time are a double click or tap.
const DOUBLE_PRESS: Duration = Duration::from_millis(400);

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
/// boundary to [`DIVIDER_ZONE`].
pub(super) fn divider_zone<WindowId>(divider: &LayoutDivider<WindowId>) -> Rectangle<i32, Logical> {
    let rect = divider.rect;
    match divider.axis {
        LayoutAxis::Horizontal => {
            let width = rect.size.w.max(DIVIDER_ZONE);
            Rectangle::new(
                Point::from((rect.loc.x - (width - rect.size.w) / 2, rect.loc.y)),
                Size::from((width, rect.size.h)),
            )
        }
        LayoutAxis::Vertical => {
            let height = rect.size.h.max(DIVIDER_ZONE);
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
) -> Option<&LayoutDivider<WindowId>> {
    dividers
        .iter()
        .filter(|divider| divider_zone(*divider).contains(point))
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

/// A finger dragging a divider.
#[derive(Clone, Debug)]
pub(crate) struct TouchDivider {
    pub(crate) slot: i32,
    pub(crate) hit: DividerHit,
    /// Where the boundary and the finger were when it came down.
    pub(crate) start_boundary: f64,
    pub(crate) start_along: f64,
    pub(crate) moved: Vec<Window>,
}

impl WaylandFrontend {
    /// The divider under `position`, if a press there takes it: no shell
    /// surface and no window other than a tile covers the point.
    pub(crate) fn layout_divider_at(&self, position: Point<f64, Logical>) -> Option<DividerHit> {
        if !self.window_layout.manages_geometry()
            || (self.mobile_shell && !self.phone_with_desk())
            || !self.divider_reachable(position)
        {
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
        divider_at(&dividers, point).map(|divider| DividerHit {
            space,
            divider: divider.clone(),
        })
    }

    /// No shell surface takes the point, and the topmost window there, if
    /// any, is a tile of the layout (the zone reaches into the tiles beside
    /// the gap), not a floating, fullscreen or pinned window above them.
    fn divider_reachable(&self, position: Point<f64, Logical>) -> bool {
        let Some(layout) = self.input_layout.as_ref() else {
            return false;
        };
        let scene = position - self.atlas_origin;
        if layout.exclusive_shell()
            || layout
                .shell_regions
                .iter()
                .any(|region| region.contains(scene.x, scene.y))
        {
            return false;
        }
        let Some(region) = layout
            .windows
            .iter()
            .find(|region| super::input::region_accepts_input(region, scene))
        else {
            return true;
        };
        self.window_for_id(region.window_id).is_some_and(|window| {
            self.window_is_layout_managed(&window) && !self.window_has_constrained_state(&window)
        })
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
        let double = self
            .last_divider_press
            .as_ref()
            .is_some_and(|(previous, at)| {
                previous.path == hit.divider.path
                    && previous.owner == hit.divider.owner
                    && now.saturating_duration_since(*at) <= DOUBLE_PRESS
            });
        self.last_divider_press = if double {
            None
        } else {
            Some((hit.divider.clone(), now))
        };
        double
    }

    /// Shows the resize cursor of a divider over whatever the shell or a
    /// client asks for, or stops showing it. True when that changed.
    pub(crate) fn set_divider_cursor(&mut self, shape: Option<&'static str>) -> bool {
        if self.divider_cursor == shape {
            return false;
        }
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
        assert_eq!(divider_zone(&upright), rect(492, 40, 16, 600));
        let level = divider(LayoutAxis::Vertical, rect(0, 336, 1000, 8), vec![]);
        assert_eq!(divider_zone(&level), rect(0, 332, 1000, 16));
        // A wider gap is its own zone.
        let wide = divider(LayoutAxis::Horizontal, rect(490, 40, 20, 600), vec![]);
        assert_eq!(divider_zone(&wide), rect(490, 40, 20, 600));
    }

    #[test]
    fn a_press_takes_the_divider_whose_gap_is_nearest() {
        // Quarters: one upright boundary, and a level one in each half.
        let dividers = vec![
            divider(LayoutAxis::Horizontal, rect(496, 40, 8, 600), vec![]),
            divider(LayoutAxis::Vertical, rect(0, 336, 496, 8), vec![false]),
            divider(LayoutAxis::Vertical, rect(504, 336, 496, 8), vec![true]),
        ];
        let at = |x, y| divider_at(&dividers, Point::from((x, y))).map(|d| d.path.clone());
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
