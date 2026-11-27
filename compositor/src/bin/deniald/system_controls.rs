//! Persistent native audio and monitor-brightness controls.
//!
//! Input callbacks only enqueue bounded, coalescible commands. PulseAudio and
//! DDC/CI traffic stays on dedicated workers because either native library can
//! block while reconnecting or waiting for hardware.

use std::collections::{HashMap, VecDeque};
use std::error::Error;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::fmt;
use std::fs;
use std::io;
#[cfg(feature = "flutter")]
use std::os::fd::OwnedFd;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Arc;
#[cfg(feature = "flutter")]
use std::sync::atomic::AtomicU8;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use libloading::Library;
use tracing::{info, warn};

const CONTROL_STEP: f64 = 0.05;
const MAX_AUDIO_LEVEL: f64 = 1.4;
const DDC_COALESCE_WINDOW: Duration = Duration::from_millis(24);
const COMMAND_QUEUE_CAPACITY: usize = 128;
const EVENT_QUEUE_CAPACITY: usize = 64;
const MAX_AUDIO_STREAMS: usize = 256;
const MAX_AUDIO_STREAM_NAME_BYTES: usize = 1024;
const MAX_AUDIO_DEVICES: usize = 128;
const MAX_AUDIO_DEVICE_NAME_BYTES: usize = 1024;
const MAX_AUDIO_DEVICE_DESCRIPTION_BYTES: usize = 1024;
const MAX_BRIGHTNESS_CONNECTOR_BYTES: usize = 128;

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AudioStreamState {
    pub(super) id: u32,
    pub(super) name: String,
    pub(super) level_percent: u8,
    pub(super) muted: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct AudioDeviceState {
    pub(super) name: String,
    pub(super) description: String,
    pub(super) active: bool,
    pub(super) available: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum SystemControlEvent {
    AudioLevel {
        level: f64,
        muted: bool,
        limit_reached: bool,
        from_key: bool,
        request_serial: u32,
    },
    CallVolume {
        previous: u32,
        step: u32,
        maximum: u32,
    },
    AudioStreams(Vec<AudioStreamState>),
    AudioDevices(Vec<AudioDeviceState>),
    BrightnessLevel {
        monitor_id: i64,
        level: f64,
    },
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum AudioRequest {
    ReadLevel,
    SetLevel { level: f64, request_serial: u32 },
    SetCallVolume(u32),
    RequestStreams,
    SetStreamLevel { stream_id: u32, level: f64 },
    RequestDevices,
    SetDevice { name: String },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum AudioRequestDecodeError {
    InvalidSize(usize),
    UnsupportedCommand(u8),
}

impl fmt::Display for AudioRequestDecodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSize(size) => write!(formatter, "invalid audio packet size {size}"),
            Self::UnsupportedCommand(command) => {
                write!(formatter, "unsupported audio command {command}")
            }
        }
    }
}

impl Error for AudioRequestDecodeError {}

pub(super) fn decode_audio_request(packet: &[u8]) -> Result<AudioRequest, AudioRequestDecodeError> {
    match packet {
        [0] => Ok(AudioRequest::ReadLevel),
        [1, percent, serial @ ..] if serial.len() == size_of::<u32>() => {
            let request_serial = u32::from_le_bytes(
                serial
                    .try_into()
                    .expect("audio request serial length was checked"),
            );
            Ok(AudioRequest::SetLevel {
                level: f64::from((*percent).min(100)) / 100.0,
                request_serial,
            })
        }
        [2] => Ok(AudioRequest::RequestStreams),
        [3, id @ ..] if id.len() == size_of::<u32>() + 1 => {
            let stream_id = u32::from_le_bytes(
                id[..size_of::<u32>()]
                    .try_into()
                    .expect("audio stream identity length was checked"),
            );
            Ok(AudioRequest::SetStreamLevel {
                stream_id,
                level: f64::from(id[size_of::<u32>()].min(100)) / 100.0,
            })
        }
        [4] => Ok(AudioRequest::RequestDevices),
        [5, name_length @ ..] if name_length.len() >= size_of::<u16>() => {
            let name_length = usize::from(u16::from_le_bytes(
                name_length[..size_of::<u16>()]
                    .try_into()
                    .expect("audio device name length has a fixed width"),
            ));
            let name = name_length
                .checked_add(3)
                .filter(|packet_length| {
                    name_length > 0
                        && name_length <= MAX_AUDIO_DEVICE_NAME_BYTES
                        && *packet_length == packet.len()
                })
                .and_then(|_| std::str::from_utf8(&packet[3..]).ok())
                .filter(|name| !name.contains('\0'))
                .ok_or(AudioRequestDecodeError::InvalidSize(packet.len()))?;
            Ok(AudioRequest::SetDevice {
                name: name.to_owned(),
            })
        }
        [6, a, b, c, d] => Ok(AudioRequest::SetCallVolume(u32::from_le_bytes([
            *a, *b, *c, *d,
        ]))),
        [command, ..] if matches!(*command, 0..=6) || packet.is_empty() => {
            Err(AudioRequestDecodeError::InvalidSize(packet.len()))
        }
        [command, ..] => Err(AudioRequestDecodeError::UnsupportedCommand(*command)),
        [] => Err(AudioRequestDecodeError::InvalidSize(0)),
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(super) enum BrightnessRequest {
    Read {
        connector: String,
        monitor_id: i64,
    },
    Set {
        connector: String,
        monitor_id: i64,
        level: f64,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum BrightnessRequestDecodeError {
    InvalidSize(usize),
    UnsupportedCommand(u8),
    InvalidMonitorId(i64),
    InvalidConnector,
}

impl fmt::Display for BrightnessRequestDecodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSize(size) => write!(formatter, "invalid brightness packet size {size}"),
            Self::UnsupportedCommand(command) => {
                write!(formatter, "unsupported brightness command {command}")
            }
            Self::InvalidMonitorId(monitor_id) => {
                write!(formatter, "invalid brightness monitor id {monitor_id}")
            }
            Self::InvalidConnector => write!(formatter, "invalid brightness connector"),
        }
    }
}

impl Error for BrightnessRequestDecodeError {}

pub(super) fn decode_brightness_request(
    packet: &[u8],
) -> Result<BrightnessRequest, BrightnessRequestDecodeError> {
    const HEADER_BYTES: usize = 12;
    if packet.len() < HEADER_BYTES {
        return Err(BrightnessRequestDecodeError::InvalidSize(packet.len()));
    }
    let command = packet[0];
    if command > 1 {
        return Err(BrightnessRequestDecodeError::UnsupportedCommand(command));
    }
    let monitor_id = i64::from_le_bytes(
        packet[1..9]
            .try_into()
            .expect("brightness monitor id has a fixed packet width"),
    );
    if monitor_id < 0 {
        return Err(BrightnessRequestDecodeError::InvalidMonitorId(monitor_id));
    }
    let connector_length = usize::from(u16::from_le_bytes(
        packet[10..12]
            .try_into()
            .expect("brightness connector length has a fixed packet width"),
    ));
    if connector_length == 0
        || connector_length > MAX_BRIGHTNESS_CONNECTOR_BYTES
        || packet.len() != HEADER_BYTES + connector_length
    {
        return Err(BrightnessRequestDecodeError::InvalidSize(packet.len()));
    }
    let connector = std::str::from_utf8(&packet[HEADER_BYTES..])
        .ok()
        .filter(|value| !value.contains('\0'))
        .ok_or(BrightnessRequestDecodeError::InvalidConnector)?
        .to_owned();
    match command {
        0 => Ok(BrightnessRequest::Read {
            connector,
            monitor_id,
        }),
        1 => Ok(BrightnessRequest::Set {
            connector,
            monitor_id,
            level: f64::from(packet[9].min(100)) / 100.0,
        }),
        _ => unreachable!("brightness command was range checked"),
    }
}

enum AudioCommand {
    ReadLevel,
    SetLevel {
        level: f64,
        request_serial: u32,
    },
    Adjust(f64),
    #[cfg(feature = "flutter")]
    AdjustCallOnly(bool),
    ToggleMute,
    SetCallVolume(u32),
    RequestStreams,
    SetStreamLevel {
        stream_id: u32,
        level: f64,
    },
    RequestDevices,
    SetDevice {
        name: String,
    },
    Stop,
}

enum BrightnessCommand {
    Read {
        connector: String,
        monitor_id: i64,
    },
    Set {
        connector: String,
        monitor_id: i64,
        level: f64,
    },
    Adjust {
        connector: String,
        monitor_id: i64,
        delta: f64,
    },
    Fade {
        connector: String,
        toward: BrightnessFade,
    },
    Stop,
}

/// A backlight fade that runs beside a shell fade: the shell's level never
/// changes, and the slider hears nothing.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) enum BrightnessFade {
    /// Down to a raw backlight code, keeping the level it left.
    Dim { raw: u32, duration: Duration },
    /// Back to the kept level.
    Restore { duration: Duration },
}

#[cfg(feature = "flutter")]
enum SessionCommand {
    SetSuspendMode(crate::idle_policy::SuspendMode),
    Power {
        action: crate::idle_policy::PowerButtonAction,
        interactive: bool,
    },
    Stop,
}

#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum SleepTransition {
    Preparing,
    Resumed,
}

