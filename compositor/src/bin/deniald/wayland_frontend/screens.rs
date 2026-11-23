//! The full-screen apps layout ("screens") in the frontend.
//!
//! The layout itself is the scrolling strip in screens mode
//! (`window_layout.rs`). This adapter answers which screen every window is
//! on, keeps floating windows over the screen they opened on while the strip
//! moves, and tells the shell and the input code where the screens are.

use std::collections::HashMap;

use denial_core::topology::OutputId;
use smithay::desktop::Window;
use smithay::reexports::wayland_server::Resource;
use smithay::reexports::wayland_server::backend::ObjectId;
use smithay::utils::{Logical, Point, Rectangle};

use super::super::window_layout::{
    LayoutDirection, LayoutScreen, LayoutSpace, WindowLayout, WindowLayoutKind,
};
use super::WaylandFrontend;
use super::managed_window::ManagedWindow;

/// Where one window is in the full-screen apps layout.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct WindowScreen {
    /// One-based position of the screen in its output's strip.
    pub(crate) index: u32,
    /// The screen in output coordinates; beside the output unless current.
    pub(crate) rect: Rectangle<i32, Logical>,
}

/// A floating window kept over one screen: a tile of that screen names it,
/// and `origin` is where the screen was when the window was last placed.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct ScreenFloat {
    pub(super) anchor: ObjectId,
    pub(super) origin: Point<i32, Logical>,
}

/// One output's screens, for placing floating windows.
pub(super) struct OutputScreens<WindowId> {
    pub(super) output: Rectangle<i32, Logical>,
    pub(super) screens: Vec<LayoutScreen<WindowId>>,
}

/// The screen a floating window belongs to after the strip moved, and how
/// far the window moves with it. A window whose screen is gone, or which the
/// user took to another output, joins the screen now current on the output
/// it is on and does not move.
pub(super) fn follow_screen<WindowId: Clone + Eq>(
    previous: Option<(&WindowId, Point<i32, Logical>)>,
    window: Rectangle<i32, Logical>,
    outputs: &[OutputScreens<WindowId>],
) -> Option<((WindowId, Point<i32, Logical>), Point<i32, Logical>)> {
    let center = window.loc + Point::from((window.size.w / 2, window.size.h / 2));
    let window_output = outputs
        .iter()
        .find(|output| output.output.contains(center))
        .or_else(|| {
            // A window dragged partly off every output keeps its strip.
            previous.and_then(|(anchor, _)| {
                outputs.iter().find(|output| {
                    output
                        .screens
                        .iter()
                        .any(|screen| screen.windows.contains(anchor))
                })
            })
        })?;
    if let Some((anchor, origin)) = previous
        && let Some(screen) = window_output
            .screens
            .iter()
            .find(|screen| screen.windows.contains(anchor))
    {
        let delta = screen.rect.loc - origin;
        return Some(((anchor.clone(), screen.rect.loc), delta));
    }
    let current = current_screen(window_output)?;
    Some((
        (current.active.clone(), current.rect.loc),
        Point::from((0, 0)),
    ))
}

/// The screen nearest the output's work area: the current one at rest, the
/// one most in view during a swipe.
fn current_screen<WindowId>(output: &OutputScreens<WindowId>) -> Option<&LayoutScreen<WindowId>> {
    output.screens.iter().min_by_key(|screen| {
        let overlap = screen.rect.intersection(output.output);
        -overlap.map_or(0_i64, |area| {
            i64::from(area.size.w) * i64::from(area.size.h)
        })
    })
}

impl WaylandFrontend {
    /// The strip of the output under the pointer, for a swipe that starts
    /// while no tiled window has focus.
    pub(super) fn screens_space_under_pointer(&self) -> Option<LayoutSpace> {
        let pointer = Point::<i32, Logical>::from((
            self.pointer_location.x.floor() as i32,
            self.pointer_location.y.floor() as i32,
        ));
        let output = self
            .outputs
            .iter()
            .find(|output| output.logical_geometry.contains(pointer))
            .or_else(|| self.outputs.first())?;
        Some(LayoutSpace::new(output.id, 1))
    }

    /// Every output's screens in strip order, with its work area.
    fn output_screens(&self) -> Vec<(OutputId, OutputScreens<ObjectId>)> {
        if self.window_layout.kind() != WindowLayoutKind::Screens {
            return Vec::new();
        }
        let gap = self.layout_gap();
        self.outputs
            .iter()
            .map(|output| {
                let work_area =
                    self.maximize_work_area(Some(&output.output), output.logical_geometry);
                (
                    output.id,
                    OutputScreens {
                        output: output.logical_geometry,
                        screens: self.window_layout.screens(
                            LayoutSpace::new(output.id, 1),
                            work_area,
                            gap,
                        ),
                    },
                )
            })
            .collect()
    }

