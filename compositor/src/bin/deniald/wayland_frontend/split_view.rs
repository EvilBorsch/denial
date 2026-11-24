//! Split View in the mobile (tablet) presentation: two phone windows side by
//! side, as on iPadOS.
//!
//! deniald owns every phone window's size (`insets.rs`,
//! `mobile_window_geometry`), so it holds the pairs too: the shell asks for
//! a pair (`WindowRequestKind::SplitView`) and draws the two windows, the
//! divider between them and their handles; deniald configures each window to
//! its half of the phone's screen below the status bar. The halves come from
//! the same split arithmetic as the desktop layouts' splits
//! (`window_layout::split_geometry_on_axis`).
//!
//! A pair comes apart when the shell asks (`LeaveSplitView`), when either
//! window goes away or to a desk, and when the presentation leaves mobile:
//! then the full-screen apps layout shows it as a split screen, and its split
//! screens come back as pairs (`presentation_switch.rs`).
//! A window that asks for full screen fills the screen while it is full
//! screen; its pair resumes when it leaves full screen. A pair is minimized
//! and restored as one: what the user left, or brings back, is the pair.

use smithay::desktop::Window;
use smithay::utils::{Logical, Rectangle};
use tracing::{info, warn};

use super::super::window_layout::{LayoutAxis, split_geometry_on_axis};
use super::WaylandFrontend;

/// The divider between the two windows, in logical pixels. The shell draws
/// it in this gap.
pub(crate) const SPLIT_VIEW_GAP: i32 = 10;

/// Two phone windows side by side, by stable window id: `left` takes
/// `ratio` of the width.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct SplitViewPair {
    pub(crate) left: u64,
    pub(crate) right: u64,
    pub(crate) ratio: f64,
}

impl SplitViewPair {
    pub(crate) const fn holds(&self, window: u64) -> bool {
        self.left == window || self.right == window
    }

    pub(crate) const fn partner_of(&self, window: u64) -> Option<u64> {
        if self.left == window {
            Some(self.right)
        } else if self.right == window {
            Some(self.left)
        } else {
            None
        }
    }

    /// `window`'s half of `area`, the phone's screen below the status bar.
    pub(crate) fn rect_of(
        &self,
        window: u64,
        area: Rectangle<i32, Logical>,
    ) -> Option<Rectangle<i32, Logical>> {
        let (left, right) =
            split_geometry_on_axis(area, SPLIT_VIEW_GAP, self.ratio, LayoutAxis::Horizontal);
        if window == self.left {
            Some(left)
        } else if window == self.right {
            Some(right)
        } else {
            None
        }
    }
}

/// The phone's pairs. A window is in one pair at most.
#[derive(Debug, Default)]
pub(crate) struct SplitViews {
    pairs: Vec<SplitViewPair>,
}

impl SplitViews {
    pub(crate) fn pair_of(&self, window: u64) -> Option<SplitViewPair> {
        self.pairs.iter().copied().find(|pair| pair.holds(window))
    }

    pub(crate) fn partner_of(&self, window: u64) -> Option<u64> {
        self.pair_of(window)
            .and_then(|pair| pair.partner_of(window))
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.pairs.is_empty()
    }

    /// Puts `window` and `target` side by side, `window` on the left when
    /// `window_on_left`, the left one taking `ratio` of the width. Another
    /// pair of either comes apart first. Returns every window whose place
    /// changed: the two, and the partners they left.
    pub(crate) fn split(
        &mut self,
        window: u64,
        target: u64,
        window_on_left: bool,
        ratio: f64,
    ) -> Vec<u64> {
        let mut changed = vec![window, target];
        for pair in self
            .pairs
            .iter()
            .filter(|pair| pair.holds(window) || pair.holds(target))
        {
            for id in [pair.left, pair.right] {
                if !changed.contains(&id) {
                    changed.push(id);
                }
            }
        }
        self.pairs
            .retain(|pair| !pair.holds(window) && !pair.holds(target));
        let (left, right) = if window_on_left {
            (window, target)
        } else {
            (target, window)
        };
        self.pairs.push(SplitViewPair {
            left,
            right,
            ratio: clamp_ratio(ratio),
        });
        changed
    }

