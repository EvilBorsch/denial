//! What the windows keep when the shell switches between the tablet (mobile)
//! and desktop presentations of one panel.
//!
//! The desktop's window layout waits, untouched, while the tablet
//! presentation holds the panel alone: every window keeps its screen and the
//! strip its order and splits, so the desktop comes back as it was left
//! (`desktop_layout_dormant`). What the tablet changed meanwhile carries over:
//!
//! - A screen of the full-screen apps layout whose only tiles are two side by
//!   side is a Split View pair on the tablet, with the same share, and a pair
//!   is such a screen on the desktop. A pair made on the tablet joins its two
//!   windows on one screen; a pair taken apart there takes the screen apart.
//! - An app the tablet minimized because the user left it (for home or
//!   another app: the phone pauses apps out of sight) is back on its screen:
//!   the desktop shows its windows side by side. Windows minimized on the
//!   desktop before stay minimized.
//! - The app in front on the tablet is the current screen on the desktop, and
//!   the current screen's focused window is the app in front on the tablet.

use smithay::desktop::Window;
use smithay::reexports::wayland_server::Resource;
use smithay::reexports::wayland_server::backend::ObjectId;
use smithay::utils::{Logical, Rectangle};
use tracing::info;

use super::super::window_layout::{LayoutDirection, LayoutSpace, WindowLayout, WindowLayoutKind};
use super::WaylandFrontend;
use super::managed_window::ManagedWindow;
use super::split_view::SplitViewPair;

/// The side-by-side screens of one strip in strip order: the left window,
/// the right one and the left one's share.
pub(super) fn side_by_side_screens<WindowId>(
    layout: &dyn WindowLayout<WindowId>,
    space: LayoutSpace,
    work_area: Rectangle<i32, Logical>,
    gap: i32,
) -> Vec<(WindowId, WindowId, f64)>
where
    WindowId: Clone + Eq + 'static,
{
    layout
        .screens(space, work_area, gap)
        .into_iter()
        .filter_map(|screen| layout.side_by_side(screen.windows.first()?, work_area))
        .collect()
}

/// Makes the strip of `space` show every pair (left, right, share) as a
/// screen of those two windows side by side, and takes apart the
/// side-by-side screens no pair holds any more. A window that leaves a
/// screen it shares with others gets a screen of its own right after it.
/// Pairs with a window outside this strip are left alone. Returns whether
/// the strip changed.
pub(super) fn screens_for_pairs<WindowId>(
    layout: &mut dyn WindowLayout<WindowId>,
    space: LayoutSpace,
    work_area: Rectangle<i32, Logical>,
    gap: i32,
    pairs: &[(WindowId, WindowId, f64)],
) -> bool
where
    WindowId: Clone + Eq + 'static,
{
    let paired = |window: &WindowId| {
        pairs
            .iter()
            .any(|(left, right, _)| left == window || right == window)
    };
    let mut changed = false;
    // Taken apart on the tablet.
    for (left, right, _) in side_by_side_screens(layout, space, work_area, gap) {
        if !paired(&left) && !paired(&right) {
            changed |= layout.move_to_column(&right, &left, false);
        }
    }
    for (left, right, share) in pairs {
        if layout.space_for(left) != Some(space) || layout.space_for(right) != Some(space) {
            continue;
        }
        match layout.side_by_side(left, work_area) {
            Some((first, second, _)) if first == *left && second == *right => {}
            Some((first, second, _)) if first == *right && second == *left => {
                changed |= layout.swap(left, right, false);
            }
            _ => {
                // The left window leaves whatever else shares its screen;
                // the right one leaves its own on joining.
                let others = layout
                    .screens(space, work_area, gap)
                    .into_iter()
                    .find(|screen| screen.windows.contains(left))
                    .map(|screen| screen.windows)
                    .unwrap_or_default();
                if let Some(other) = others
                    .iter()
                    .find(|window| *window != left && *window != right)
                {
                    changed |= layout.move_to_column(left, other, false);
                }
                changed |= layout.move_beside(right, left, LayoutDirection::Right);
            }
        }
        changed |= layout.set_side_by_side_share(left, *share, work_area);
    }
    changed
}