    /// Which screen each window is on: tiles by their screen, floating
    /// windows by the screen they are kept over. Empty in other layouts.
    pub(crate) fn window_screens(&self) -> HashMap<ObjectId, WindowScreen> {
        let mut screens = HashMap::new();
        let mut leaves = HashMap::new();
        for (_, output) in self.output_screens() {
            for (index, screen) in output.screens.into_iter().enumerate() {
                let placed = WindowScreen {
                    index: u32::try_from(index + 1).unwrap_or(u32::MAX),
                    rect: screen.rect,
                };
                for window in screen.windows {
                    leaves.insert(window.clone(), placed);
                    screens.insert(window, placed);
                }
            }
        }
        for (window, float) in &self.screen_floats {
            if let Some(placed) = leaves.get(&float.anchor) {
                screens.insert(window.clone(), *placed);
            }
        }
        screens
    }

    /// A window that floats over a screen: not tiled, not pinned above every
    /// screen, shown, and not a dialog, which follows its parent instead.
    fn floats_over_screen(&self, window: &Window) -> bool {
        let Some(root) = self.window_root_surface(window) else {
            return false;
        };
        if !root.is_alive() || self.window_layout.contains(&root.id()) {
            return false;
        }
        #[cfg(feature = "flutter")]
        if self.surface_is_minimized(&root.id())
            || self.window_is_pinned(window)
            || self.window_on_phone(window)
        {
            return false;
        }
        let Some(facts) = ManagedWindow::new(window).map(|window| window.facts()) else {
            return false;
        };
        !facts.override_redirect
            && !facts.auxiliary
            && !facts.client_state.fullscreen
            && !self.window_has_transient_parent(window)
    }

    /// Moves every floating window with the screen it belongs to. Runs after
    /// each arrangement of the full-screen apps layout.
    pub(super) fn keep_floats_over_screens(&mut self) -> bool {
        if self.window_layout.kind() != WindowLayoutKind::Screens {
            self.screen_floats.clear();
            return false;
        }
        let outputs = self
            .output_screens()
            .into_iter()
            .map(|(_, screens)| screens)
            .collect::<Vec<_>>();
        let floats = self
            .space
            .elements()
            .filter(|window| self.floats_over_screen(window))
            .filter_map(|window| {
                let id = self.window_root_surface(window)?.id();
                Some((window.clone(), id))
            })
            .collect::<Vec<_>>();
        let mut kept = HashMap::with_capacity(floats.len());
        let mut changed = false;
        for (window, id) in floats {
            let geometry = self.window_geometry_target(&window);
            let previous = self
                .screen_floats
                .get(&id)
                .map(|float| (&float.anchor, float.origin));
            let Some(((anchor, origin), delta)) = follow_screen(previous, geometry, &outputs)
            else {
                continue;
            };
            if delta != Point::from((0, 0)) {
                let mut moved = geometry;
                moved.loc += delta;
                self.set_window_geometry_target(&window, moved);
                self.reconcile_xdg_transient_descendant_placements(&window);
                changed = true;
            }
            kept.insert(id, ScreenFloat { anchor, origin });
        }
        self.screen_floats = kept;
        changed
    }

    /// Joins `window` to the screen of `target`, splitting that tile on
    /// `side`. Refused outside the full-screen apps layout, for windows the
    /// layout does not hold, and for a screen that already has four tiles.
    pub(crate) fn join_screen(
        &mut self,
        window: &Window,
        target: &Window,
        side: LayoutDirection,
    ) -> bool {
        self.change_screens(window, target, |layout, window, target| {
            layout.move_beside(window, target, side)
        })
    }

    /// Gives `window` a screen of its own just before or after the screen
    /// of `target`: separates a split, or moves a screen along the strip.
    pub(crate) fn move_to_screen(
        &mut self,
        window: &Window,
        target: &Window,
        before: bool,
    ) -> bool {
        self.change_screens(window, target, |layout, window, target| {
            layout.move_to_column(window, target, before)
        })
    }

    fn change_screens(
        &mut self,
        window: &Window,
        target: &Window,
        change: impl FnOnce(&mut dyn WindowLayout<ObjectId>, &ObjectId, &ObjectId) -> bool,
    ) -> bool {
        if self.window_layout.kind() != WindowLayoutKind::Screens {
            return false;
        }
        let (Some(window), Some(target)) = (
            self.window_root_surface(window).map(|root| root.id()),
            self.window_root_surface(target).map(|root| root.id()),
        ) else {
            return false;
        };
        if !self.window_layout.contains(&window)
            || !self.window_layout.contains(&target)
            || !change(self.window_layout.as_mut(), &window, &target)
        {
            return false;
        }
        self.window_layout.activate(&window);
        self.arrange_layout_windows();
        true
    }

