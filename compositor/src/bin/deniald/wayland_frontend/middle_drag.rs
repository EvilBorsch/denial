//! A drag with the middle mouse button held, in the full-screen apps layout:
//! the mouse's three-finger swipe. Sideways it moves the strip of screens
//! with the pointer and snaps (or flings) to a screen on release; up and
//! down it drives the shell's overview and app windows like three fingers
//! (`wire::ShellGesture`).
//!
//! A middle click stays a click: the press is held back until the pointer
//! moves [`MIDDLE_DRAG_THRESHOLD`] away, and a release before that reaches
//! the app as a press and release where the button went down (links open in
//! new tabs, primary selection pastes). The cost is that apps never see a
//! middle-button drag while the switch is on (canvas panning, autoscroll by
//! dragging), which the Settings switch says.
//!
//! This is the decision alone, in logical pixels and microseconds; the
//! pointer grab that applies it is `window_grab::MiddleButtonGrab`.

use smithay::utils::{Logical, Point};

use super::super::touchpad_gestures::MotionTracker;
use super::super::wire::ShellGestureKind;

/// How far the pointer moves with the middle button held before the press is
/// a drag rather than a click: about 2 mm on the tablet's 1357 px wide
/// scene, more than a hand's tremor during a click.
pub(crate) const MIDDLE_DRAG_THRESHOLD: f64 = 10.0;

/// Travel up or down that commits the shell's view on release, projected by
/// the speed the pointer left with: the distance three fingers must swipe.
const SHELL_COMMIT_TRAVEL: f64 = 100.0;

/// What decides whether a middle press may become a drag.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct MiddlePress {
    /// The full-screen apps layout arranges the desk.
    pub(crate) screens_layout: bool,
    /// `layout.screensMiddleButtonGestures`.
    pub(crate) switch_on: bool,
    /// The press goes to an app window (a Wayland or X11 toplevel, or a
    /// dialog over one), not to the shell, a layer surface or an input
    /// method popup.
    pub(crate) over_app_window: bool,
    /// Another button is down: a chord belongs to the app.
    pub(crate) other_buttons_down: bool,
    /// The app holds the pointer: a game's locked or confined pointer.
    pub(crate) pointer_held_by_app: bool,
}

impl MiddlePress {
    /// Whether the press is held back as a possible drag.
    pub(crate) const fn may_drag(self) -> bool {
        self.screens_layout
            && self.switch_on
            && self.over_app_window
            && !self.other_buttons_down
            && !self.pointer_held_by_app
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Mode {
    /// Within the threshold: a click so far.
    Undecided,
    /// Sideways: the strip follows the pointer.
    Strip,
    /// Up or down: the shell's view follows the pointer.
    Shell(ShellGestureKind),
}

/// What a motion with the middle button held does.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum MiddleDragStep {
    /// Still possibly a click: the app sees the pointer move, nothing else.
    Undecided,
    /// The drag just became sideways: move the strip by `delta_x`, the whole
    /// travel since the press.
    StripBegin { delta_x: f64 },
    /// Move the strip on by `delta_x`.
    StripUpdate { delta_x: f64 },
    /// The drag just became vertical: the shell's gesture toward `kind`
    /// starts, `travel` along already (logical px toward it).
    ShellBegin { kind: ShellGestureKind, travel: f64 },
    /// `velocity`: travel per second toward the gesture's direction.
    ShellUpdate { travel: f64, velocity: f64 },
}

/// How the middle button's release ends it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum MiddleDragEnd {
    /// It never moved past the threshold: the app gets a middle click at
    /// `origin`, where the button went down.
    Click { origin: Point<f64, Logical> },
    /// The strip settles on the screen the travel, projected by the speed
    /// the pointer left with, reaches.
    Strip { projected_delta_x: f64 },
    /// The shell's view settles open (`committed`) or closed.
    Shell {
        travel: f64,
        velocity: f64,
        committed: bool,
    },
}

#[derive(Debug)]
pub(crate) struct MiddleDrag {
    origin: Point<f64, Logical>,
    last: Point<f64, Logical>,
    mode: Mode,
    x: MotionTracker,
    y: MotionTracker,
}