impl WaylandFrontend {
    /// The tablet presentation holds the panel alone: the desktop's layout
    /// keeps every window's place, unchanged, until the desktop is back.
    /// With a monitor beside the phone the desks keep their own layouts.
    pub(super) fn desktop_layout_dormant(&self) -> bool {
        self.mobile_shell && !self.phone_with_desk()
    }

    fn layout_work_area(&self, space: LayoutSpace) -> Option<Rectangle<i32, Logical>> {
        let output = self
            .outputs
            .iter()
            .find(|output| output.id == space.output)?;
        Some(self.maximize_work_area(Some(&output.output), output.logical_geometry))
    }

    /// Every layout space of every output.
    fn layout_spaces(&self) -> Vec<LayoutSpace> {
        let workspaces = self.layout_workspace_count();
        self.outputs
            .iter()
            .flat_map(|output| (1..=workspaces).map(|workspace| LayoutSpace::new(output.id, workspace)))
            .collect()
    }

    /// Desktop to tablet: the side-by-side screens become Split View pairs.
    pub(super) fn pair_side_by_side_screens(&mut self) {
        if self.window_layout.kind() != WindowLayoutKind::Screens {
            return;
        }
        let gap = self.layout_gap();
        let mut pairs = Vec::new();
        for space in self.layout_spaces() {
            let Some(work_area) = self.layout_work_area(space) else {
                continue;
            };
            for (left, right, share) in
                side_by_side_screens(self.window_layout.as_ref(), space, work_area, gap)
            {
                if let (Some(left), Some(right)) =
                    (self.surface_ids.get(&left), self.surface_ids.get(&right))
                {
                    pairs.push((*left, *right, share));
                }
            }
        }
        for &(left, right, share) in &pairs {
            self.split_views.split(left, right, true, share);
        }
        if !pairs.is_empty() {
            info!(?pairs, "split screens are Split View pairs on the tablet");
        }
    }

    /// Tablet to desktop: every Split View pair is a screen of its two
    /// windows side by side, and side-by-side screens taken apart on the
    /// tablet come apart. Ends the pairs; the caller arranges.
    pub(super) fn show_split_views_as_screens(&mut self) {
        let pairs = self.split_views.clear();
        if self.window_layout.kind() != WindowLayoutKind::Screens {
            if !pairs.is_empty() {
                info!("Split View ended with the mobile presentation");
            }
            return;
        }
        let pairs = pairs
            .iter()
            .filter_map(|pair| self.layout_pair(pair))
            .collect::<Vec<_>>();
        let gap = self.layout_gap();
        let mut changed = false;
        for space in self.layout_spaces() {
            let Some(work_area) = self.layout_work_area(space) else {
                continue;
            };
            changed |=
                screens_for_pairs(self.window_layout.as_mut(), space, work_area, gap, &pairs);
        }
        if changed || !pairs.is_empty() {
            info!(
                pairs = pairs.len(),
                changed, "Split View pairs are split screens on the desktop"
            );
        }
    }

    /// A pair by its windows' layout ids.
    fn layout_pair(&self, pair: &SplitViewPair) -> Option<(ObjectId, ObjectId, f64)> {
        let id = |window: u64| {
            self.window_for_id(window)
                .and_then(|window| self.window_root_surface(&window))
                .map(|root| root.id())
        };
        Some((id(pair.left)?, id(pair.right)?, pair.ratio))
    }

    /// Tablet to desktop: the windows the tablet minimized are shown again.
    /// Returns how many.
    pub(super) fn restore_windows_the_tablet_minimized(&mut self) -> usize {
        let windows = self
            .space
            .elements()
            .filter(|window| {
                self.window_root_surface(window)
                    .and_then(|root| self.window_record_for_surface(&root.id()))
                    .is_some_and(|record| record.minimized && record.minimized_in_tablet)
            })
            .cloned()
            .collect::<Vec<Window>>();
        for window in &windows {
            let Some(root) = self.window_root_surface(window) else {
                continue;
            };
            if let Some(managed) = ManagedWindow::new(window) {
                managed.prepare_minimized(false, self.window_covered(window));
            }
            self.set_surface_minimized(root.id(), false);
        }
        windows.len()
    }

