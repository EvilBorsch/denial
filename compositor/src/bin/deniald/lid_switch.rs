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
//! logind acts on the lid by itself. While Denial holds its
//! `handle-lid-switch` inhibitor (Stay awake), logind leaves the lid alone
//! and the closed cover changes nothing on screen: the panel stays lit and
//! the session as it was.
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

    pub(super) fn take_pending(&mut self) -> Option<bool> {
        self.pending.take()
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
}

/// Whether a device is ignored while the lid is closed: a touchscreen or a
/// pen built into the machine. On the OnePlus Pad 3 these are
/// NVTCapacitiveTouchScreen and NVTCapacitivePen on SPI, which register
/// touches through the closed cover. A touchscreen or pen plugged in or
/// paired (USB, Bluetooth) or a virtual one, and every keyboard, touchpad or
/// mouse, including the keyboard cover's, goes on working; so do the power
/// and volume keys and the lid switch. A touchscreen whose bus could not be
/// read counts as built in.
#[cfg(feature = "flutter")]
pub(super) fn ignored_under_closed_lid(device: InputDeviceTraits) -> bool {
    let attached = matches!(device.bus, Some(BUS_USB | BUS_BLUETOOTH | BUS_VIRTUAL));
    !attached && (device.touch || device.tablet)
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
    fn the_closed_lid_silences_the_built_in_touchscreen_and_pen() {
        // NVTCapacitiveTouchScreen and NVTCapacitivePen.
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            touch: true,
            ..device(BUS_SPI)
        }));
        assert!(ignored_under_closed_lid(InputDeviceTraits {
            tablet: true,
            ..device(BUS_SPI)
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
        // The keyboard cover's keyboard and touchpad (oneplus-pogo-keyboard,
        // BUS_HOST), gpio-keys (volume keys, the lid) and pmic_pwrkey: no
        // touchscreen or pen.
        assert!(!ignored_under_closed_lid(device(BUS_HOST)));
        // A Bluetooth or USB keyboard, mouse, touchscreen or pen.
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
        }
        // uinput, such as a remote session's virtual touchscreen.
        assert!(!ignored_under_closed_lid(InputDeviceTraits {
            touch: true,
            ..device(BUS_VIRTUAL)
        }));
    }
}
