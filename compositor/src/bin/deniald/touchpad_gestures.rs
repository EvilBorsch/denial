//! Compositor-owned touchpad gesture recognition.
//!
//! Libinput classifies touchpad sequences; direct touch supplies centroid
//! motion after capturing three or four contacts. Both use the same swipe
//! state machine for shortcut triggers and continuous motion phases.
//! Keeping the recognizer independent from Smithay and the wire protocol makes
//! gestures easy to extend and the state machine deterministic to test.
//!
//! Continuous phases follow the fingers: three fingers sideways move a
//! scrolling strip ([`HorizontalScrollDirections`]), and in the full-screen
//! apps layout three fingers up or down drive the shell's overview or app
//! windows ([`SwipeTracking::vertical`]). Their distances are the device's
//! own units: libinput's swipe travel on a touchpad (about 10.7 per mm on
//! the cover's), logical pixels on the touchscreen.

use std::collections::{HashMap, VecDeque};

use super::native_shortcut::ShortcutGesture;

const DIRECTION_DOMINANCE: f64 = 1.5;
const HORIZONTAL_SCROLL_SLOP: f64 = 8.0;
const HORIZONTAL_SCROLL_VELOCITY_HISTORY_MICROS: u64 = 150_000;
const HORIZONTAL_SCROLL_DECELERATION: f64 = 0.997;
const THREE_FINGER_SWIPE_DISTANCE: f64 = 100.0;
const FOUR_FINGER_SWIPE_DISTANCE: f64 = 100.0;
/// Travel in the gesture's direction before a vertical swipe that follows
/// the fingers starts; as for the horizontal one.
const VERTICAL_TRACKING_SLOP: f64 = HORIZONTAL_SCROLL_SLOP;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SwipeDirection {
    Up,
    Down,
    Left,
    Right,
}

#[derive(Clone, Copy, Debug)]
struct SwipeBinding {
    fingers: u32,
    direction: SwipeDirection,
    minimum_distance: f64,
    gesture: ShortcutGesture,
}

// Adding a supported swipe trigger should normally require only another
// binding here. Its action belongs to the user's shortcut configuration.
// Pinch and hold lifecycles can be added beside `active_swipes` without
// coupling their state to input routing or Flutter serialization.
const SWIPE_BINDINGS: &[SwipeBinding] = &[
    SwipeBinding {
        fingers: 3,
        direction: SwipeDirection::Up,
        minimum_distance: THREE_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::ThreeFingerSwipeUp,
    },
    SwipeBinding {
        fingers: 3,
        direction: SwipeDirection::Down,
        minimum_distance: THREE_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::ThreeFingerSwipeDown,
    },
    SwipeBinding {
        fingers: 3,
        direction: SwipeDirection::Left,
        minimum_distance: THREE_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::ThreeFingerSwipeLeft,
    },
    SwipeBinding {
        fingers: 3,
        direction: SwipeDirection::Right,
        minimum_distance: THREE_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::ThreeFingerSwipeRight,
    },
    SwipeBinding {
        fingers: 4,
        direction: SwipeDirection::Up,
        minimum_distance: FOUR_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::FourFingerSwipeUp,
    },
    SwipeBinding {
        fingers: 4,
        direction: SwipeDirection::Down,
        minimum_distance: FOUR_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::FourFingerSwipeDown,
    },
    SwipeBinding {
        fingers: 4,
        direction: SwipeDirection::Left,
        minimum_distance: FOUR_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::FourFingerSwipeLeft,
    },
    SwipeBinding {
        fingers: 4,
        direction: SwipeDirection::Right,
        minimum_distance: FOUR_FINGER_SWIPE_DISTANCE,
        gesture: ShortcutGesture::FourFingerSwipeRight,
    },
];