/// What logind's block inhibitors hold off that inactivity would do, from
/// the Manager's `BlockInhibited` and `BlockWeakInhibited` properties. A weak
/// block counts too: it lets the user's explicit request through, not an
/// automatic one.
#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct LogindBlocks {
    /// `idle`: the session does not go idle. Nothing locks, darkens the
    /// screen or suspends on inactivity.
    pub(super) idle: bool,
    /// `sleep`: the system does not suspend on inactivity.
    pub(super) sleep: bool,
}

#[cfg(feature = "flutter")]
impl LogindBlocks {
    const IDLE: u8 = 1 << 0;
    const SLEEP: u8 = 1 << 1;

    /// Reads one of logind's inhibitor lists, such as
    /// `sleep:idle:handle-power-key`.
    pub(super) fn parse(what: &str) -> Self {
        let mut blocks = Self::default();
        for operation in what.split(':') {
            match operation {
                "idle" => blocks.idle = true,
                "sleep" => blocks.sleep = true,
                _ => {}
            }
        }
        blocks
    }

    pub(super) fn union(self, other: Self) -> Self {
        Self {
            idle: self.idle || other.idle,
            sleep: self.sleep || other.sleep,
        }
    }

    fn bits(self) -> u8 {
        u8::from(self.idle) * Self::IDLE | u8::from(self.sleep) * Self::SLEEP
    }

