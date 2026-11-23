//! Touchpad pinch and hold gestures for the Wayland client under the pointer
//! (`zwp_pointer_gestures_v1`, version 3). Firefox zooms on a pinch and stops
//! kinetic scrolling when fingers rest on the touchpad (a hold); GTK 4 does
//! the same with its zoom and rotate gestures and in scrolled windows. A pinch
//! with three or four fingers is a pinch too and goes the same way.
//!
//! Swipes stay deniald's own: three and four fingers open the overview,
//! switch windows and workspaces and scroll the scrolling layout
//! (`touchpad_gestures.rs`), and no swipe reaches a client.
//!
//! A gesture goes to a client only when it begins there, decided as scrolling
//! is: not under the secure lock, not over the shell unless a pointer grab
//! holds the pointer. Its updates and end follow Smithay's pointer focus,
//! which ends it, cancelled, if the focus leaves that client before the end,
//! and sends nothing of it to another client. deniald ends it, cancelled,
//! when the session locks or the pointer devices are reset.

use smithay::backend::input::{
    Event, GestureBeginEvent, GestureEndEvent, GesturePinchUpdateEvent as _, InputEvent, InputTime,
};
use smithay::backend::libinput::LibinputInputBackend;
use smithay::input::pointer::{
    GestureHoldBeginEvent, GestureHoldEndEvent, GesturePinchBeginEvent, GesturePinchEndEvent,
    GesturePinchUpdateEvent, PointerHandle,
};
use smithay::utils::SERIAL_COUNTER;

use super::super::super::RuntimeState;

/// A touchpad gesture libinput reports that a client may have.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ClientGesture {
    Pinch,
    Hold,
}

/// The gesture a client has under way: sent its begin and not yet its end.
#[derive(Debug, Default)]
pub(in super::super) struct ClientGestures {
    under_way: Option<ClientGesture>,
}

/// What a client is sent for a pinch update.
#[derive(Debug, PartialEq, Eq)]
enum Update {
    /// The update: the client has the pinch under way.
    Send,
    /// The pinch's end, cancelled: it may not go on.
    Cancel,
    /// Nothing: no client has the pinch.
    Drop,
}

impl ClientGestures {
    /// A gesture begins, at the client when `at_client`. Returns a gesture
    /// still under way, whose end never came: it is to be sent its end,
    /// cancelled, before anything else.
    fn begin(&mut self, gesture: ClientGesture, at_client: bool) -> Option<ClientGesture> {
        let lost = self.under_way.take();
        if at_client {
            self.under_way = Some(gesture);
        }
        lost
    }

    fn update(&mut self, gesture: ClientGesture, may_go_on: bool) -> Update {
        if self.under_way != Some(gesture) {
            Update::Drop
        } else if may_go_on {
            Update::Send
        } else {
            self.under_way = None;
            Update::Cancel
        }
    }

    /// A gesture ends. When the client has it under way, returns whether the
    /// end it is sent is cancelled.
    fn end(&mut self, gesture: ClientGesture, cancelled: bool, may_go_on: bool) -> Option<bool> {
        if self.under_way != Some(gesture) {
            return None;
        }
        self.under_way = None;
        Some(cancelled || !may_go_on)
    }

    /// The gesture under way, which is to be sent its end, cancelled.
    fn cancel(&mut self) -> Option<ClientGesture> {
        self.under_way.take()
    }
}