/// What a recognized swipe does in the full-screen apps layout, whatever
/// the user's shortcuts say. Three fingers left and right never get here:
/// they move the strip continuously (`HorizontalScrollDirections`), as in
/// the scrolling layout; three fingers up and down follow the fingers too
/// ([`SwipeTracking::vertical`]) and reach this table only from a swipe
/// that started before the layout did.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum ScreensGesture {
    /// The screens overview, or closing the app windows if they are open.
    Overview,
    /// The app windows, or closing the screens overview if it is open.
    AppWindows,
    Launcher,
    Nothing,
}

pub(super) const fn screens_gesture(gesture: ShortcutGesture) -> ScreensGesture {
    match gesture {
        ShortcutGesture::ThreeFingerSwipeUp => ScreensGesture::Overview,
        ShortcutGesture::ThreeFingerSwipeDown => ScreensGesture::AppWindows,
        ShortcutGesture::FourFingerSwipeUp => ScreensGesture::Launcher,
        ShortcutGesture::ThreeFingerSwipeLeft
        | ShortcutGesture::ThreeFingerSwipeRight
        | ShortcutGesture::FourFingerSwipeDown
        | ShortcutGesture::FourFingerSwipeLeft
        | ShortcutGesture::FourFingerSwipeRight => ScreensGesture::Nothing,
    }
}

/// The direction of a three-finger swipe that follows the fingers up or
/// down.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum VerticalSwipe {
    Up,
    Down,
}