    fn from_bits(bits: u8) -> Self {
        Self {
            idle: bits & Self::IDLE != 0,
            sleep: bits & Self::SLEEP != 0,
        }
    }
}

#[cfg(feature = "flutter")]
struct SleepMonitorShared {
    transitions: Mutex<VecDeque<SleepTransition>>,
    transitions_pending: AtomicBool,
    delay_inhibitor: Mutex<Option<OwnedFd>>,
    power_key_inhibitor: Mutex<Option<OwnedFd>>,
    /// logind's `handle-lid-switch` block inhibitor, held while the
    /// compositor handles the cover itself ([`SystemControls::hold_lid_switch`]).
    lid_switch_inhibitor: Mutex<Option<OwnedFd>>,
    /// Whether the compositor wants that inhibitor held.
    lid_switch_wanted: AtomicBool,
    /// Whether it is held now; changed only under `lid_switch_inhibitor`.
    lid_switch_held: AtomicBool,
    /// Wakes the monitor when `lid_switch_wanted` changes.
    lid_switch_wake: crate::wakeup::Wakeup,
    /// `LogindBlocks` as last read from logind.
    blocks: AtomicU8,
    /// `LidClosed` as last read from logind: 0 = unknown, 1 = open, 2 = closed.
    lid_closed: AtomicU8,
    lid_closed_dirty: AtomicBool,
    stop: AtomicBool,
    stop_wake: crate::wakeup::Wakeup,
}

#[cfg(feature = "flutter")]
impl SleepMonitorShared {
    const LID_UNKNOWN: u8 = 0;
    const LID_OPEN: u8 = 1;
    const LID_CLOSED: u8 = 2;

    fn new() -> io::Result<Self> {
        Ok(Self {
            transitions: Mutex::default(),
            transitions_pending: AtomicBool::new(false),
            delay_inhibitor: Mutex::default(),
            power_key_inhibitor: Mutex::default(),
            lid_switch_inhibitor: Mutex::default(),
            lid_switch_wanted: AtomicBool::new(false),
            lid_switch_held: AtomicBool::new(false),
            lid_switch_wake: crate::wakeup::Wakeup::new()?,
            blocks: AtomicU8::new(0),
            lid_closed: AtomicU8::new(Self::LID_UNKNOWN),
            lid_closed_dirty: AtomicBool::new(false),
            stop: AtomicBool::new(false),
            stop_wake: crate::wakeup::Wakeup::new()?,
        })
    }

    fn publish(&self, transition: SleepTransition) {
        let mut transitions = self
            .transitions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        const MAX_PENDING_TRANSITIONS: usize = 8;
        if transitions.len() == MAX_PENDING_TRANSITIONS {
            transitions.pop_front();
        }
        transitions.push_back(transition);
        self.transitions_pending.store(true, Ordering::Release);
        drop(transitions);
        crate::loop_wake::wake();
    }

    fn take_transition(&self) -> Option<SleepTransition> {
        if !self.transitions_pending.load(Ordering::Acquire) {
            return None;
        }
        let mut transitions = self
            .transitions
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let transition = transitions.pop_front();
        // Serialize clearing with producers so no queued transition loses its
        // readiness flag.
        self.transitions_pending
            .store(!transitions.is_empty(), Ordering::Release);
        transition
    }

    /// Publishes logind's block inhibitors; a change wakes the compositor,
    /// whose idle policy follows it.
    fn set_blocks(&self, blocks: LogindBlocks) {
        let previous = LogindBlocks::from_bits(self.blocks.swap(blocks.bits(), Ordering::AcqRel));
        if previous == blocks {
            return;
        }
        info!(
            idle = blocks.idle,
            sleep = blocks.sleep,
            "logind block inhibitors changed"
        );
        crate::loop_wake::wake();
    }

    fn blocks(&self) -> LogindBlocks {
        LogindBlocks::from_bits(self.blocks.load(Ordering::Acquire))
    }

    /// Publishes logind's hardware `LidClosed` property; a known change wakes
    /// the compositor so its lid policy follows logind directly even if
    /// libinput synthesizes a lid-open from a paired keyboard.
    fn set_logind_lid_closed(&self, closed: Option<bool>) {
        let encoded = match closed {
            None => Self::LID_UNKNOWN,
            Some(false) => Self::LID_OPEN,
            Some(true) => Self::LID_CLOSED,
        };
        let previous = self.lid_closed.swap(encoded, Ordering::AcqRel);
        if previous == encoded {
            return;
        }
        if let Some(closed) = closed {
            self.lid_closed_dirty.store(true, Ordering::Release);
            info!(closed, "logind lid state changed");
            crate::loop_wake::wake();
        } else {
            self.lid_closed_dirty.store(false, Ordering::Release);
        }
    }