    /// Ranks every window for a layout switch: by output, then workspace,
    /// then its place in the layout it leaves (its stacking place when that
    /// layout did not arrange it). Switching into the full-screen apps layout
    /// gathers the workspaces into one strip in this order.
    pub(super) fn layout_switch_order(&self) -> HashMap<ObjectId, (usize, u8, usize)> {
        let gap = self.layout_gap();
        let mut order = HashMap::new();
        let workspace_count = self.layout_workspace_count();
        for (output_index, output) in self.outputs.iter().enumerate() {
            let work_area = self.maximize_work_area(Some(&output.output), output.logical_geometry);
            for workspace in 1..=workspace_count {
                for (position, placement) in self
                    .window_layout
                    .arrange(LayoutSpace::new(output.id, workspace), work_area, gap)
                    .into_iter()
                    .enumerate()
                {
                    order.insert(placement.window, (output_index, workspace, position));
                }
            }
        }
        let placed = order.len();
        for (stacking, window) in self.space.elements().enumerate() {
            let Some(root) = self.window_root_surface(window) else {
                continue;
            };
            if order.contains_key(&root.id()) {
                continue;
            }
            let output_index = self
                .outputs
                .iter()
                .position(|output| {
                    output
                        .logical_geometry
                        .contains(self.window_geometry_target(window).loc)
                })
                .unwrap_or(0);
            #[cfg(feature = "flutter")]
            let workspace = self
                .surface_ids
                .get(&root.id())
                .and_then(|stable_id| self.workspace_location(*stable_id))
                .map_or(1, |location| location.workspace);
            #[cfg(not(feature = "flutter"))]
            let workspace = 1;
            order.insert(root.id(), (output_index, workspace, placed + stacking));
        }
        order
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use smithay::utils::Size;

    fn rect(x: i32, y: i32, width: i32, height: i32) -> Rectangle<i32, Logical> {
        Rectangle::new(Point::from((x, y)), Size::from((width, height)))
    }

    fn screen(x: i32, windows: &[u64]) -> LayoutScreen<u64> {
        LayoutScreen {
            rect: rect(x, 40, 1000, 600),
            windows: windows.to_vec(),
            active: windows[0],
        }
    }

    fn strip(current: i32, screens: &[&[u64]]) -> OutputScreens<u64> {
        OutputScreens {
            output: rect(0, 0, 1000, 640),
            screens: screens
                .iter()
                .enumerate()
                .map(|(index, windows)| screen((index as i32 - current) * 1008, windows))
                .collect(),
        }
    }

    #[test]
    fn a_new_floating_window_joins_the_current_screen_where_it_is() {
        let outputs = [strip(1, &[&[1], &[2, 3], &[4]])];
        let dialog = rect(300, 200, 200, 100);
        assert_eq!(
            follow_screen(None, dialog, &outputs),
            Some(((2, Point::from((0, 40))), Point::from((0, 0))))
        );
    }

    #[test]
    fn a_floating_window_moves_with_its_screen() {
        // The window floats over screen [2, 3], current at x = 0. A swipe
        // brings in the next screen: its own screen moves one stride left.
        let outputs = [strip(2, &[&[1], &[2, 3], &[4]])];
        let dialog = rect(300, 200, 200, 100);
        let ((anchor, origin), delta) =
            follow_screen(Some((&3, Point::from((0, 40)))), dialog, &outputs).unwrap();
        assert_eq!(anchor, 3);
        assert_eq!(origin, Point::from((-1008, 40)));
        assert_eq!(delta, Point::from((-1008, 0)));
    }

    #[test]
    fn a_floating_window_whose_screen_closed_stays_over_the_current_one() {
        let outputs = [strip(0, &[&[1], &[4]])];
        let dialog = rect(300, 200, 200, 100);
        assert_eq!(
            follow_screen(Some((&2, Point::from((0, 40)))), dialog, &outputs),
            Some(((1, Point::from((0, 40))), Point::from((0, 0))))
        );
    }

    #[test]
    fn a_floating_window_taken_to_another_output_joins_that_strip() {
        let second = OutputScreens {
            output: rect(1000, 0, 800, 600),
            screens: vec![LayoutScreen {
                rect: rect(1000, 40, 800, 560),
                windows: vec![7],
                active: 7,
            }],
        };
        let outputs = [strip(0, &[&[1], &[2]]), second];
        let moved = rect(1200, 200, 200, 100);
        assert_eq!(
            follow_screen(Some((&1, Point::from((0, 40)))), moved, &outputs),
            Some(((7, Point::from((1000, 40))), Point::from((0, 0))))
        );
    }

    #[test]
    fn mid_swipe_the_screen_most_in_view_is_current() {
        let mut outputs = strip(0, &[&[1], &[2]]);
        for screen in &mut outputs.screens {
            screen.rect.loc.x -= 700;
        }
        assert_eq!(
            current_screen(&outputs).map(|screen| screen.active),
            Some(2)
        );
    }
}