impl VerticalSwipe {
    /// Travel toward this direction from motion along y (y grows down).
    fn toward(self, delta_y: f64) -> f64 {
        match self {
            Self::Up => -delta_y,
            Self::Down => delta_y,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) enum TouchpadGestureEvent {
    Trigger(ShortcutGesture),
    Repeat(ShortcutGesture),
    End(ShortcutGesture),
    HorizontalScrollBegin {
        delta_x: f64,
    },
    HorizontalScrollUpdate {
        delta_x: f64,
    },
    HorizontalScrollEnd {
        cancelled: bool,
        projected_delta_x: f64,
    },
    /// Three fingers moved far enough up or down to follow them. `travel`:
    /// how far they went in `direction` since they came down (the device's
    /// units, see the module); it may turn negative later.
    VerticalBegin {
        direction: VerticalSwipe,
        travel: f64,
    },
    /// `velocity`: travel per second toward `direction`.
    VerticalUpdate {
        direction: VerticalSwipe,
        travel: f64,
        velocity: f64,
    },
    /// The fingers lifted. `committed`: the swipe, projected by the speed it
    /// left with, travelled as far as a recognized swipe must
    /// ([`THREE_FINGER_SWIPE_DISTANCE`]), so a flick commits and fingers
    /// that turned back do not. `cancelled`: the swipe was abandoned
    /// (libinput cancelled it, another gesture took over, every touch
    /// ended); never committed then.
    VerticalEnd {
        direction: VerticalSwipe,
        travel: f64,
        velocity: f64,
        committed: bool,
        cancelled: bool,
    },
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct HorizontalScrollDirections {
    pub(super) left: bool,
    pub(super) right: bool,
}

/// The motions of a three-finger swipe that follow the fingers instead of
/// firing a shortcut once.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct SwipeTracking {
    /// Sideways: a scrolling strip moves.
    pub(super) horizontal: HorizontalScrollDirections,
    /// Up and down: the full-screen apps layout's overview and app windows.
    pub(super) vertical: bool,
}

impl From<HorizontalScrollDirections> for SwipeTracking {
    fn from(horizontal: HorizontalScrollDirections) -> Self {
        Self {
            horizontal,
            vertical: false,
        }
    }
}

impl HorizontalScrollDirections {
    fn contains(self, direction: SwipeDirection) -> bool {
        match direction {
            SwipeDirection::Left => self.left,
            SwipeDirection::Right => self.right,
            SwipeDirection::Up | SwipeDirection::Down => false,
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct MotionSample {
    delta: f64,
    timestamp_micros: u64,
}

/// Motion along one axis: where it got to, how fast it went lately, and
/// where that speed would carry it. Swipes and the middle-button drag
/// (`wayland_frontend::middle_drag`) share it.
#[derive(Debug, Default)]
pub(super) struct MotionTracker {
    history: VecDeque<MotionSample>,
    /// The motion since the start.
    pub(super) total: f64,
}

impl MotionTracker {
    pub(super) fn push(&mut self, delta: f64, timestamp_micros: u64) {
        if self
            .history
            .back()
            .is_some_and(|sample| timestamp_micros < sample.timestamp_micros)
        {
            return;
        }
        self.history.push_back(MotionSample {
            delta,
            timestamp_micros,
        });
        self.total += delta;
        while self.history.front().is_some_and(|sample| {
            timestamp_micros.saturating_sub(sample.timestamp_micros)
                > HORIZONTAL_SCROLL_VELOCITY_HISTORY_MICROS
        }) {
            self.history.pop_front();
        }
    }

    /// Motion per second over the last 150 ms.
    pub(super) fn velocity(&self) -> f64 {
        let (Some(first), Some(last)) = (self.history.front(), self.history.back()) else {
            return 0.0;
        };
        let elapsed_micros = last.timestamp_micros.saturating_sub(first.timestamp_micros);
        if elapsed_micros == 0 {
            return 0.0;
        }
        let delta = self.history.iter().map(|sample| sample.delta).sum::<f64>();
        delta / (elapsed_micros as f64 / 1_000_000.0)
    }

    /// Where the motion would stop if it slowed down as a strip's fling
    /// does.
    pub(super) fn projected(&self) -> f64 {
        let projected =
            self.total - self.velocity() / (1_000.0 * HORIZONTAL_SCROLL_DECELERATION.ln());
        if projected.is_finite() {
            projected
        } else {
            self.total
        }
    }
}

#[derive(Debug)]
pub(super) struct ActiveSwipe {
    fingers: u32,
    delta_x: f64,
    delta_y: f64,
    triggered: Option<ShortcutGesture>,
    tracking: SwipeTracking,
    horizontal_scrolling: bool,
    horizontal_scroll_tracker: MotionTracker,
    /// The direction of a vertical swipe that follows the fingers, once it
    /// started.
    vertical: Option<VerticalSwipe>,
    vertical_tracker: MotionTracker,
}

impl ActiveSwipe {
    pub(super) fn new(fingers: u32, tracking: impl Into<SwipeTracking>) -> Self {
        Self {
            fingers,
            delta_x: 0.0,
            delta_y: 0.0,
            triggered: None,
            tracking: tracking.into(),
            horizontal_scrolling: false,
            horizontal_scroll_tracker: MotionTracker::default(),
            vertical: None,
            vertical_tracker: MotionTracker::default(),
        }
    }

    pub(super) fn has_started(&self) -> bool {
        self.triggered.is_some() || self.horizontal_scrolling || self.vertical.is_some()
    }

    /// A vertical swipe that follows the fingers is under way.
    pub(super) fn follows_vertically(&self) -> bool {
        self.vertical.is_some()
    }

    pub(super) fn update(
        &mut self,
        delta_x: f64,
        delta_y: f64,
        timestamp_micros: u64,
    ) -> Result<Option<TouchpadGestureEvent>, ()> {
        if !delta_x.is_finite() || !delta_y.is_finite() {
            return Err(());
        }
        if !(self.horizontal_scroll_tracker.total + delta_x).is_finite()
            || !(self.vertical_tracker.total + delta_y).is_finite()
        {
            return Err(());
        }
        self.horizontal_scroll_tracker
            .push(delta_x, timestamp_micros);
        self.vertical_tracker.push(delta_y, timestamp_micros);
        if self.horizontal_scrolling {
            return Ok((delta_x != 0.0)
                .then_some(TouchpadGestureEvent::HorizontalScrollUpdate { delta_x }));
        }
        if let Some(direction) = self.vertical {
            return Ok(
                (delta_y != 0.0).then_some(TouchpadGestureEvent::VerticalUpdate {
                    direction,
                    travel: direction.toward(self.vertical_tracker.total),
                    velocity: direction.toward(self.vertical_tracker.velocity()),
                }),
            );
        }

        let next_x = self.delta_x + delta_x;
        let next_y = self.delta_y + delta_y;
        if !next_x.is_finite() || !next_y.is_finite() {
            return Err(());
        }
        self.delta_x = next_x;
        self.delta_y = next_y;

        if self.fingers == 3
            && let Some((direction, distance)) = self.direction_and_distance()
            && distance >= HORIZONTAL_SCROLL_SLOP
            && self.tracking.horizontal.contains(direction)
        {
            self.horizontal_scrolling = true;
            let delta_x = std::mem::take(&mut self.delta_x);
            self.delta_y = 0.0;
            return Ok(Some(TouchpadGestureEvent::HorizontalScrollBegin {
                delta_x,
            }));
        }
        if self.fingers == 3
            && self.tracking.vertical
            && let Some((direction, distance)) = self.direction_and_distance()
            && distance >= VERTICAL_TRACKING_SLOP
            && let Some(direction) = match direction {
                SwipeDirection::Up => Some(VerticalSwipe::Up),
                SwipeDirection::Down => Some(VerticalSwipe::Down),
                SwipeDirection::Left | SwipeDirection::Right => None,
            }
        {
            self.vertical = Some(direction);
            self.delta_x = 0.0;
            self.delta_y = 0.0;
            return Ok(Some(TouchpadGestureEvent::VerticalBegin {
                direction,
                travel: direction.toward(self.vertical_tracker.total),
            }));
        }

        let Some(gesture) = self.recognized_gesture() else {
            return Ok(None);
        };
        let event = if self.triggered.is_none() {
            self.triggered = Some(gesture);
            TouchpadGestureEvent::Trigger(gesture)
        } else if matches!(
            gesture,
            ShortcutGesture::ThreeFingerSwipeLeft | ShortcutGesture::ThreeFingerSwipeRight
        ) {
            TouchpadGestureEvent::Repeat(gesture)
        } else {
            return Ok(None);
        };
        self.delta_x = 0.0;
        self.delta_y = 0.0;
        Ok(Some(event))
    }

    fn direction_and_distance(&self) -> Option<(SwipeDirection, f64)> {
        let absolute_x = self.delta_x.abs();
        let absolute_y = self.delta_y.abs();
        let (direction, primary, cross_axis) = if absolute_x > absolute_y {
            let direction = if self.delta_x < 0.0 {
                SwipeDirection::Left
            } else {
                SwipeDirection::Right
            };
            (direction, absolute_x, absolute_y)
        } else {
            let direction = if self.delta_y < 0.0 {
                SwipeDirection::Up
            } else {
                SwipeDirection::Down
            };
            (direction, absolute_y, absolute_x)
        };
        (primary >= cross_axis * DIRECTION_DOMINANCE).then_some((direction, primary))
    }

    fn recognized_gesture(&self) -> Option<ShortcutGesture> {
        let (direction, distance) = self.direction_and_distance()?;
        SWIPE_BINDINGS
            .iter()
            .find(|binding| {
                binding.fingers == self.fingers
                    && binding.direction == direction
                    && distance >= binding.minimum_distance
            })
            .map(|binding| binding.gesture)
    }

    pub(super) fn end_event(
        mut self,
        cancelled: bool,
        timestamp_micros: u64,
    ) -> Option<TouchpadGestureEvent> {
        if self.horizontal_scrolling {
            // Treat time spent stationary before release as zero motion so a
            // deliberate slow stop does not inherit stale fling velocity.
            self.horizontal_scroll_tracker.push(0.0, timestamp_micros);
            Some(TouchpadGestureEvent::HorizontalScrollEnd {
                cancelled,
                projected_delta_x: self.horizontal_scroll_tracker.projected(),
            })
        } else if let Some(direction) = self.vertical {
            self.vertical_tracker.push(0.0, timestamp_micros);
            let projected = direction.toward(self.vertical_tracker.projected());
            Some(TouchpadGestureEvent::VerticalEnd {
                direction,
                travel: direction.toward(self.vertical_tracker.total),
                velocity: direction.toward(self.vertical_tracker.velocity()),
                committed: !cancelled && projected >= THREE_FINGER_SWIPE_DISTANCE,
                cancelled,
            })
        } else {
            self.triggered.map(TouchpadGestureEvent::End)
        }
    }
}

#[derive(Debug, Default)]
pub(super) struct TouchpadGestureRecognizer {
    active_swipes: HashMap<String, ActiveSwipe>,
}

impl TouchpadGestureRecognizer {
    pub(super) fn begin_swipe(
        &mut self,
        device: &str,
        fingers: u32,
        tracking: impl Into<SwipeTracking>,
    ) {
        self.active_swipes
            .insert(device.to_owned(), ActiveSwipe::new(fingers, tracking));
    }

    pub(super) fn update_swipe(
        &mut self,
        device: &str,
        delta_x: f64,
        delta_y: f64,
        timestamp_micros: u64,
    ) -> Option<TouchpadGestureEvent> {
        let update = self
            .active_swipes
            .get_mut(device)?
            .update(delta_x, delta_y, timestamp_micros);
        match update {
            Ok(event) => event,
            Err(()) => self
                .active_swipes
                .remove(device)
                .and_then(|swipe| swipe.end_event(true, timestamp_micros)),
        }
    }

    pub(super) fn end_swipe(
        &mut self,
        device: &str,
        cancelled: bool,
        timestamp_micros: u64,
    ) -> Option<TouchpadGestureEvent> {
        self.active_swipes
            .remove(device)
            .and_then(|swipe| swipe.end_event(cancelled, timestamp_micros))
    }

    /// Forgets every swipe under way: what the ones that followed the
    /// fingers were doing, for their callers to settle.
    pub(super) fn reset(&mut self) -> SwipeReset {
        let reset = SwipeReset {
            horizontal_scrolling: self
                .active_swipes
                .values()
                .any(|swipe| swipe.horizontal_scrolling),
            vertical: self
                .active_swipes
                .values()
                .any(ActiveSwipe::follows_vertically),
        };
        self.active_swipes.clear();
        reset
    }
}

/// What [`TouchpadGestureRecognizer::reset`] cut short.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct SwipeReset {
    /// A strip was moving with the fingers.
    pub(super) horizontal_scrolling: bool,
    /// A vertical swipe followed the fingers.
    pub(super) vertical: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn four_finger_workspace_swipes_support_both_axes() {
        let mut recognizer = TouchpadGestureRecognizer::default();

        recognizer.begin_swipe("touchpad", 4, HorizontalScrollDirections::default());
        assert_eq!(recognizer.update_swipe("touchpad", 60.0, 2.0, 10_000), None);
        assert_eq!(
            recognizer.update_swipe("touchpad", 41.0, 1.0, 20_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::FourFingerSwipeRight
            ))
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", 120.0, 0.0, 30_000),
            None
        );
        assert_eq!(
            recognizer.end_swipe("touchpad", false, 40_000),
            Some(TouchpadGestureEvent::End(
                ShortcutGesture::FourFingerSwipeRight
            ))
        );

        recognizer.begin_swipe("touchpad", 4, HorizontalScrollDirections::default());
        assert_eq!(
            recognizer.update_swipe("touchpad", -101.0, 0.0, 50_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::FourFingerSwipeLeft
            ))
        );

        recognizer.begin_swipe("touchpad", 4, HorizontalScrollDirections::default());
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, -101.0, 60_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::FourFingerSwipeUp
            ))
        );