    fn logind_lid_closed(&self) -> Option<bool> {
        match self.lid_closed.load(Ordering::Acquire) {
            Self::LID_OPEN => Some(false),
            Self::LID_CLOSED => Some(true),
            _ => None,
        }
    }

    fn take_logind_lid_closed(&self) -> Option<bool> {
        if !self.lid_closed_dirty.swap(false, Ordering::AcqRel) {
            return None;
        }
        self.logind_lid_closed()
    }

    fn install_delay_inhibitor(&self, inhibitor: OwnedFd) {
        *self
            .delay_inhibitor
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(inhibitor);
    }

    fn release_delay_inhibitor(&self) -> bool {
        self.delay_inhibitor
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
            .is_some()
    }

    fn install_power_key_inhibitor(&self, inhibitor: OwnedFd) {
        *self
            .power_key_inhibitor
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(inhibitor);
    }

    fn release_power_key_inhibitor(&self) {
        self.power_key_inhibitor
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
    }

    /// Records whether the compositor wants logind's lid switch handling;
    /// returns whether that changed. Letting go takes effect here and now:
    /// the inhibitor is a file descriptor, and closing it hands the lid back
    /// to logind. Taking it is a logind call, left to the monitor.
    fn want_lid_switch(&self, wanted: bool) -> bool {
        if self.lid_switch_wanted.swap(wanted, Ordering::AcqRel) == wanted {
            return false;
        }
        if !wanted {
            self.release_lid_switch_inhibitor();
        }
        self.lid_switch_wake.wake();
        true
    }

    fn lid_switch_wanted(&self) -> bool {
        self.lid_switch_wanted.load(Ordering::Acquire)
    }

    fn lid_switch_held(&self) -> bool {
        self.lid_switch_held.load(Ordering::Acquire)
    }

    /// Keeps a lid switch inhibitor logind just handed out, unless the
    /// compositor stopped wanting it while logind answered or the monitor
    /// stops: then it is closed at once. Returns whether it was kept; keeping
    /// it wakes the compositor, whose cover policy follows.
    fn install_lid_switch_inhibitor(&self, inhibitor: OwnedFd) -> bool {
        let mut held = self
            .lid_switch_inhibitor
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Checked under the lock that `release_lid_switch_inhibitor` takes
        // after `want_lid_switch(false)`, so a release never misses this one.
        if !self.lid_switch_wanted() || self.stopping() {
            return false;
        }
        *held = Some(inhibitor);
        self.lid_switch_held.store(true, Ordering::Release);
        drop(held);
        crate::loop_wake::wake();
        true
    }

    /// Closes the lid switch inhibitor if one is held: logind handles the lid
    /// again. Returns whether one was held; that wakes the compositor.
    fn release_lid_switch_inhibitor(&self) -> bool {
        let released = {
            let mut held = self
                .lid_switch_inhibitor
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.lid_switch_held.store(false, Ordering::Release);
            held.take()
        };
        let released = released.is_some();
        if released {
            crate::loop_wake::wake();
        }
        released
    }

    fn request_stop(&self) {
        self.stop.store(true, Ordering::Release);
        self.stop_wake.wake();
        self.release_delay_inhibitor();
        self.release_power_key_inhibitor();
        self.release_lid_switch_inhibitor();
    }

    fn stopping(&self) -> bool {
        self.stop.load(Ordering::Acquire)
    }

    /// Returns once a stop is requested.
    async fn stopped(&self) {
        while !self.stopping() {
            self.stop_wake.wait().await;
        }
    }
}

#[derive(Clone)]
struct SystemControlEventSender {
    sender: SyncSender<SystemControlEvent>,
    pending: Arc<AtomicBool>,
}

impl SystemControlEventSender {
    fn new(sender: SyncSender<SystemControlEvent>, pending: Arc<AtomicBool>) -> Self {
        Self { sender, pending }
    }

    fn try_send(&self, event: SystemControlEvent) {
        // Publish before the bounded send so a concurrent main-thread swap
        // cannot miss an event which is already visible in the channel. Set
        // it again after success to close the inverse swap-before-send race.
        self.pending.store(true, Ordering::Release);
        if self.sender.try_send(event).is_ok() {
            self.pending.store(true, Ordering::Release);
        }
        crate::loop_wake::wake();
    }
}