impl MiddleDrag {
    /// The middle button went down at `origin`.
    pub(crate) fn new(origin: Point<f64, Logical>, time_micros: u64) -> Self {
        let mut x = MotionTracker::default();
        let mut y = MotionTracker::default();
        x.push(0.0, time_micros);
        y.push(0.0, time_micros);
        Self {
            origin,
            last: origin,
            mode: Mode::Undecided,
            x,
            y,
        }
    }

    /// The drag moves the strip or the shell's view: no click any more.
    pub(crate) fn decided(&self) -> bool {
        self.mode != Mode::Undecided
    }

    /// Whether the drag moves the strip.
    pub(crate) fn moves_strip(&self) -> bool {
        self.mode == Mode::Strip
    }

    /// The pointer moved to `position`.
    pub(crate) fn motion(
        &mut self,
        position: Point<f64, Logical>,
        time_micros: u64,
    ) -> MiddleDragStep {
        if !position.x.is_finite() || !position.y.is_finite() {
            return match self.mode {
                Mode::Undecided => MiddleDragStep::Undecided,
                Mode::Strip => MiddleDragStep::StripUpdate { delta_x: 0.0 },
                Mode::Shell(kind) => MiddleDragStep::ShellUpdate {
                    travel: toward(kind, self.y.total),
                    velocity: toward(kind, self.y.velocity()),
                },
            };
        }
        let step = position - self.last;
        self.last = position;
        self.x.push(step.x, time_micros);
        self.y.push(step.y, time_micros);
        match self.mode {
            Mode::Undecided => {
                let travel = position - self.origin;
                if travel.x.hypot(travel.y) < MIDDLE_DRAG_THRESHOLD {
                    return MiddleDragStep::Undecided;
                }
                if travel.x.abs() >= travel.y.abs() {
                    self.mode = Mode::Strip;
                    MiddleDragStep::StripBegin {
                        delta_x: self.x.total,
                    }
                } else {
                    let kind = if travel.y < 0.0 {
                        ShellGestureKind::Up
                    } else {
                        ShellGestureKind::Down
                    };
                    self.mode = Mode::Shell(kind);
                    MiddleDragStep::ShellBegin {
                        kind,
                        travel: toward(kind, self.y.total),
                    }
                }
            }
            Mode::Strip => MiddleDragStep::StripUpdate { delta_x: step.x },
            Mode::Shell(kind) => MiddleDragStep::ShellUpdate {
                travel: toward(kind, self.y.total),
                velocity: toward(kind, self.y.velocity()),
            },
        }
    }

    /// The middle button came up.
    pub(crate) fn release(mut self, time_micros: u64) -> MiddleDragEnd {
        // Time spent resting before the release is no fling.
        self.x.push(0.0, time_micros);
        self.y.push(0.0, time_micros);
        match self.mode {
            Mode::Undecided => MiddleDragEnd::Click {
                origin: self.origin,
            },
            Mode::Strip => MiddleDragEnd::Strip {
                projected_delta_x: self.x.projected(),
            },
            Mode::Shell(kind) => MiddleDragEnd::Shell {
                travel: toward(kind, self.y.total),
                velocity: toward(kind, self.y.velocity()),
                committed: toward(kind, self.y.projected()) >= SHELL_COMMIT_TRAVEL,
            },
        }
    }
}

