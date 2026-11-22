//! Laptop lid position for the runtime display policy.
//!
//! libinput reports each lid toggle as it happens, but it withholds the
//! initial position of switches it does not trust, and a session away from its
//! VT receives no toggles. logind reads the switch itself. It supplies the
//! position at startup, and again whenever libinput may have missed a change:
//! after the session returns to its VT and after system sleep.
//!
//! logind acts on the lid by itself. While Denial holds its
//! `handle-lid-switch` inhibitor (Stay awake), logind leaves the lid alone
//! and [`Cover`] decides what the compositor does instead: the closed cover
//! turns the displays off, the opened cover lights them again.

#[cfg(feature = "flutter")]
use smithay::reexports::calloop::channel::Sender;
#[cfg(feature = "flutter")]
use tracing::warn;
use tracing::{debug, info};

const LOGIND: &str = "org.freedesktop.login1";
const LOGIND_PATH: &str = "/org/freedesktop/login1";
const LOGIND_MANAGER: &str = "org.freedesktop.login1.Manager";

/// Reads whether the lid is closed. logind reports a machine without a lid
/// as open.
pub(super) fn read_closed() -> zbus::Result<bool> {
    let connection = crate::bus::blocking_system()?;
    let reply = connection.call_method(
        Some(LOGIND),
        LOGIND_PATH,
        Some("org.freedesktop.DBus.Properties"),
        "Get",
        &(LOGIND_MANAGER, "LidClosed"),
    )?;
    let value = reply.body().deserialize::<zbus::zvariant::OwnedValue>()?;
    Ok(bool::try_from(value)?)
}

/// Reads the lid position at startup. Without logind the lid counts as open,
/// so the built-in panel behaves as it would on a machine without a lid.
pub(super) fn startup_closed() -> bool {
    match read_closed() {
        Ok(closed) => {
            if closed {
                info!("the lid is closed at startup");
            }
            closed
        }
        Err(error) => {
            debug!(%error, "could not read the lid position from logind; assuming it is open");
            false
        }
    }
}

/// A logind reading, tagged with the libinput toggle it follows.
#[cfg(feature = "flutter")]
pub(super) struct LidReading {
    generation: u64,
    closed: bool,
}

/// Lid observations waiting for the compositor loop to apply them.
#[cfg(feature = "flutter")]
#[derive(Default)]
pub(super) struct LidSwitch {
    pending: Option<bool>,
    /// Advances with every libinput toggle, so a logind reading requested
    /// before a newer toggle cannot overwrite it.
    generation: u64,
    readings: Option<Sender<LidReading>>,
}

#[cfg(feature = "flutter")]
impl LidSwitch {
    pub(super) fn new(readings: Sender<LidReading>) -> Self {
        Self {
            readings: Some(readings),
            ..Self::default()
        }
    }

    pub(super) fn note_toggle(&mut self, closed: bool) {
        self.generation = self.generation.wrapping_add(1);
        self.pending = Some(closed);
    }

    /// Asks logind for the current position without blocking the compositor
    /// thread. The answer arrives through [`Self::note_reading`].
    pub(super) fn request_reading(&self) {
        let Some(readings) = self.readings.clone() else {
            return;
        };
        let generation = self.generation;
        let reader = std::thread::Builder::new()
            .name("denial-lid".to_owned())
            .spawn(move || {
                crate::cpu_scheduling::normalize_current_worker("lid");
                match read_closed() {
                    Ok(closed) => {
                        // The compositor may already be shutting down.
                        let _ = readings.send(LidReading { generation, closed });
                    }
                    Err(error) => debug!(%error, "could not refresh the lid position from logind"),
                }
            });
        if let Err(error) = reader {
            warn!(%error, "could not start the lid position reader");
        }
    }

    pub(super) fn note_reading(&mut self, reading: LidReading) {
        if reading.generation == self.generation {
            self.pending = Some(reading.closed);
        }
    }

    pub(super) fn take_pending(&mut self) -> Option<bool> {
        self.pending.take()
    }
}

