//! The shell gestures that follow the fingers or the pointer.
//!
//! In the full-screen apps layout three fingers up or down (on the touchpad
//! or the touchscreen) and a middle-button drag up or down open the screens
//! overview or the app windows as far as they travel, as Mission Control
//! does on macOS. deniald recognizes them and tells the shell their phase
//! and progress (`wire::ShellGesture`); the shell animates its view from
//! that and settles it at the end the way `committed` says.
//!
//! One gesture drives the shell at a time. While one source drives it, a
//! gesture that another source starts is ignored to its end, so two hands
//! (or a hand and the mouse) never fight over the view.

use super::wire::{ShellGesture, ShellGestureKind, ShellGesturePhase};

/// Where a shell gesture comes from.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ShellGestureSource {
    /// Three fingers on a touchpad, or on the touchscreen used as an input
    /// deck.
    Touchpad,
    /// Three fingers on the touchscreen.
    Touchscreen,
    /// A drag with the middle mouse button held.
    MiddleButton,
}

#[derive(Clone, Copy, Debug)]
struct Active {
    kind: ShellGestureKind,
    source: ShellGestureSource,
    progress: f32,
}

/// The shell gesture under way, if any, and the messages that tell the
/// shell about it.
#[derive(Debug, Default)]
pub(crate) struct ShellGestures {
    active: Option<Active>,
}

impl ShellGestures {
    /// The direction and source of the gesture under way.
    pub(crate) fn active(&self) -> Option<(ShellGestureKind, ShellGestureSource)> {
        self.active.map(|active| (active.kind, active.source))
    }

    /// `source` starts a gesture toward `kind`, `progress` along already.
    /// Nothing while another source's gesture drives the shell; a gesture of
    /// the same source still under way (its end was lost) is replaced.
    pub(crate) fn begin(
        &mut self,
        source: ShellGestureSource,
        kind: ShellGestureKind,
        progress: f64,
    ) -> Option<ShellGesture> {
        if self.active.is_some_and(|active| active.source != source) {
            return None;
        }
        let progress = finite_or(progress, 0.0);
        self.active = Some(Active {
            kind,
            source,
            progress,
        });
        Some(ShellGesture {
            kind,
            phase: ShellGesturePhase::Begin,
            progress,
            velocity: 0.0,
            committed: false,
        })
    }

    /// The gesture of `source` moved on to `progress`, at `velocity`
    /// (progress per second).
    pub(crate) fn update(
        &mut self,
        source: ShellGestureSource,
        progress: f64,
        velocity: f64,
    ) -> Option<ShellGesture> {
        let active = self
            .active
            .as_mut()
            .filter(|active| active.source == source)?;
        active.progress = finite_or(progress, active.progress);
        Some(ShellGesture {
            kind: active.kind,
            phase: ShellGesturePhase::Update,
            progress: active.progress,
            velocity: finite_or(velocity, 0.0),
            committed: false,
        })
    }

    /// The gesture of `source` ended at `progress`, leaving at `velocity`;
    /// `committed`: its view opens.
    pub(crate) fn end(
        &mut self,
        source: ShellGestureSource,
        progress: f64,
        velocity: f64,
        committed: bool,
    ) -> Option<ShellGesture> {
        let active = self.active.filter(|active| active.source == source)?;
        self.active = None;
        Some(ShellGesture {
            kind: active.kind,
            phase: ShellGesturePhase::End,
            progress: finite_or(progress, active.progress),
            velocity: finite_or(velocity, 0.0),
            committed,
        })
    }

    /// Abandons the gesture of `source`, or the gesture under way whatever
    /// drives it (`None`: the session locked, the shell went away).
    pub(crate) fn cancel(&mut self, source: Option<ShellGestureSource>) -> Option<ShellGesture> {
        let active = self
            .active
            .filter(|active| source.is_none_or(|source| active.source == source))?;
        self.active = None;
        Some(ShellGesture {
            kind: active.kind,
            phase: ShellGesturePhase::Cancel,
            progress: active.progress,
            velocity: 0.0,
            committed: false,
        })
    }
}