    /// The pair of `window` comes apart; returns it.
    pub(crate) fn leave(&mut self, window: u64) -> Option<SplitViewPair> {
        let index = self.pairs.iter().position(|pair| pair.holds(window))?;
        Some(self.pairs.remove(index))
    }

    /// Every pair comes apart; returns them.
    pub(crate) fn clear(&mut self) -> Vec<SplitViewPair> {
        std::mem::take(&mut self.pairs)
    }
}

/// The shares the arithmetic accepts, as every desktop split: 10% to 90%.
fn clamp_ratio(ratio: f64) -> f64 {
    if ratio.is_finite() {
        ratio.clamp(0.1, 0.9)
    } else {
        0.5
    }
}

impl WaylandFrontend {
    /// The pair `window` is in, by its stable id.
    pub(super) fn split_view_pair(&self, window: &Window) -> Option<SplitViewPair> {
        let id = self.window_stable_id(window)?;
        self.split_views.pair_of(id)
    }

    fn window_stable_id(&self, window: &Window) -> Option<u64> {
        let root = self.window_root_surface(window)?;
        self.surface_id(&root)
    }

    /// The window whose half `window` lays out in: itself in a pair, or the
    /// split window whose dialog it is.
    pub(super) fn split_view_owner(&self, window: &Window) -> Option<(u64, SplitViewPair)> {
        if self.split_views.is_empty() {
            return None;
        }
        let mut current = window.clone();
        // A malformed transient cycle must not loop: a pair is at most a few
        // dialogs away.
        for _ in 0..16 {
            if let Some(id) = self.window_stable_id(&current)
                && let Some(pair) = self.split_views.pair_of(id)
            {
                return Some((id, pair));
            }
            current = self.transient_parent_window(&current)?;
        }
        None
    }

    /// `SplitView`: `window_id` and `target_window_id` share the phone's
    /// screen. Both must be phone windows in the mobile presentation.
    pub(crate) fn split_view(
        &mut self,
        window_id: u64,
        target_window_id: u64,
        window_on_left: bool,
        ratio: f64,
    ) -> bool {
        let (Some(window), Some(target)) = (
            self.window_for_id(window_id),
            self.window_for_id(target_window_id),
        ) else {
            warn!(
                window_id,
                target_window_id, "refused Split View: no such windows"
            );
            return false;
        };
        if self.mobile_window_geometry(&window).is_none()
            || self.mobile_window_geometry(&target).is_none()
        {
            warn!(
                window_id,
                target_window_id, "refused Split View: not two phone windows"
            );
            return false;
        }
        let changed = self
            .split_views
            .split(window_id, target_window_id, window_on_left, ratio);
        info!(
            window_id,
            target_window_id, window_on_left, ratio, "Split View on the phone"
        );
        self.configure_split_view_windows(&changed);
        true
    }

    /// `LeaveSplitView`: the pair of `window_id` comes apart, and both
    /// windows fill the screen again.
    pub(crate) fn leave_split_view(&mut self, window_id: u64) -> bool {
        let Some(pair) = self.split_views.leave(window_id) else {
            return false;
        };
        info!(window_id, "Split View left");
        self.configure_split_view_windows(&[pair.left, pair.right]);
        true
    }

    /// A window went away or left the phone: its pair comes apart, and its
    /// partner fills the screen.
    pub(super) fn forget_split_view_window(&mut self, window_id: u64) {
        let Some(pair) = self.split_views.leave(window_id) else {
            return;
        };
        if let Some(partner) = pair.partner_of(window_id) {
            info!(window_id, partner, "Split View ended with a window");
            self.configure_split_view_windows(&[partner]);
        }
    }

