//! Laptop lid position for the runtime display policy and for input.
//!
//! libinput reports each lid toggle as it happens, but it withholds the
//! initial position of switches it does not trust, and a session away from its
//! VT receives no toggles. logind reads the switch itself. It supplies the
//! position at startup, and again whenever libinput may have missed a change:
//! after the session returns to its VT and after system sleep. Only the lid
//! switch says whether the lid is closed, through either; nothing else is
//! taken for it.
//!
//! logind acts on the lid by itself, locking as configured, and the closed
//! cover turns the screen off ([`Cover`]), so that the suspend timeout counts
//! from the closing. While Denial holds its `handle-lid-switch` inhibitor
//! (Stay awake), logind leaves the lid alone and the closed cover changes
//! nothing on screen: the panel stays lit and the session as it was.
//!
//! In any mode, the built-in touchscreen and pen are ignored while the lid
//! is closed ([`ignored_under_closed_lid`]): they register touches through
//! the closed cover. Every other input device goes on working.

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
    /// The last position the lid switch reported, by either source.
    closed: bool,
    pending: Option<bool>,
    /// Advances with every libinput toggle, so a logind reading requested
    /// before a newer toggle cannot overwrite it.
    generation: u64,
    readings: Option<Sender<LidReading>>,
}

#[cfg(feature = "flutter")]
impl LidSwitch {
    /// `closed` is the position logind reported at startup.
    pub(super) fn new(readings: Sender<LidReading>, closed: bool) -> Self {
        Self {
            closed,
            readings: Some(readings),
            ..Self::default()
        }
    }

    pub(super) fn note_toggle(&mut self, closed: bool) {
        self.generation = self.generation.wrapping_add(1);
        self.pending = Some(closed);
        self.closed = closed;
    }

    /// Whether the lid switch last reported the lid closed.
    pub(super) fn closed(&self) -> bool {
        self.closed
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
            self.closed = reading.closed;
        }
    }

    /// Applies an authoritative hardware lid state transition from logind.
    /// Advances `generation` so any earlier in-flight reading cannot overwrite
    /// it.
    pub(super) fn note_logind_state(&mut self, closed: bool) {
        self.generation = self.generation.wrapping_add(1);
        if self.closed != closed {
            self.pending = Some(closed);
            self.closed = closed;
        }
    }

    pub(super) fn take_pending(&mut self) -> Option<bool> {
        self.pending.take()
    }
}

/// The cover opening or closing, as the compositor loop sees the lid.
#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum CoverChange {
    Closed,
    Opened,
}

/// Turns the lid position into changes, once each, whether libinput or a
/// logind reading reported it. The position at startup is no change.
#[cfg(feature = "flutter")]
#[derive(Debug, Default)]
pub(super) struct Cover {
    closed: Option<bool>,
}

#[cfg(feature = "flutter")]
impl Cover {
    pub(super) fn update(&mut self, closed: bool) -> Option<CoverChange> {
        match self.closed.replace(closed) {
            Some(previous) if previous != closed => Some(if closed {
                CoverChange::Closed
            } else {
                CoverChange::Opened
            }),
            _ => None,
        }
    }
}

/// Linux input bus types (`linux/input.h`) of devices plugged in or paired
/// and of virtual ones: none of them is under the cover.
#[cfg(feature = "flutter")]
const BUS_USB: u16 = 0x03;
#[cfg(feature = "flutter")]
const BUS_BLUETOOTH: u16 = 0x05;
#[cfg(feature = "flutter")]
const BUS_VIRTUAL: u16 = 0x06;

/// What decides whether an input device is ignored while the lid is closed.
#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct InputDeviceTraits {
    /// The kernel's bus type (`id/bustype`), if it could be read.
    pub(super) bus: Option<u16>,
    /// A touchscreen.
    pub(super) touch: bool,
    /// A pen, or a drawing tablet's pad.
    pub(super) tablet: bool,
    /// A typing keyboard (not power/volume/lid buttons).
    pub(super) keyboard: bool,
    /// A touchpad.
    pub(super) touchpad: bool,
}