/// What the cover does while Denial, not logind, handles the lid switch.
///
/// The closed cover only turns the displays off: the session stays as it
/// was, so opening the cover shows what was on screen. With the inhibitor
/// let go, logind acts on the lid as configured, and the cover asks nothing
/// of the compositor beyond lighting the displays it darkened.
#[cfg(feature = "flutter")]
#[derive(Debug, Default)]
pub(super) struct Cover {
    /// The closed cover turned the displays off; opening it lights them.
    darkened: bool,
}

#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum CoverAction {
    /// Turn the displays off, without locking.
    Darken,
    /// Light the displays the cover turned off.
    Light,
}

#[cfg(feature = "flutter")]
impl Cover {
    /// Follows the lid position the display policy uses (`closed`), whether
    /// Denial holds logind's lid switch handling (`handled`) and whether a
    /// display other than the built-in panels is in use (`docked`), where
    /// logind by default ignores the lid too. Called on every loop turn, it
    /// acts once per closing: the cover closed while handled, or the handling
    /// taken while the cover was closed.
    pub(super) fn update(
        &mut self,
        closed: bool,
        handled: bool,
        docked: bool,
    ) -> Option<CoverAction> {
        if !closed {
            return std::mem::take(&mut self.darkened).then_some(CoverAction::Light);
        }
        if self.darkened || !handled || docked {
            return None;
        }
        self.darkened = true;
        Some(CoverAction::Darken)
    }

    /// Whether the closed cover keeps the displays dark: a notification does
    /// not light the panel under it. The user's own input still does.
    pub(super) fn darkened(&self) -> bool {
        self.darkened
    }
}

#[cfg(all(test, feature = "flutter"))]
mod tests {
    use super::*;

    #[test]
    fn a_logind_reading_never_overwrites_a_newer_toggle() {
        let mut lid = LidSwitch::default();
        let requested_at = lid.generation;
        lid.note_toggle(false);
        assert_eq!(lid.take_pending(), Some(false));

        lid.note_reading(LidReading {
            generation: requested_at,
            closed: true,
        });
        assert_eq!(lid.take_pending(), None);

        lid.note_reading(LidReading {
            generation: lid.generation,
            closed: true,
        });
        assert_eq!(lid.take_pending(), Some(true));
    }

    #[test]
    fn the_cover_darkens_only_while_denial_handles_the_lid() {
        let mut cover = Cover::default();
        // logind handles the lid: it suspends or locks, Denial does nothing.
        assert_eq!(cover.update(true, false, false), None);
        assert!(!cover.darkened());
        assert_eq!(cover.update(false, false, false), None);

        assert_eq!(cover.update(true, true, false), Some(CoverAction::Darken));
        assert!(cover.darkened());
        // Once per closing, however many loop turns follow.
        assert_eq!(cover.update(true, true, false), None);
        assert_eq!(cover.update(false, true, false), Some(CoverAction::Light));
        assert!(!cover.darkened());
        assert_eq!(cover.update(false, true, false), None);
    }

    #[test]
    fn taking_the_lid_while_the_cover_is_closed_darkens_at_once() {
        let mut cover = Cover::default();
        assert_eq!(cover.update(true, false, false), None);
        assert_eq!(cover.update(true, true, false), Some(CoverAction::Darken));
    }

    #[test]
    fn letting_the_lid_go_under_the_closed_cover_leaves_logind_to_act() {
        let mut cover = Cover::default();
        assert_eq!(cover.update(true, true, false), Some(CoverAction::Darken));
        // logind suspends on battery or does nothing on the charger; the
        // displays stay dark until the cover opens.
        assert_eq!(cover.update(true, false, false), None);
        assert!(cover.darkened());
        assert_eq!(cover.update(false, false, false), Some(CoverAction::Light));
    }

    #[test]
    fn an_external_display_keeps_the_desktop_lit_under_the_closed_cover() {
        let mut cover = Cover::default();
        assert_eq!(cover.update(true, true, true), None);
        assert!(!cover.darkened());
        assert_eq!(cover.update(false, true, true), None);
        // Unplugged while the cover is closed: nothing shows the desktop.
        assert_eq!(cover.update(true, true, true), None);
        assert_eq!(cover.update(true, true, false), Some(CoverAction::Darken));
    }
}