/// Process-lifetime handles used by the compositor input path.
pub(super) struct SystemControls {
    audio_commands: SyncSender<AudioCommand>,
    brightness_commands: SyncSender<BrightnessCommand>,
    #[cfg(feature = "flutter")]
    session_commands: SyncSender<SessionCommand>,
    #[cfg(feature = "flutter")]
    suspend_mode: Mutex<Option<crate::idle_policy::SuspendMode>>,
    #[cfg_attr(not(feature = "flutter"), allow(dead_code))]
    events: Receiver<SystemControlEvent>,
    events_pending: Arc<AtomicBool>,
    audio_worker: Option<JoinHandle<()>>,
    brightness_worker: Option<JoinHandle<()>>,
    #[cfg(feature = "flutter")]
    session_worker: Option<JoinHandle<()>>,
    #[cfg(feature = "flutter")]
    sleep_monitor: Arc<SleepMonitorShared>,
    #[cfg(feature = "flutter")]
    sleep_monitor_worker: Option<JoinHandle<()>>,
}

impl SystemControls {
    pub(super) fn new() -> io::Result<Self> {
        #[cfg(feature = "flutter")]
        let sleep_monitor = Arc::new(SleepMonitorShared::new()?);
        let (events_tx, events) = mpsc::sync_channel(EVENT_QUEUE_CAPACITY);
        let events_pending = Arc::new(AtomicBool::new(false));
        let events_tx = SystemControlEventSender::new(events_tx, Arc::clone(&events_pending));
        let (audio_commands, audio_rx) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
        let audio_events = events_tx.clone();
        let subscription_commands = audio_commands.clone();
        let audio_worker = thread::Builder::new()
            .name("denial-audio".into())
            .spawn(move || {
                crate::cpu_scheduling::normalize_current_worker("audio");
                run_audio_worker(audio_rx, audio_events, subscription_commands);
            })?;

        let (brightness_commands, brightness_rx) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
        let brightness_worker = match thread::Builder::new()
            .name("denial-brightness".into())
            .spawn(move || {
                crate::cpu_scheduling::normalize_current_worker("brightness");
                run_brightness_worker(brightness_rx, events_tx);
            }) {
            Ok(worker) => worker,
            Err(error) => {
                let _ = audio_commands.send(AudioCommand::Stop);
                let _ = audio_worker.join();
                return Err(error);
            }
        };

        #[cfg(feature = "flutter")]
        let (session_commands, session_rx) = mpsc::sync_channel(4);
        #[cfg(feature = "flutter")]
        let session_worker = match thread::Builder::new()
            .name("denial-session-power".into())
            .spawn(move || {
                crate::cpu_scheduling::normalize_current_worker("session power");
                run_session_worker(session_rx);
            }) {
            Ok(worker) => worker,
            Err(error) => {
                let _ = audio_commands.send(AudioCommand::Stop);
                let _ = brightness_commands.send(BrightnessCommand::Stop);
                let _ = audio_worker.join();
                let _ = brightness_worker.join();
                return Err(error);
            }
        };

        #[cfg(feature = "flutter")]
        let sleep_monitor_worker = {
            let monitor = Arc::clone(&sleep_monitor);
            match thread::Builder::new()
                .name("denial-sleep-monitor".into())
                .spawn(move || {
                    crate::cpu_scheduling::normalize_current_worker("sleep monitor");
                    run_sleep_monitor(monitor);
                }) {
                Ok(worker) => worker,
                Err(error) => {
                    let _ = audio_commands.send(AudioCommand::Stop);
                    let _ = brightness_commands.send(BrightnessCommand::Stop);
                    let _ = session_commands.send(SessionCommand::Stop);
                    let _ = audio_worker.join();
                    let _ = brightness_worker.join();
                    let _ = session_worker.join();
                    return Err(error);
                }
            }
        };

        Ok(Self {
            audio_commands,
            brightness_commands,
            #[cfg(feature = "flutter")]
            session_commands,
            #[cfg(feature = "flutter")]
            suspend_mode: Mutex::new(None),
            events,
            events_pending,
            audio_worker: Some(audio_worker),
            brightness_worker: Some(brightness_worker),
            #[cfg(feature = "flutter")]
            session_worker: Some(session_worker),
            #[cfg(feature = "flutter")]
            sleep_monitor,
            #[cfg(feature = "flutter")]
            sleep_monitor_worker: Some(sleep_monitor_worker),
        })
    }

    pub(super) fn volume_up(&self) {
        self.adjust_audio(CONTROL_STEP);
    }

    pub(super) fn volume_down(&self) {
        self.adjust_audio(-CONTROL_STEP);
    }

    #[cfg(feature = "flutter")]
    pub(super) fn adjust_locked_call(&self, up: bool) {
        let _ = self
            .audio_commands
            .try_send(AudioCommand::AdjustCallOnly(up));
    }

    pub(super) fn toggle_mute(&self) {
        let _ = self.audio_commands.try_send(AudioCommand::ToggleMute);
    }

    pub(super) fn handle_audio_request(&self, request: AudioRequest) -> bool {
        let command = match request {
            AudioRequest::ReadLevel => AudioCommand::ReadLevel,
            AudioRequest::SetLevel {
                level,
                request_serial,
            } => AudioCommand::SetLevel {
                level,
                request_serial,
            },
            AudioRequest::SetCallVolume(step) => AudioCommand::SetCallVolume(step),
            AudioRequest::RequestStreams => AudioCommand::RequestStreams,
            AudioRequest::SetStreamLevel { stream_id, level } => {
                AudioCommand::SetStreamLevel { stream_id, level }
            }
            AudioRequest::RequestDevices => AudioCommand::RequestDevices,
            AudioRequest::SetDevice { name } => AudioCommand::SetDevice { name },
        };
        self.audio_commands.try_send(command).is_ok()
    }