/// Whether a device is ignored while the lid is closed: a built-in
/// touchscreen, pen, typing keyboard or touchpad (anything not on USB,
/// Bluetooth or uinput). On the OnePlus Pad 3 these include
/// NVTCapacitiveTouchScreen, NVTCapacitivePen (SPI) and the folded pogo
/// keyboard cover and touchpad (BUS_HOST), which can register spurious
/// presses against the glass or inside a bag. USB/Bluetooth keyboards, mice,
/// touchscreens or pens, virtual devices, and the power/volume/lid buttons
/// keep working. A covered device whose bus could not be read counts as built
/// in.
#[cfg(feature = "flutter")]
pub(super) fn ignored_under_closed_lid(device: InputDeviceTraits) -> bool {
    let attached = matches!(device.bus, Some(BUS_USB | BUS_BLUETOOTH | BUS_VIRTUAL));
    !attached && (device.touch || device.tablet || device.keyboard || device.touchpad)
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
        assert!(!lid.closed());

        lid.note_reading(LidReading {
            generation: lid.generation,
            closed: true,
        });
        assert_eq!(lid.take_pending(), Some(true));
        assert!(lid.closed());
    }

    #[test]
    fn the_lid_position_follows_toggles_from_the_startup_reading() {
        let (readings, _) = smithay::reexports::calloop::channel::channel();
        let mut lid = LidSwitch::new(readings, true);
        assert!(lid.closed());
        // Read at once by the input path, before the display policy takes it.
        lid.note_toggle(false);
        assert!(!lid.closed());
        lid.note_toggle(true);
        assert!(lid.closed());
        assert_eq!(lid.take_pending(), Some(true));
        assert!(lid.closed());
    }

    #[test]
    fn the_cover_reports_each_closing_and_opening_once() {
        let mut cover = Cover::default();
        // The position at startup is no change.
        assert_eq!(cover.update(true), None);
        assert_eq!(cover.update(false), Some(CoverChange::Opened));
        assert_eq!(cover.update(false), None);
        assert_eq!(cover.update(true), Some(CoverChange::Closed));
        assert_eq!(cover.update(true), None);
        assert_eq!(cover.update(false), Some(CoverChange::Opened));
        let mut cover = Cover::default();
        assert_eq!(cover.update(false), None);
        assert_eq!(cover.update(true), Some(CoverChange::Closed));
    }

    /// `linux/input.h`
    const BUS_HOST: u16 = 0x19;
    const BUS_SPI: u16 = 0x1c;

    fn device(bus: u16) -> InputDeviceTraits {
        InputDeviceTraits {
            bus: Some(bus),
            ..InputDeviceTraits::default()
        }
    }

    #[test]
    fn the_closed_lid_silences_the_built_in_touchscreen_pen_and_cover() {
        // NVTCapacitiveTouchScreen and NVTCapacitivePen.
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            touch: true,
            ..device(BUS_SPI)
        }));
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            tablet: true,
            ..device(BUS_SPI)
        }));
        // The folded keyboard cover and its touchpad (oneplus-pogo-keyboard,
        // BUS_HOST): keys/touchpad pressed against the glass in a bag must not
        // wake the screen.
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            keyboard: true,
            ..device(BUS_HOST)
        }));
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            touchpad: true,
            ..device(BUS_HOST)
        }));
        // An unreadable bus counts as built in.
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            touch: true,
            bus: None,
            ..InputDeviceTraits::default()
        }));
    }

    #[test]
    fn every_other_device_works_under_the_closed_lid() {
        // gpio-keys (volume keys, the lid) and pmic_pwrkey: neither a typing
        // keyboard nor a touchpad, touchscreen or pen.
        assert!(!ignored_under_closed_lid(device(BUS_HOST)));
        // A Bluetooth or USB keyboard, touchpad, mouse, touchscreen or pen.
        for bus in [BUS_USB, BUS_BLUETOOTH] {
            assert!(!ignored_under_closed_lid(device(bus)));
            assert!(!ignored_under_closed_lid(InputDeviceTraits {
                touch: true,
                ..device(bus)
            }));
            assert!(!ignored_under_closed_lid(InputDeviceTraits {
                tablet: true,
                ..device(bus)
            }));
            assert!(!ignored_under_closed_lid(InputDeviceTraits {
                keyboard: true,
                ..device(bus)
            }));
            assert!(!ignored_under_closed_lid(InputDeviceTraits {
                touchpad: true,
                ..device(bus)
            }));
        }
        // uinput, such as a remote session's virtual touchscreen or keyboard.
        assert!(!ignored_under_closed_lid(InputDeviceTraits {
            touch: true,
            ..device(BUS_VIRTUAL)
        }));
        assert!(!ignored_under_closed_lid(InputDeviceTraits {
            keyboard: true,
            ..device(BUS_VIRTUAL)
        }));
    }

    #[test]
    fn logind_lid_state_updates_and_invalidates_older_readings() {
        let mut lid = LidSwitch::default();
        let requested_at = lid.generation;
        lid.note_logind_state(true);
        assert!(lid.closed());
        assert_eq!(lid.take_pending(), Some(true));

        // An older in-flight reading saying open cannot undo the close.
        lid.note_reading(LidReading {
            generation: requested_at,
            closed: false,
        });
        assert!(lid.closed());
        assert_eq!(lid.take_pending(), None);

        // Repeating the same state queues nothing.
        lid.note_logind_state(true);
        assert_eq!(lid.take_pending(), None);

        lid.note_logind_state(false);
        assert!(!lid.closed());
        assert_eq!(lid.take_pending(), Some(false));
    }
}