    fn configure_split_view_windows(&mut self, windows: &[u64]) {
        for &id in windows {
            if let Some(window) = self.window_for_id(id) {
                self.configure_mobile_window(&window);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(x: i32, y: i32, width: i32, height: i32) -> Rectangle<i32, Logical> {
        Rectangle::new((x, y).into(), (width, height).into())
    }

    /// The tablet's screen below the status bar at the shell's scale.
    fn screen() -> Rectangle<i32, Logical> {
        rect(0, 48, 1357, 912)
    }

    #[test]
    fn a_pair_halves_the_screen_with_a_gap_between() {
        let pair = SplitViewPair {
            left: 1,
            right: 2,
            ratio: 0.5,
        };
        let left = pair.rect_of(1, screen()).unwrap();
        let right = pair.rect_of(2, screen()).unwrap();
        assert_eq!(left.loc, (0, 48).into());
        assert_eq!(left.size.h, 912);
        assert_eq!(right.size.h, 912);
        assert_eq!(right.loc.x - (left.loc.x + left.size.w), SPLIT_VIEW_GAP);
        assert_eq!(right.loc.x + right.size.w, 1357);
        assert!((left.size.w - right.size.w).abs() <= 1);
        assert_eq!(pair.rect_of(3, screen()), None);
    }

    #[test]
    fn thirds_split_the_width_without_the_gap() {
        let pair = SplitViewPair {
            left: 1,
            right: 2,
            ratio: 1.0 / 3.0,
        };
        let left = pair.rect_of(1, screen()).unwrap();
        let right = pair.rect_of(2, screen()).unwrap();
        let available = 1357 - SPLIT_VIEW_GAP;
        assert_eq!(left.size.w, (f64::from(available) / 3.0).round() as i32);
        assert_eq!(left.size.w + SPLIT_VIEW_GAP + right.size.w, 1357);
    }

    #[test]
    fn a_split_puts_the_window_on_its_side() {
        let mut views = SplitViews::default();
        assert_eq!(views.split(5, 7, false, 0.5), vec![5, 7]);
        let pair = views.pair_of(5).unwrap();
        assert_eq!((pair.left, pair.right), (7, 5));
        assert_eq!(views.partner_of(7), Some(5));
        assert_eq!(views.partner_of(9), None);
    }

    #[test]
    fn splitting_a_pair_again_changes_its_share_or_swaps_it() {
        let mut views = SplitViews::default();
        views.split(1, 2, true, 0.5);
        assert_eq!(views.split(1, 2, true, 2.0 / 3.0), vec![1, 2]);
        let pair = views.pair_of(2).unwrap();
        assert_eq!((pair.left, pair.right), (1, 2));
        assert!((pair.ratio - 2.0 / 3.0).abs() < 1e-9);
        views.split(1, 2, false, 2.0 / 3.0);
        let pair = views.pair_of(1).unwrap();
        assert_eq!((pair.left, pair.right), (2, 1));
    }

    #[test]
    fn a_window_leaves_its_old_pair_for_a_new_one() {
        let mut views = SplitViews::default();
        views.split(1, 2, true, 0.5);
        views.split(3, 4, true, 0.5);
        // 2 joins 3: 1 and 4 lose their partners and fill the screen.
        let mut changed = views.split(2, 3, true, 0.5);
        changed.sort_unstable();
        assert_eq!(changed, vec![1, 2, 3, 4]);
        assert_eq!(views.partner_of(2), Some(3));
        assert_eq!(views.pair_of(1), None);
        assert_eq!(views.pair_of(4), None);
    }

    #[test]
    fn leaving_takes_the_whole_pair_apart() {
        let mut views = SplitViews::default();
        views.split(1, 2, true, 0.5);
        views.split(3, 4, true, 0.5);
        assert_eq!(
            views.leave(2),
            Some(SplitViewPair {
                left: 1,
                right: 2,
                ratio: 0.5
            })
        );
        assert_eq!(views.pair_of(1), None);
        assert_eq!(views.leave(1), None);
        assert_eq!(views.partner_of(3), Some(4));
        assert_eq!(views.clear().len(), 1);
        assert!(views.is_empty());
    }

    #[test]
    fn a_share_outside_what_splits_take_is_clamped() {
        let mut views = SplitViews::default();
        views.split(1, 2, true, 0.02);
        assert!((views.pair_of(1).unwrap().ratio - 0.1).abs() < 1e-9);
        views.split(1, 2, true, f64::NAN);
        assert!((views.pair_of(1).unwrap().ratio - 0.5).abs() < 1e-9);
    }
}