    pub(super) fn handle_brightness_request(&self, request: BrightnessRequest) -> bool {
        let command = match request {
            BrightnessRequest::Read {
                connector,
                monitor_id,
            } => BrightnessCommand::Read {
                connector,
                monitor_id,
            },
            BrightnessRequest::Set {
                connector,
                monitor_id,
                level,
            } => BrightnessCommand::Set {
                connector,
                monitor_id,
                level,
            },
        };
        self.brightness_commands.try_send(command).is_ok()
    }

    #[cfg(feature = "flutter")]
    pub(super) fn suspend(&self) -> bool {
        self.session_commands
            .try_send(SessionCommand::Power {
                action: crate::idle_policy::PowerButtonAction::Suspend,
                interactive: false,
            })
            .is_ok()
    }

    #[cfg(feature = "flutter")]
    pub(super) fn power_button_action(
        &self,
        action: crate::idle_policy::PowerButtonAction,
    ) -> bool {
        action != crate::idle_policy::PowerButtonAction::Dpms
            && self
                .session_commands
                .try_send(SessionCommand::Power {
                    action,
                    interactive: true,
                })
                .is_ok()
    }

    #[cfg(feature = "flutter")]
    pub(super) fn set_suspend_mode(&self, mode: crate::idle_policy::SuspendMode) -> bool {
        let Ok(mut current) = self.suspend_mode.lock() else {
            return false;
        };
        if *current == Some(mode) {
            return true;
        }
        if self
            .session_commands
            .try_send(SessionCommand::SetSuspendMode(mode))
            .is_err()
        {
            return false;
        }
        *current = Some(mode);
        true
    }

    #[cfg(feature = "flutter")]
    pub(super) fn take_sleep_transition(&self) -> Option<SleepTransition> {
        self.sleep_monitor.take_transition()
    }

    #[cfg(feature = "flutter")]
    pub(super) fn release_sleep_delay(&self) -> bool {
        self.sleep_monitor.release_delay_inhibitor()
    }

    /// What logind's block inhibitors hold off, as last read from logind.
    /// Nothing while logind is out of reach.
    #[cfg(feature = "flutter")]
    pub(super) fn logind_blocks(&self) -> LogindBlocks {
        self.sleep_monitor.blocks()
    }

    /// Hardware lid state last reported by logind, or `None` while logind is
    /// unreachable.
    #[cfg(feature = "flutter")]
    pub(super) fn logind_lid_closed(&self) -> Option<bool> {
        self.sleep_monitor.logind_lid_closed()
    }

    /// Consumes a fresh logind `LidClosed` transition, if one arrived.
    #[cfg(feature = "flutter")]
    pub(super) fn take_logind_lid_closed(&self) -> Option<bool> {
        self.sleep_monitor.take_logind_lid_closed()
    }

    /// Takes logind's handling of the lid switch while `held`, with a
    /// `handle-lid-switch` block inhibitor: closing the cover then neither
    /// suspends nor locks the system, and the panel stays lit (Stay awake).
    /// Suspend asked for any other way, such as the power menu, is not held
    /// off. Letting go is immediate; taking it waits for logind.
    #[cfg(feature = "flutter")]
    pub(super) fn hold_lid_switch(&self, held: bool) {
        if self.sleep_monitor.want_lid_switch(held) {
            if held {
                info!("taking logind's lid switch handling");
            } else {
                info!("handing the lid switch back to logind");
            }
        }
    }

    fn adjust_audio(&self, delta: f64) {
        let _ = self.audio_commands.try_send(AudioCommand::Adjust(delta));
    }

    pub(super) fn brightness_up(&self, connector: String, monitor_id: i64) {
        self.adjust_brightness(connector, monitor_id, CONTROL_STEP);
    }

    pub(super) fn brightness_down(&self, connector: String, monitor_id: i64) {
        self.adjust_brightness(connector, monitor_id, -CONTROL_STEP);
    }

    #[cfg_attr(not(feature = "flutter"), allow(dead_code))]
    pub(super) fn fade_brightness(&self, connector: String, toward: BrightnessFade) {
        let _ = self
            .brightness_commands
            .try_send(BrightnessCommand::Fade { connector, toward });
    }

    fn adjust_brightness(&self, connector: String, monitor_id: i64, delta: f64) {
        let _ = self
            .brightness_commands
            .try_send(BrightnessCommand::Adjust {
                connector,
                monitor_id,
                delta,
            });
    }

    #[cfg_attr(not(feature = "flutter"), allow(dead_code))]
    pub(super) fn take_event_signal(&self) -> bool {
        self.events_pending.swap(false, Ordering::AcqRel)
    }