/// Passes a touchpad pinch or hold to the client under the pointer. Returns
/// whether clients have events to flush, or None for any other event.
pub(super) fn process_client_gesture(
    state: &mut RuntimeState,
    event: &InputEvent<LibinputInputBackend>,
) -> Option<bool> {
    state.wayland.as_ref()?;
    Some(match event {
        InputEvent::GesturePinchBegin { event } => {
            begin(state, ClientGesture::Pinch, event.fingers(), event.time())
        }
        InputEvent::GesturePinchUpdate { event } => {
            let may_go_on = may_go_on(state);
            match state
                .frontend_mut()
                .client_gestures
                .update(ClientGesture::Pinch, may_go_on)
            {
                Update::Send => {
                    pointer(state).gesture_pinch_update(
                        state,
                        &GesturePinchUpdateEvent {
                            time: event.time(),
                            delta: event.delta(),
                            scale: event.scale(),
                            rotation: event.rotation(),
                        },
                    );
                    true
                }
                Update::Cancel => {
                    send_end(state, ClientGesture::Pinch, true, event.time());
                    true
                }
                Update::Drop => false,
            }
        }
        InputEvent::GesturePinchEnd { event } => {
            end(state, ClientGesture::Pinch, event.cancelled(), event.time())
        }
        InputEvent::GestureHoldBegin { event } => {
            begin(state, ClientGesture::Hold, event.fingers(), event.time())
        }
        InputEvent::GestureHoldEnd { event } => {
            end(state, ClientGesture::Hold, event.cancelled(), event.time())
        }
        _ => return None,
    })
}

/// Ends, cancelled, the gesture a client has under way: the pointer devices
/// were reset, so libinput's end will not come. Returns whether it did.
pub(super) fn cancel_client_gesture(state: &mut RuntimeState, time: InputTime) -> bool {
    let Some(gesture) = state
        .wayland
        .as_mut()
        .and_then(|frontend| frontend.client_gestures.cancel())
    else {
        return false;
    };
    send_end(state, gesture, true, time);
    true
}

fn begin(state: &mut RuntimeState, gesture: ClientGesture, fingers: u32, time: InputTime) -> bool {
    let at_client = begins_at_client(state);
    let lost = state
        .frontend_mut()
        .client_gestures
        .begin(gesture, at_client);
    if let Some(lost) = lost {
        send_end(state, lost, true, time);
    }
    if !at_client {
        return lost.is_some();
    }
    let serial = SERIAL_COUNTER.next_serial();
    let pointer = pointer(state);
    match gesture {
        ClientGesture::Pinch => {
            pointer.gesture_pinch_begin(
                state,
                &GesturePinchBeginEvent {
                    serial,
                    time,
                    fingers,
                },
            );
            // A pinch zooms around the pointer: show where that is.
            #[cfg(feature = "flutter")]
            if state.flutter_active {
                state.frontend_mut().set_pointer_cursor_visible(true);
            }
        }
        ClientGesture::Hold => pointer.gesture_hold_begin(
            state,
            &GestureHoldBeginEvent {
                serial,
                time,
                fingers,
            },
        ),
    }
    true
}

fn end(state: &mut RuntimeState, gesture: ClientGesture, cancelled: bool, time: InputTime) -> bool {
    let may_go_on = may_go_on(state);
    let Some(cancelled) = state
        .frontend_mut()
        .client_gestures
        .end(gesture, cancelled, may_go_on)
    else {
        return false;
    };
    send_end(state, gesture, cancelled, time);
    true
}

fn send_end(state: &mut RuntimeState, gesture: ClientGesture, cancelled: bool, time: InputTime) {
    let serial = SERIAL_COUNTER.next_serial();
    let pointer = pointer(state);
    match gesture {
        ClientGesture::Pinch => pointer.gesture_pinch_end(
            state,
            &GesturePinchEndEvent {
                serial,
                time,
                cancelled,
            },
        ),
        ClientGesture::Hold => pointer.gesture_hold_end(
            state,
            &GestureHoldEndEvent {
                serial,
                time,
                cancelled,
            },
        ),
    }
}

/// Whether a gesture beginning now goes to Smithay's pointer, and so to the
/// client it focuses: decided as scrolling is, and only with a client focused.
fn begins_at_client(state: &mut RuntimeState) -> bool {
    #[cfg(feature = "flutter")]
    {
        if state.secure_session_locked() {
            return false;
        }
        if state.flutter_active
            && !super::flutter_route::PointerEventRoute::at_pointer(state).reaches_client()
        {
            return false;
        }
    }
    pointer(state).current_focus().is_some()
}