/// Travel toward `kind` from motion along y (y grows down).
fn toward(kind: ShellGestureKind, delta_y: f64) -> f64 {
    match kind {
        ShellGestureKind::Up => -delta_y,
        ShellGestureKind::Down => delta_y,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(x: f64, y: f64) -> Point<f64, Logical> {
        Point::from((x, y))
    }

    #[test]
    fn only_a_plain_middle_press_on_an_app_in_the_screens_layout_may_drag() {
        let press = MiddlePress {
            screens_layout: true,
            switch_on: true,
            over_app_window: true,
            other_buttons_down: false,
            pointer_held_by_app: false,
        };
        assert!(press.may_drag());
        for refused in [
            // Another layout, or the switch off.
            MiddlePress {
                screens_layout: false,
                ..press
            },
            MiddlePress {
                switch_on: false,
                ..press
            },
            // Over the shell: the top bar, the overview, the desktop.
            MiddlePress {
                over_app_window: false,
                ..press
            },
            // A chord.
            MiddlePress {
                other_buttons_down: true,
                ..press
            },
            // A game holding the pointer.
            MiddlePress {
                pointer_held_by_app: true,
                ..press
            },
        ] {
            assert!(!refused.may_drag(), "{refused:?}");
        }
    }

    #[test]
    fn a_press_that_stays_within_the_threshold_is_a_click_where_it_went_down() {
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        assert_eq!(
            drag.motion(at(506.0, 404.0), 10_000),
            MiddleDragStep::Undecided
        );
        assert_eq!(
            drag.motion(at(503.0, 407.0), 20_000),
            MiddleDragStep::Undecided
        );
        assert!(!drag.decided());
        assert_eq!(
            drag.release(200_000),
            MiddleDragEnd::Click {
                origin: at(500.0, 400.0)
            }
        );
    }

    #[test]
    fn a_sideways_drag_moves_the_strip_with_the_pointer_and_flings() {
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        assert_eq!(
            drag.motion(at(494.0, 401.0), 10_000),
            MiddleDragStep::Undecided
        );
        // Past the threshold: the whole travel so far moves the strip.
        assert_eq!(
            drag.motion(at(488.0, 402.0), 20_000),
            MiddleDragStep::StripBegin { delta_x: -12.0 }
        );
        assert!(drag.decided() && drag.moves_strip());
        // Then step by step, whatever it does vertically.
        assert_eq!(
            drag.motion(at(400.0, 300.0), 30_000),
            MiddleDragStep::StripUpdate { delta_x: -88.0 }
        );
        let MiddleDragEnd::Strip { projected_delta_x } = drag.release(40_000) else {
            panic!("a sideways drag ends on the strip");
        };
        // Fast to the left: the fling carries past the travel.
        assert!(projected_delta_x < -100.0);

        // Resting before the release: no fling.
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        drag.motion(at(700.0, 400.0), 10_000);
        assert_eq!(
            drag.release(900_000),
            MiddleDragEnd::Strip {
                projected_delta_x: 200.0
            }
        );
    }

    #[test]
    fn up_and_down_drive_the_shell_and_commit_like_three_fingers() {
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        assert_eq!(
            drag.motion(at(503.0, 388.0), 10_000),
            MiddleDragStep::ShellBegin {
                kind: ShellGestureKind::Up,
                travel: 12.0
            }
        );
        let MiddleDragStep::ShellUpdate { travel, velocity } =
            drag.motion(at(520.0, 250.0), 20_000)
        else {
            panic!("an upward drag follows the pointer");
        };
        assert_eq!(travel, 150.0);
        assert!(velocity > 0.0);
        assert_eq!(
            drag.release(800_000),
            MiddleDragEnd::Shell {
                travel: 150.0,
                velocity: 0.0,
                committed: true
            }
        );

        // Down a little and back up past the start: not committed.
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        assert!(matches!(
            drag.motion(at(500.0, 430.0), 10_000),
            MiddleDragStep::ShellBegin {
                kind: ShellGestureKind::Down,
                ..
            }
        ));
        assert!(matches!(
            drag.motion(at(500.0, 380.0), 300_000),
            MiddleDragStep::ShellUpdate { travel, .. } if travel == -20.0
        ));
        assert!(matches!(
            drag.release(900_000),
            MiddleDragEnd::Shell {
                committed: false,
                ..
            }
        ));
    }

    #[test]
    fn a_short_quick_flick_up_commits() {
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        drag.motion(at(500.0, 385.0), 5_000);
        drag.motion(at(500.0, 360.0), 10_000);
        assert!(matches!(
            drag.release(15_000),
            MiddleDragEnd::Shell {
                committed: true,
                ..
            }
        ));
    }

    #[test]
    fn a_position_that_is_not_finite_moves_nothing() {
        let mut drag = MiddleDrag::new(at(500.0, 400.0), 0);
        assert_eq!(
            drag.motion(at(f64::NAN, 400.0), 10_000),
            MiddleDragStep::Undecided
        );
        drag.motion(at(520.0, 400.0), 20_000);
        assert_eq!(
            drag.motion(at(f64::INFINITY, 0.0), 30_000),
            MiddleDragStep::StripUpdate { delta_x: 0.0 }
        );
        assert_eq!(
            drag.release(900_000),
            MiddleDragEnd::Strip {
                projected_delta_x: 20.0
            }
        );
    }
}