    #[cfg_attr(not(feature = "flutter"), allow(dead_code))]
    pub(super) fn try_event(&self) -> Option<SystemControlEvent> {
        self.events.try_recv().ok()
    }
}

impl Drop for SystemControls {
    fn drop(&mut self) {
        #[cfg(feature = "flutter")]
        self.sleep_monitor.request_stop();
        let _ = self.audio_commands.send(AudioCommand::Stop);
        let _ = self.brightness_commands.send(BrightnessCommand::Stop);
        #[cfg(feature = "flutter")]
        let _ = self.session_commands.send(SessionCommand::Stop);
        if self
            .audio_worker
            .take()
            .is_some_and(|worker| worker.join().is_err())
        {
            warn!("native audio worker panicked during shutdown");
        }
        if self
            .brightness_worker
            .take()
            .is_some_and(|worker| worker.join().is_err())
        {
            warn!("native brightness worker panicked during shutdown");
        }
        #[cfg(feature = "flutter")]
        {
            if self
                .session_worker
                .take()
                .is_some_and(|worker| worker.join().is_err())
            {
                warn!("native session power worker panicked during shutdown");
            }
            if self
                .sleep_monitor_worker
                .take()
                .is_some_and(|worker| worker.join().is_err())
            {
                warn!("native sleep monitor worker panicked during shutdown");
            }
        }
    }
}

#[path = "system_controls/audio.rs"]
mod audio;
#[path = "system_controls/brightness.rs"]
mod brightness;
#[path = "system_controls/call_volume.rs"]
mod call_volume;
#[cfg(feature = "flutter")]
#[path = "system_controls/session.rs"]
mod session;

use audio::run_audio_worker;
use brightness::run_brightness_worker;
#[cfg(feature = "flutter")]
use session::{run_session_worker, run_sleep_monitor};

#[cfg(all(test, feature = "flutter"))]
mod sleep_readiness_tests {
    use super::*;

    #[test]
    fn idle_sleep_check_does_not_lock_the_queue() {
        let monitor = SleepMonitorShared::new().unwrap();
        let queue = monitor.transitions.lock().unwrap();
        assert_eq!(monitor.take_transition(), None);
        drop(queue);
    }

    #[test]
    fn readiness_stays_set_until_all_transitions_are_consumed() {
        let monitor = SleepMonitorShared::new().unwrap();
        monitor.publish(SleepTransition::Preparing);
        monitor.publish(SleepTransition::Resumed);
        assert_eq!(monitor.take_transition(), Some(SleepTransition::Preparing));
        assert!(monitor.transitions_pending.load(Ordering::Acquire));
        assert_eq!(monitor.take_transition(), Some(SleepTransition::Resumed));
        assert!(!monitor.transitions_pending.load(Ordering::Acquire));
        monitor.publish(SleepTransition::Preparing);
        assert_eq!(monitor.take_transition(), Some(SleepTransition::Preparing));
        assert_eq!(monitor.take_transition(), None);
    }

    #[test]
    fn logind_inhibitor_lists_hold_idle_and_sleep_only() {
        assert_eq!(LogindBlocks::parse(""), LogindBlocks::default());
        // Denial's own power key inhibitor holds nothing off.
        assert_eq!(
            LogindBlocks::parse("handle-power-key"),
            LogindBlocks::default()
        );
        assert_eq!(
            LogindBlocks::parse("sleep:idle:handle-power-key"),
            LogindBlocks {
                idle: true,
                sleep: true,
            }
        );
        assert_eq!(
            LogindBlocks::parse("shutdown:sleep"),
            LogindBlocks {
                idle: false,
                sleep: true,
            }
        );
        assert_eq!(
            LogindBlocks::parse("idle"),
            LogindBlocks {
                idle: true,
                sleep: false,
            }
        );
        // Only whole names count.
        assert_eq!(LogindBlocks::parse("sleepy:idler"), LogindBlocks::default());
        assert_eq!(
            LogindBlocks::parse("idle").union(LogindBlocks::parse("sleep")),
            LogindBlocks {
                idle: true,
                sleep: true,
            }
        );
    }

    #[test]
    fn logind_blocks_round_trip_through_the_shared_state() {
        let monitor = SleepMonitorShared::new().unwrap();
        assert_eq!(monitor.blocks(), LogindBlocks::default());
        for blocks in [
            LogindBlocks {
                idle: true,
                sleep: false,
            },
            LogindBlocks {
                idle: false,
                sleep: true,
            },
            LogindBlocks {
                idle: true,
                sleep: true,
            },
            LogindBlocks::default(),
        ] {
            monitor.set_blocks(blocks);
            assert_eq!(monitor.blocks(), blocks);
        }
    }