        recognizer.begin_swipe("touchpad", 4, HorizontalScrollDirections::default());
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, 101.0, 70_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::FourFingerSwipeDown
            ))
        );
    }

    #[test]
    fn four_finger_diagonal_motion_does_not_trigger_a_workspace_swipe() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 4, HorizontalScrollDirections::default());

        assert_eq!(
            recognizer.update_swipe("touchpad", 110.0, 90.0, 10_000),
            None
        );
        assert_eq!(recognizer.end_swipe("touchpad", false, 20_000), None);
    }

    #[test]
    fn enabled_three_finger_horizontal_swipe_streams_raw_motion() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe(
            "touchpad",
            3,
            HorizontalScrollDirections {
                left: true,
                right: true,
            },
        );

        assert_eq!(recognizer.update_swipe("touchpad", -4.0, 0.0, 10_000), None);
        assert_eq!(
            recognizer.update_swipe("touchpad", -5.0, 1.0, 20_000),
            Some(TouchpadGestureEvent::HorizontalScrollBegin { delta_x: -9.0 })
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", -2.5, 30.0, 30_000),
            Some(TouchpadGestureEvent::HorizontalScrollUpdate { delta_x: -2.5 })
        );
        assert_eq!(
            recognizer.end_swipe("touchpad", false, 300_000),
            Some(TouchpadGestureEvent::HorizontalScrollEnd {
                cancelled: false,
                projected_delta_x: -11.5,
            })
        );
    }

    #[test]
    fn quick_horizontal_swipe_projects_past_the_next_tile_threshold() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe(
            "touchpad",
            3,
            HorizontalScrollDirections {
                left: true,
                right: true,
            },
        );

        assert_eq!(recognizer.update_swipe("touchpad", -4.0, 0.0, 10_000), None);
        assert_eq!(
            recognizer.update_swipe("touchpad", -5.0, 0.0, 20_000),
            Some(TouchpadGestureEvent::HorizontalScrollBegin { delta_x: -9.0 })
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", -2.5, 0.0, 30_000),
            Some(TouchpadGestureEvent::HorizontalScrollUpdate { delta_x: -2.5 })
        );
        let Some(TouchpadGestureEvent::HorizontalScrollEnd {
            cancelled: false,
            projected_delta_x,
        }) = recognizer.end_swipe("touchpad", false, 40_000)
        else {
            panic!("quick swipe did not finish as horizontal scrolling");
        };
        assert!(projected_delta_x < -100.0);
        assert!(projected_delta_x > -200.0);
    }

    #[test]
    fn three_fingers_down_is_recognized_like_three_fingers_up() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 3, HorizontalScrollDirections::default());
        assert_eq!(recognizer.update_swipe("touchpad", 1.0, 60.0, 10_000), None);
        assert_eq!(
            recognizer.update_swipe("touchpad", -1.0, 41.0, 20_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::ThreeFingerSwipeDown
            ))
        );
        assert_eq!(
            recognizer.end_swipe("touchpad", false, 30_000),
            Some(TouchpadGestureEvent::End(
                ShortcutGesture::ThreeFingerSwipeDown
            ))
        );
    }

    #[test]
    fn three_fingers_down_in_a_scrolling_strip_does_not_scroll_it() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe(
            "touchpad",
            3,
            HorizontalScrollDirections {
                left: true,
                right: true,
            },
        );
        assert_eq!(recognizer.update_swipe("touchpad", 2.0, 30.0, 10_000), None);
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, 80.0, 20_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::ThreeFingerSwipeDown
            ))
        );
    }

    #[test]
    fn screens_layout_routes_swipes_to_its_views_and_the_launcher() {
        assert_eq!(
            screens_gesture(ShortcutGesture::ThreeFingerSwipeUp),
            ScreensGesture::Overview
        );
        assert_eq!(
            screens_gesture(ShortcutGesture::ThreeFingerSwipeDown),
            ScreensGesture::AppWindows
        );
        assert_eq!(
            screens_gesture(ShortcutGesture::FourFingerSwipeUp),
            ScreensGesture::Launcher
        );
        for gesture in [
            ShortcutGesture::ThreeFingerSwipeLeft,
            ShortcutGesture::ThreeFingerSwipeRight,
            ShortcutGesture::FourFingerSwipeDown,
            ShortcutGesture::FourFingerSwipeLeft,
            ShortcutGesture::FourFingerSwipeRight,
        ] {
            assert_eq!(screens_gesture(gesture), ScreensGesture::Nothing);
        }
    }

    fn screens_tracking() -> SwipeTracking {
        SwipeTracking {
            horizontal: HorizontalScrollDirections {
                left: true,
                right: true,
            },
            vertical: true,
        }
    }

    fn vertical_end(event: Option<TouchpadGestureEvent>) -> (VerticalSwipe, f64, bool, bool) {
        match event {
            Some(TouchpadGestureEvent::VerticalEnd {
                direction,
                travel,
                committed,
                cancelled,
                ..
            }) => (direction, travel, committed, cancelled),
            other => panic!("expected the end of a vertical swipe, got {other:?}"),
        }
    }

    #[test]
    fn three_fingers_up_follow_the_fingers_and_commit_past_the_swipe_distance() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        // Inside the slop: nothing yet.
        assert_eq!(recognizer.update_swipe("touchpad", 0.5, -5.0, 10_000), None);
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, -5.0, 20_000),
            Some(TouchpadGestureEvent::VerticalBegin {
                direction: VerticalSwipe::Up,
                travel: 10.0,
            })
        );
        let Some(TouchpadGestureEvent::VerticalUpdate {
            direction: VerticalSwipe::Up,
            travel,
            velocity,
        }) = recognizer.update_swipe("touchpad", 3.0, -110.0, 30_000)
        else {
            panic!("the swipe did not follow the fingers");
        };
        assert_eq!(travel, 120.0);
        assert!(velocity > 0.0);
        // Sideways motion now moves no strip.
        assert!(matches!(
            recognizer.update_swipe("touchpad", 50.0, -1.0, 40_000),
            Some(TouchpadGestureEvent::VerticalUpdate { .. })
        ));
        assert_eq!(recognizer.update_swipe("touchpad", 50.0, 0.0, 45_000), None);
        // Released after resting: committed by distance alone.
        let (direction, travel, committed, cancelled) =
            vertical_end(recognizer.end_swipe("touchpad", false, 400_000));
        assert_eq!(direction, VerticalSwipe::Up);
        assert_eq!(travel, 121.0);
        assert!(committed);
        assert!(!cancelled);
    }

    #[test]
    fn a_short_slow_swipe_does_not_commit_but_a_flick_does() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        for step in 1..=6 {
            recognizer.update_swipe("touchpad", 0.0, 10.0, step * 100_000);
        }
        let (direction, travel, committed, _) =
            vertical_end(recognizer.end_swipe("touchpad", false, 900_000));
        assert_eq!((direction, travel), (VerticalSwipe::Down, 60.0));
        assert!(!committed);

        // The same 60 units in 30 ms: the speed carries it past 100.
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        for step in 1..=6 {
            recognizer.update_swipe("touchpad", 0.0, 10.0, step * 5_000);
        }
        let (_, travel, committed, _) =
            vertical_end(recognizer.end_swipe("touchpad", false, 35_000));
        assert_eq!(travel, 60.0);
        assert!(committed);
    }

    #[test]
    fn fingers_that_turn_back_go_negative_and_do_not_commit() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        recognizer.update_swipe("touchpad", 0.0, -150.0, 100_000);
        let Some(TouchpadGestureEvent::VerticalUpdate { travel, .. }) =
            recognizer.update_swipe("touchpad", 0.0, 180.0, 400_000)
        else {
            panic!("turning back is part of the swipe");
        };
        assert_eq!(travel, -30.0);
        let (direction, travel, committed, _) =
            vertical_end(recognizer.end_swipe("touchpad", false, 800_000));
        assert_eq!((direction, travel), (VerticalSwipe::Up, -30.0));
        assert!(!committed);
    }

    #[test]
    fn a_cancelled_vertical_swipe_never_commits() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        recognizer.update_swipe("touchpad", 0.0, -300.0, 100_000);
        let (_, _, committed, cancelled) =
            vertical_end(recognizer.end_swipe("touchpad", true, 200_000));
        assert!(!committed);
        assert!(cancelled);

        // Every swipe dropped at once (a device went away, the lock).
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        recognizer.update_swipe("touchpad", 0.0, -30.0, 300_000);
        assert_eq!(
            recognizer.reset(),
            SwipeReset {
                horizontal_scrolling: false,
                vertical: true,
            }
        );
        assert_eq!(recognizer.end_swipe("touchpad", false, 400_000), None);
    }

    #[test]
    fn sideways_three_fingers_keep_moving_the_strip_when_vertical_follows_too() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 3, screens_tracking());
        assert_eq!(
            recognizer.update_swipe("touchpad", -9.0, 1.0, 10_000),
            Some(TouchpadGestureEvent::HorizontalScrollBegin { delta_x: -9.0 })
        );
        // Vertical motion afterwards stays the strip's.
        assert_eq!(
            recognizer.update_swipe("touchpad", -1.0, -200.0, 20_000),
            Some(TouchpadGestureEvent::HorizontalScrollUpdate { delta_x: -1.0 })
        );
        assert!(matches!(
            recognizer.end_swipe("touchpad", false, 30_000),
            Some(TouchpadGestureEvent::HorizontalScrollEnd { .. })
        ));
    }

    #[test]
    fn four_fingers_and_two_fingers_never_follow_vertically() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe("touchpad", 4, screens_tracking());
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, -60.0, 10_000),
            None
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, -41.0, 20_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::FourFingerSwipeUp
            ))
        );
        assert_eq!(
            recognizer.end_swipe("touchpad", false, 30_000),
            Some(TouchpadGestureEvent::End(
                ShortcutGesture::FourFingerSwipeUp
            ))
        );

        // Two fingers (scrolling) are no swipe at all, however far they go.
        recognizer.begin_swipe("touchpad", 2, screens_tracking());
        for step in 1..=10 {
            assert_eq!(
                recognizer.update_swipe("touchpad", 0.0, -50.0, step * 10_000),
                None
            );
        }
        assert_eq!(recognizer.end_swipe("touchpad", false, 200_000), None);
    }

    #[test]
    fn without_vertical_tracking_three_fingers_up_stay_a_shortcut() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe(
            "touchpad",
            3,
            HorizontalScrollDirections {
                left: true,
                right: true,
            },
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, -60.0, 10_000),
            None
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", 0.0, -41.0, 20_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::ThreeFingerSwipeUp
            ))
        );
    }

    #[test]
    fn disabled_horizontal_direction_keeps_the_shortcut_threshold() {
        let mut recognizer = TouchpadGestureRecognizer::default();
        recognizer.begin_swipe(
            "touchpad",
            3,
            HorizontalScrollDirections {
                left: false,
                right: true,
            },
        );

        assert_eq!(
            recognizer.update_swipe("touchpad", -20.0, 0.0, 10_000),
            None
        );
        assert_eq!(
            recognizer.update_swipe("touchpad", -81.0, 0.0, 20_000),
            Some(TouchpadGestureEvent::Trigger(
                ShortcutGesture::ThreeFingerSwipeLeft
            ))
        );
    }
}