/// `value` as the wire's f32, or `fallback` when it is not finite there.
fn finite_or(value: f64, fallback: f32) -> f32 {
    let value = value as f32;
    if value.is_finite() { value } else { fallback }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_gesture_begins_follows_and_ends_committed() {
        let mut gestures = ShellGestures::default();
        let begin = gestures
            .begin(ShellGestureSource::Touchpad, ShellGestureKind::Up, 0.02)
            .unwrap();
        assert_eq!(begin.phase, ShellGesturePhase::Begin);
        assert_eq!(begin.kind, ShellGestureKind::Up);
        assert_eq!(begin.progress, 0.02);
        assert_eq!(
            gestures.active(),
            Some((ShellGestureKind::Up, ShellGestureSource::Touchpad))
        );
        let update = gestures
            .update(ShellGestureSource::Touchpad, 0.6, 2.5)
            .unwrap();
        assert_eq!(update.phase, ShellGesturePhase::Update);
        assert_eq!((update.progress, update.velocity), (0.6, 2.5));
        // Past fully open, and back below zero: both pass through.
        assert_eq!(
            gestures
                .update(ShellGestureSource::Touchpad, 1.3, 0.0)
                .unwrap()
                .progress,
            1.3
        );
        assert_eq!(
            gestures
                .update(ShellGestureSource::Touchpad, -0.2, -1.0)
                .unwrap()
                .progress,
            -0.2
        );
        let end = gestures
            .end(ShellGestureSource::Touchpad, 0.8, 1.0, true)
            .unwrap();
        assert_eq!(end.phase, ShellGesturePhase::End);
        assert!(end.committed);
        assert_eq!(gestures.active(), None);
        // Nothing more for it.
        assert_eq!(
            gestures.update(ShellGestureSource::Touchpad, 0.9, 0.0),
            None
        );
        assert_eq!(
            gestures.end(ShellGestureSource::Touchpad, 0.9, 0.0, true),
            None
        );
    }

    #[test]
    fn a_gesture_that_turns_back_ends_uncommitted() {
        let mut gestures = ShellGestures::default();
        gestures.begin(ShellGestureSource::Touchscreen, ShellGestureKind::Down, 0.0);
        let end = gestures
            .end(ShellGestureSource::Touchscreen, 0.1, -3.0, false)
            .unwrap();
        assert_eq!(end.kind, ShellGestureKind::Down);
        assert!(!end.committed);
    }

    #[test]
    fn one_source_drives_the_shell_at_a_time() {
        let mut gestures = ShellGestures::default();
        gestures.begin(ShellGestureSource::Touchpad, ShellGestureKind::Up, 0.0);
        assert_eq!(
            gestures.begin(
                ShellGestureSource::MiddleButton,
                ShellGestureKind::Down,
                0.1
            ),
            None
        );
        assert_eq!(
            gestures.update(ShellGestureSource::MiddleButton, 0.5, 0.0),
            None
        );
        assert_eq!(
            gestures.end(ShellGestureSource::MiddleButton, 0.5, 0.0, true),
            None
        );
        assert_eq!(
            gestures.cancel(Some(ShellGestureSource::MiddleButton)),
            None
        );
        assert_eq!(
            gestures.active(),
            Some((ShellGestureKind::Up, ShellGestureSource::Touchpad))
        );
        // The same source starting again replaces its lost gesture.
        let again = gestures
            .begin(ShellGestureSource::Touchpad, ShellGestureKind::Down, 0.05)
            .unwrap();
        assert_eq!(again.kind, ShellGestureKind::Down);
    }

    #[test]
    fn a_cancel_reports_where_the_gesture_was() {
        let mut gestures = ShellGestures::default();
        assert_eq!(gestures.cancel(None), None);
        gestures.begin(ShellGestureSource::MiddleButton, ShellGestureKind::Up, 0.0);
        gestures.update(ShellGestureSource::MiddleButton, 0.4, 1.0);
        let cancel = gestures.cancel(None).unwrap();
        assert_eq!(cancel.phase, ShellGesturePhase::Cancel);
        assert_eq!(cancel.progress, 0.4);
        assert!(!cancel.committed);
        assert_eq!(gestures.active(), None);
    }

    #[test]
    fn progress_that_is_not_finite_never_reaches_the_wire() {
        let mut gestures = ShellGestures::default();
        let begin = gestures
            .begin(ShellGestureSource::Touchpad, ShellGestureKind::Up, f64::NAN)
            .unwrap();
        assert_eq!(begin.progress, 0.0);
        gestures.update(ShellGestureSource::Touchpad, 0.5, 1.0);
        let update = gestures
            .update(ShellGestureSource::Touchpad, f64::INFINITY, f64::NAN)
            .unwrap();
        assert_eq!((update.progress, update.velocity), (0.5, 0.0));
        let end = gestures
            .end(ShellGestureSource::Touchpad, 1e300, 0.0, true)
            .unwrap();
        assert_eq!(end.progress, 0.5);
    }
}