    /// The window that has the keyboard becomes the current one of its
    /// strip. Returns whether the strip moved.
    pub(super) fn activate_focused_layout_window(&mut self) -> bool {
        let Some(focused) = self.focused_layout_window() else {
            return false;
        };
        // A dialog stands for the screen of its parent.
        let focused = self
            .window_for_layout_id(&focused)
            .and_then(|window| {
                let mut current = window;
                for _ in 0..16 {
                    let id = self.window_root_surface(&current)?.id();
                    if self.window_layout.contains(&id) {
                        return Some(id);
                    }
                    current = self.transient_parent_window(&current)?;
                }
                None
            })
            .unwrap_or(focused);
        self.window_layout.contains(&focused) && self.window_layout.activate(&focused)
    }
}

#[cfg(test)]
mod tests {
    use denial_core::topology::OutputId;
    use smithay::utils::{Point, Size};

    use super::super::super::window_layout::{LayoutAxis, LayoutInsertion, create_window_layout};
    use super::*;

    const SPACE: LayoutSpace = LayoutSpace::new(OutputId(1), 1);
    const GAP: i32 = 8;

    fn area() -> Rectangle<i32, Logical> {
        Rectangle::new(Point::from((0, 40)), Size::from((1000, 600)))
    }

    fn strip(windows: &[u64]) -> Box<dyn WindowLayout<u64>> {
        let mut layout = create_window_layout::<u64>(WindowLayoutKind::Screens);
        let mut anchor = None;
        for &window in windows {
            layout.insert(LayoutInsertion {
                window,
                space: SPACE,
                anchor,
            });
            anchor = Some(window);
        }
        layout.prepare_arrange(SPACE, area(), GAP, LayoutAxis::Horizontal);
        layout
    }

    fn screens(layout: &dyn WindowLayout<u64>) -> Vec<Vec<u64>> {
        layout
            .screens(SPACE, area(), GAP)
            .into_iter()
            .map(|screen| screen.windows)
            .collect()
    }

    fn share(layout: &dyn WindowLayout<u64>, window: u64) -> f64 {
        layout.side_by_side(&window, area()).expect("side by side").2
    }