/// Whether a client's gesture under way may go on: not once the session is
/// locked.
fn may_go_on(state: &RuntimeState) -> bool {
    #[cfg(feature = "flutter")]
    {
        !state.secure_session_locked()
    }
    #[cfg(not(feature = "flutter"))]
    {
        let _ = state;
        true
    }
}

fn pointer(state: &RuntimeState) -> PointerHandle<RuntimeState> {
    state
        .frontend()
        .seat
        .get_pointer()
        .expect("seat has no pointer")
}

#[cfg(test)]
mod tests {
    use super::{ClientGesture, ClientGestures, Update};

    #[test]
    fn a_gesture_begun_at_the_client_goes_on_to_its_end() {
        let mut gestures = ClientGestures::default();
        assert_eq!(gestures.begin(ClientGesture::Pinch, true), None);
        assert_eq!(gestures.update(ClientGesture::Pinch, true), Update::Send);
        assert_eq!(gestures.update(ClientGesture::Pinch, true), Update::Send);
        assert_eq!(gestures.end(ClientGesture::Pinch, false, true), Some(false));
        assert_eq!(gestures.update(ClientGesture::Pinch, true), Update::Drop);
        assert_eq!(gestures.end(ClientGesture::Pinch, false, true), None);
    }

    #[test]
    fn libinput_cancelling_a_gesture_cancels_it_at_the_client() {
        let mut gestures = ClientGestures::default();
        gestures.begin(ClientGesture::Hold, true);
        assert_eq!(gestures.end(ClientGesture::Hold, true, true), Some(true));
    }

    #[test]
    fn a_gesture_begun_over_the_shell_reaches_no_client() {
        let mut gestures = ClientGestures::default();
        assert_eq!(gestures.begin(ClientGesture::Pinch, false), None);
        assert_eq!(gestures.update(ClientGesture::Pinch, true), Update::Drop);
        assert_eq!(gestures.end(ClientGesture::Pinch, false, true), None);
        assert_eq!(gestures.cancel(), None);
    }

    #[test]
    fn locking_the_session_cancels_a_pinch_under_way() {
        let mut gestures = ClientGestures::default();
        gestures.begin(ClientGesture::Pinch, true);
        assert_eq!(gestures.update(ClientGesture::Pinch, false), Update::Cancel);
        assert_eq!(gestures.update(ClientGesture::Pinch, true), Update::Drop);
        assert_eq!(gestures.end(ClientGesture::Pinch, false, true), None);
    }

    #[test]
    fn a_hold_ending_under_the_lock_is_cancelled() {
        let mut gestures = ClientGestures::default();
        gestures.begin(ClientGesture::Hold, true);
        assert_eq!(gestures.end(ClientGesture::Hold, false, false), Some(true));
    }

    #[test]
    fn a_gesture_whose_end_was_lost_is_cancelled_by_the_next_begin() {
        let mut gestures = ClientGestures::default();
        gestures.begin(ClientGesture::Hold, true);
        assert_eq!(
            gestures.begin(ClientGesture::Pinch, true),
            Some(ClientGesture::Hold)
        );
        assert_eq!(gestures.end(ClientGesture::Hold, false, true), None);
        assert_eq!(gestures.end(ClientGesture::Pinch, false, true), Some(false));
        gestures.begin(ClientGesture::Pinch, true);
        assert_eq!(
            gestures.begin(ClientGesture::Hold, false),
            Some(ClientGesture::Pinch)
        );
        assert_eq!(gestures.end(ClientGesture::Hold, false, true), None);
    }

    #[test]
    fn a_reset_cancels_the_gesture_under_way_once() {
        let mut gestures = ClientGestures::default();
        gestures.begin(ClientGesture::Pinch, true);
        assert_eq!(gestures.cancel(), Some(ClientGesture::Pinch));
        assert_eq!(gestures.cancel(), None);
        assert_eq!(gestures.update(ClientGesture::Pinch, true), Update::Drop);
    }
}