    #[test]
    fn producer_and_consumer_do_not_lose_readiness() {
        let monitor = SleepMonitorShared::new().unwrap();
        let barrier = std::sync::Barrier::new(2);
        std::thread::scope(|scope| {
            scope.spawn(|| {
                for _ in 0..1000 {
                    barrier.wait();
                    monitor.publish(SleepTransition::Resumed);
                    barrier.wait();
                }
            });
            for _ in 0..1000 {
                monitor.publish(SleepTransition::Preparing);
                barrier.wait();
                assert_eq!(monitor.take_transition(), Some(SleepTransition::Preparing));
                barrier.wait();
                assert_eq!(monitor.take_transition(), Some(SleepTransition::Resumed));
                assert_eq!(monitor.take_transition(), None);
            }
        });
    }
    /// A stand-in for an inhibitor logind hands out: the test keeps the
    /// other end and sees it close when Denial lets the inhibitor go.
    fn inhibitor() -> (OwnedFd, std::os::unix::net::UnixStream) {
        let (held, logind) = std::os::unix::net::UnixStream::pair().unwrap();
        logind.set_nonblocking(true).unwrap();
        (OwnedFd::from(held), logind)
    }

    fn closed(logind: &std::os::unix::net::UnixStream) -> bool {
        use std::io::Read;
        matches!((&*logind).read(&mut [0_u8; 1]), Ok(0))
    }

    #[test]
    fn the_lid_switch_is_held_only_while_wanted() {
        let monitor = SleepMonitorShared::new().unwrap();
        assert!(!monitor.lid_switch_wanted());
        // Unwanted: an inhibitor that arrives anyway is closed at once.
        let (fd, logind) = inhibitor();
        assert!(!monitor.install_lid_switch_inhibitor(fd));
        assert!(closed(&logind));
        assert!(!monitor.lid_switch_held());

        assert!(monitor.want_lid_switch(true));
        assert!(!monitor.want_lid_switch(true));
        assert!(!monitor.lid_switch_held());
        let (fd, logind) = inhibitor();
        assert!(monitor.install_lid_switch_inhibitor(fd));
        assert!(monitor.lid_switch_held());
        assert!(!closed(&logind));

        // Turning the setting off hands the lid back to logind at once.
        assert!(monitor.want_lid_switch(false));
        assert!(!monitor.lid_switch_held());
        assert!(closed(&logind));
        assert!(!monitor.release_lid_switch_inhibitor());
    }

    #[test]
    fn an_inhibitor_logind_grants_after_the_setting_went_off_is_dropped() {
        let monitor = SleepMonitorShared::new().unwrap();
        monitor.want_lid_switch(true);
        // The monitor asked logind; the setting went off before the answer.
        monitor.want_lid_switch(false);
        let (fd, logind) = inhibitor();
        assert!(!monitor.install_lid_switch_inhibitor(fd));
        assert!(closed(&logind));
        assert!(!monitor.lid_switch_held());
    }

    #[test]
    fn stopping_hands_the_lid_back_to_logind() {
        let monitor = SleepMonitorShared::new().unwrap();
        monitor.want_lid_switch(true);
        let (fd, logind) = inhibitor();
        assert!(monitor.install_lid_switch_inhibitor(fd));
        monitor.request_stop();
        assert!(closed(&logind));
        assert!(!monitor.lid_switch_held());
        // Nor is one granted during shutdown kept.
        let (fd, logind) = inhibitor();
        assert!(!monitor.install_lid_switch_inhibitor(fd));
        assert!(closed(&logind));
    }

    #[test]
    fn logind_lid_state_tracks_changes_and_clears_on_disconnect() {
        let monitor = SleepMonitorShared::new().unwrap();
        assert_eq!(monitor.logind_lid_closed(), None);
        assert_eq!(monitor.take_logind_lid_closed(), None);

        monitor.set_logind_lid_closed(Some(true));
        assert_eq!(monitor.logind_lid_closed(), Some(true));
        assert_eq!(monitor.take_logind_lid_closed(), Some(true));
        assert_eq!(monitor.take_logind_lid_closed(), None);

        // Repeated identical updates do not re-dirty the pending transition.
        monitor.set_logind_lid_closed(Some(true));
        assert_eq!(monitor.take_logind_lid_closed(), None);

        monitor.set_logind_lid_closed(Some(false));
        assert_eq!(monitor.logind_lid_closed(), Some(false));
        assert_eq!(monitor.take_logind_lid_closed(), Some(false));

        monitor.set_logind_lid_closed(None);
        assert_eq!(monitor.logind_lid_closed(), None);
        assert_eq!(monitor.take_logind_lid_closed(), None);
    }

    #[test]
    fn a_change_of_the_wanted_lid_switch_wakes_the_monitor() {
        let monitor = SleepMonitorShared::new().unwrap();
        let woken = |monitor: &SleepMonitorShared| {
            futures_lite::future::block_on(futures_lite::future::or(
                async {
                    monitor.lid_switch_wake.wait().await;
                    true
                },
                async { false },
            ))
        };
        assert!(!woken(&monitor));
        monitor.want_lid_switch(true);
        assert!(woken(&monitor));
        assert!(!woken(&monitor));
        // Asking again for what is already wanted is no change.
        monitor.want_lid_switch(true);
        assert!(!woken(&monitor));
        monitor.want_lid_switch(false);
        assert!(woken(&monitor));
    }
}