    #[test]
    fn side_by_side_screens_are_the_pairs_in_strip_order() {
        let mut layout = strip(&[1, 2, 3, 4, 5, 6]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Right));
        assert!(layout.move_beside(&4, &3, LayoutDirection::Down));
        assert!(layout.move_beside(&5, &6, LayoutDirection::Left));
        assert!(layout.set_side_by_side_share(&1, 2.0 / 3.0, area()));
        assert_eq!(screens(layout.as_ref()), vec![vec![1, 2], vec![3, 4], vec![5, 6]]);
        let pairs = side_by_side_screens(layout.as_ref(), SPACE, area(), GAP);
        assert_eq!(pairs.len(), 2);
        assert_eq!((pairs[0].0, pairs[0].1), (1, 2));
        assert!((pairs[0].2 - 2.0 / 3.0).abs() < 1e-9);
        assert_eq!(pairs[1], (5, 6, 0.5));
    }

    #[test]
    fn unchanged_pairs_leave_the_strip_as_it_was() {
        let mut layout = strip(&[1, 2, 3]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Right));
        assert!(layout.set_side_by_side_share(&1, 0.4, area()));
        let pairs = side_by_side_screens(layout.as_ref(), SPACE, area(), GAP);
        assert!(!screens_for_pairs(layout.as_mut(), SPACE, area(), GAP, &pairs));
        assert_eq!(screens(layout.as_ref()), vec![vec![1, 2], vec![3]]);
        assert!((share(layout.as_ref(), 1) - 0.4).abs() < 1e-9);
    }

    #[test]
    fn a_pair_made_on_the_tablet_joins_its_windows_on_the_left_ones_screen() {
        let mut layout = strip(&[1, 2, 3]);
        assert!(screens_for_pairs(
            layout.as_mut(),
            SPACE,
            area(),
            GAP,
            &[(3, 1, 2.0 / 3.0)]
        ));
        // The right one left its screen for the left one's.
        assert_eq!(screens(layout.as_ref()), vec![vec![2], vec![3, 1]]);
        assert_eq!(
            layout.side_by_side(&1, area()).map(|(left, right, _)| (left, right)),
            Some((3, 1))
        );
        assert!((share(layout.as_ref(), 3) - 2.0 / 3.0).abs() < 1e-9);
    }

    #[test]
    fn a_pair_taken_apart_on_the_tablet_takes_its_screen_apart() {
        let mut layout = strip(&[1, 2, 3]);
        assert!(layout.move_beside(&3, &1, LayoutDirection::Right));
        assert_eq!(screens(layout.as_ref()), vec![vec![1, 3], vec![2]]);
        assert!(screens_for_pairs(layout.as_mut(), SPACE, area(), GAP, &[]));
        // The right one gets a screen of its own right after.
        assert_eq!(screens(layout.as_ref()), vec![vec![1], vec![3], vec![2]]);
        // Stacked and crowded screens were never pairs: they stay.
        let mut layout = strip(&[1, 2, 3, 4]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Down));
        assert!(layout.move_beside(&4, &3, LayoutDirection::Right));
        assert!(layout.move_beside(&2, &4, LayoutDirection::Down));
        let before = screens(layout.as_ref());
        assert!(!screens_for_pairs(layout.as_mut(), SPACE, area(), GAP, &[]));
        assert_eq!(screens(layout.as_ref()), before);
    }

    #[test]
    fn a_pair_swapped_or_resized_on_the_tablet_keeps_its_screen() {
        let mut layout = strip(&[1, 2, 3]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Right));
        assert!(screens_for_pairs(
            layout.as_mut(),
            SPACE,
            area(),
            GAP,
            &[(2, 1, 0.7)]
        ));
        assert_eq!(screens(layout.as_ref()), vec![vec![2, 1], vec![3]]);
        assert!((share(layout.as_ref(), 2) - 0.7).abs() < 1e-9);
    }

    #[test]
    fn a_window_paired_away_from_a_shared_screen_leaves_the_rest_there() {
        // [1|2] [3]: the tablet paired 1 with 3; 2 keeps the old screen.
        let mut layout = strip(&[1, 2, 3]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Right));
        assert!(screens_for_pairs(
            layout.as_mut(),
            SPACE,
            area(),
            GAP,
            &[(1, 3, 0.5)]
        ));
        assert_eq!(screens(layout.as_ref()), vec![vec![2], vec![1, 3]]);
        // Two pairs made of one screen's halves and two others.
        let mut layout = strip(&[1, 2, 3, 4]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Right));
        assert!(screens_for_pairs(
            layout.as_mut(),
            SPACE,
            area(),
            GAP,
            &[(1, 3, 0.5), (2, 4, 0.5)]
        ));
        let result = screens(layout.as_ref());
        assert_eq!(result.len(), 2, "{result:?}");
        assert!(result.contains(&vec![1, 3]), "{result:?}");
        assert!(result.contains(&vec![2, 4]), "{result:?}");
    }

    #[test]
    fn a_pair_from_a_crowded_screen_becomes_a_screen_of_its_own() {
        // [1|2|3]: the tablet showed 1 and 2 alone, then paired them.
        let mut layout = strip(&[1, 2, 3]);
        assert!(layout.move_beside(&2, &1, LayoutDirection::Right));
        assert!(layout.move_beside(&3, &2, LayoutDirection::Down));
        assert!(screens_for_pairs(
            layout.as_mut(),
            SPACE,
            area(),
            GAP,
            &[(1, 2, 0.5)]
        ));
        assert_eq!(screens(layout.as_ref()), vec![vec![3], vec![1, 2]]);
        assert_eq!(
            layout.side_by_side(&1, area()).map(|(left, right, _)| (left, right)),
            Some((1, 2))
        );
    }

    #[test]
    fn pairs_outside_the_strip_are_left_alone() {
        let mut layout = strip(&[1, 2]);
        assert!(!screens_for_pairs(
            layout.as_mut(),
            SPACE,
            area(),
            GAP,
            &[(1, 9, 0.5)]
        ));
        assert_eq!(screens(layout.as_ref()), vec![vec![1], vec![2]]);
    }
}
