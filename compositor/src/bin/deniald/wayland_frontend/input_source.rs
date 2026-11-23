//! Libinput event source: every queued event, with an explicit end-of-batch
//! edge.
//!
//! libinput queues most events while it reads its file descriptor, which is
//! readable then. A few calls queue events with nothing to read:
//! `udev_assign_seat` and `resume` enumerate the seat and queue a
//! DEVICE_ADDED event for every device, `suspend` a DEVICE_REMOVED event.
//! The descriptor stays quiet after them, so a source that waits for it
//! leaves those events queued until unrelated input or a udev event arrives;
//! after a session restart the touchscreen, the keyboard and the touchpad
//! stayed dead until then. Weston and wlroots drain the queue right after
//! such a call. Here, calloop asks the source before every sleep, and the
//! source takes a turn whenever libinput's queue holds an event: no backlog
//! waits for the descriptor, and an empty queue costs one look at it.
//!
//! Smithay's `LibinputInputBackend` acts only for its own calloop token,
//! which it keeps private, so a turn the source asks for could not reach it.
//! This source therefore owns the libinput context and turns libinput's
//! events into Smithay's input events as Smithay does.
//!
//! The source hands the compositor every event of one turn and then a final
//! edge, so Denial flushes Wayland clients once after the whole batch without
//! adding a timer, wakeup fd, or allocation to the input path.

use std::io;
use std::os::fd::{AsFd, BorrowedFd};
#[cfg(feature = "flutter")]
use std::{
    cell::RefCell,
    collections::HashSet,
    os::fd::OwnedFd,
    path::{Path, PathBuf},
    rc::Rc,
};

use smithay::backend::input::InputEvent;
use smithay::backend::libinput::{LibinputInputBackend, PointerScrollAxis};
#[cfg(feature = "flutter")]
use smithay::backend::session::Session;
#[cfg(feature = "flutter")]
use smithay::backend::session::libseat::LibSeatSession;
use smithay::reexports::calloop::{
    self, EventSource, Interest, Mode, Poll, PostAction, Readiness, Token, TokenFactory,
};
#[cfg(feature = "flutter")]
use smithay::reexports::calloop::{LoopHandle, generic::Generic};
use smithay::reexports::input::event::{
    DeviceEvent, EventTrait, GestureEvent, KeyboardEvent, PointerEvent, SwitchEvent,
    TabletToolEvent, TouchEvent,
    gesture::{GestureHoldEvent, GesturePinchEvent, GestureSwipeEvent},
};
use smithay::reexports::input::{self as libinput, AsRaw, Libinput, ffi as libinput_ffi};
#[cfg(feature = "flutter")]
use smithay::reexports::rustix::{fs::OFlags, io as rustix_io};
use tracing::info;
#[cfg(feature = "flutter")]
use tracing::{debug, warn};

#[cfg(feature = "flutter")]
use super::super::RuntimeState;

pub(super) enum InputBatchEvent<E = InputEvent<LibinputInputBackend>> {
    Input(E),
    Complete,
}

#[derive(Default)]
pub(super) struct InputBatchMetadata {
    pub(super) flush_clients: bool,
}

/// An input queue as the batch source drives it: libinput's, or a test's.
pub(super) trait InputQueue: AsFd {
    type Event;

    /// Reads the descriptor into the queue, as `libinput_dispatch` does.
    fn read(&mut self) -> io::Result<()>;

    /// Whether an event waits in the queue; takes none.
    fn has_queued_events(&self) -> bool;

    /// The next queued event the compositor handles. Events it does not
    /// handle leave the queue too.
    fn next_event(&mut self) -> Option<Self::Event>;
}

/// libinput's context as an input queue of Smithay's input events.
pub(super) struct LibinputQueue(Libinput);

impl AsFd for LibinputQueue {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.0.as_fd()
    }
}

impl InputQueue for LibinputQueue {
    type Event = InputEvent<LibinputInputBackend>;

    fn read(&mut self) -> io::Result<()> {
        self.0.dispatch()
    }

    fn has_queued_events(&self) -> bool {
        // SAFETY: the context outlives this borrow, and the call only looks at
        // the type of the first queued event; it takes none and reads nothing.
        let next = unsafe { libinput_ffi::libinput_next_event_type(self.0.as_raw_mut()) };
        next != libinput_ffi::libinput_event_type_LIBINPUT_EVENT_NONE
    }

    fn next_event(&mut self) -> Option<Self::Event> {
        self.0.find_map(smithay_input_event)
    }
}

/// libinput's event as Smithay's `LibinputInputBackend` hands it over, or
/// none for the events Smithay leaves out.
fn smithay_input_event(event: libinput::Event) -> Option<InputEvent<LibinputInputBackend>> {
    Some(match event {
        libinput::Event::Device(DeviceEvent::Added(event)) => {
            let device = EventTrait::device(&event);
            info!("New device {:?}", device.sysname());
            InputEvent::DeviceAdded { device }
        }
        libinput::Event::Device(DeviceEvent::Removed(event)) => {
            let device = EventTrait::device(&event);
            info!("Removed device {:?}", device.sysname());
            InputEvent::DeviceRemoved { device }
        }
        libinput::Event::Touch(TouchEvent::Down(event)) => InputEvent::TouchDown { event },
        libinput::Event::Touch(TouchEvent::Motion(event)) => InputEvent::TouchMotion { event },
        libinput::Event::Touch(TouchEvent::Up(event)) => InputEvent::TouchUp { event },
        libinput::Event::Touch(TouchEvent::Cancel(event)) => InputEvent::TouchCancel { event },
        libinput::Event::Touch(TouchEvent::Frame(event)) => InputEvent::TouchFrame { event },
        libinput::Event::Keyboard(KeyboardEvent::Key(event)) => InputEvent::Keyboard { event },
        libinput::Event::Pointer(PointerEvent::Motion(event)) => {
            InputEvent::PointerMotion { event }
        }
        libinput::Event::Pointer(PointerEvent::MotionAbsolute(event)) => {
            InputEvent::PointerMotionAbsolute { event }
        }
        libinput::Event::Pointer(PointerEvent::ScrollWheel(event)) => InputEvent::PointerAxis {
            event: PointerScrollAxis::Wheel(event),
        },
        libinput::Event::Pointer(PointerEvent::ScrollFinger(event)) => InputEvent::PointerAxis {
            event: PointerScrollAxis::Finger(event),
        },
        libinput::Event::Pointer(PointerEvent::ScrollContinuous(event)) => {
            InputEvent::PointerAxis {
                event: PointerScrollAxis::Continuous(event),
            }
        }
        libinput::Event::Pointer(PointerEvent::Button(event)) => {
            InputEvent::PointerButton { event }
        }
        libinput::Event::Gesture(GestureEvent::Swipe(GestureSwipeEvent::Begin(event))) => {
            InputEvent::GestureSwipeBegin { event }
        }
        libinput::Event::Gesture(GestureEvent::Swipe(GestureSwipeEvent::Update(event))) => {
            InputEvent::GestureSwipeUpdate { event }
        }
        libinput::Event::Gesture(GestureEvent::Swipe(GestureSwipeEvent::End(event))) => {
            InputEvent::GestureSwipeEnd { event }
        }
        libinput::Event::Gesture(GestureEvent::Pinch(GesturePinchEvent::Begin(event))) => {
            InputEvent::GesturePinchBegin { event }
        }
        libinput::Event::Gesture(GestureEvent::Pinch(GesturePinchEvent::Update(event))) => {
            InputEvent::GesturePinchUpdate { event }
        }
        libinput::Event::Gesture(GestureEvent::Pinch(GesturePinchEvent::End(event))) => {
            InputEvent::GesturePinchEnd { event }
        }
        libinput::Event::Gesture(GestureEvent::Hold(GestureHoldEvent::Begin(event))) => {
            InputEvent::GestureHoldBegin { event }
        }
        libinput::Event::Gesture(GestureEvent::Hold(GestureHoldEvent::End(event))) => {
            InputEvent::GestureHoldEnd { event }
        }
        libinput::Event::Tablet(TabletToolEvent::Axis(event)) => {
            InputEvent::TabletToolAxis { event }
        }
        libinput::Event::Tablet(TabletToolEvent::Proximity(event)) => {
            InputEvent::TabletToolProximity { event }
        }
        libinput::Event::Tablet(TabletToolEvent::Tip(event)) => InputEvent::TabletToolTip { event },
        libinput::Event::Tablet(TabletToolEvent::Button(event)) => {
            InputEvent::TabletToolButton { event }
        }
        libinput::Event::Switch(SwitchEvent::Toggle(event)) => InputEvent::SwitchToggle { event },
        _ => return None,
    })
}

/// The libinput event source the compositor's loop runs.
pub(super) struct LibinputBatchSource<Q: InputQueue = LibinputQueue> {
    queue: Q,
    token: Option<Token>,
}

impl LibinputBatchSource {
    pub(super) fn new(context: Libinput) -> Self {
        Self::with_queue(LibinputQueue(context))
    }
}

impl<Q: InputQueue> LibinputBatchSource<Q> {
    fn with_queue(queue: Q) -> Self {
        Self { queue, token: None }
    }
}

/// The turn the source asks calloop for before it sleeps: one, while
/// events wait in the queue.
fn backlog_turn(token: Option<Token>, queued: bool) -> Option<(Readiness, Token)> {
    token
        .filter(|_| queued)
        .map(|token| (Readiness::EMPTY, token))
}

impl<Q: InputQueue> EventSource for LibinputBatchSource<Q> {
    type Event = InputBatchEvent<Q::Event>;
    type Metadata = InputBatchMetadata;
    type Ret = ();
    type Error = io::Error;

    const NEEDS_EXTRA_LIFECYCLE_EVENTS: bool = true;

    fn process_events<F>(
        &mut self,
        _: Readiness,
        token: Token,
        mut callback: F,
    ) -> Result<PostAction, Self::Error>
    where
        F: FnMut(Self::Event, &mut Self::Metadata) -> Self::Ret,
    {
        if self.token != Some(token) {
            return Ok(PostAction::Continue);
        }
        self.queue.read()?;
        let mut dispatched = false;
        let mut metadata = InputBatchMetadata::default();
        while let Some(event) = self.queue.next_event() {
            dispatched = true;
            callback(InputBatchEvent::Input(event), &mut metadata);
        }
        if dispatched {
            callback(InputBatchEvent::Complete, &mut metadata);
        }
        Ok(PostAction::Continue)
    }

    fn register(
        &mut self,
        poll: &mut Poll,
        token_factory: &mut TokenFactory,
    ) -> calloop::Result<()> {
        let token = token_factory.token();
        self.token = Some(token);
        // SAFETY: the source owns the queue and with it the descriptor, and
        // calloop unregisters a source before dropping it.
        unsafe { poll.register(self.queue.as_fd(), Interest::READ, Mode::Level, token) }
    }

    fn reregister(
        &mut self,
        poll: &mut Poll,
        token_factory: &mut TokenFactory,
    ) -> calloop::Result<()> {
        let token = token_factory.token();
        self.token = Some(token);
        poll.reregister(self.queue.as_fd(), Interest::READ, Mode::Level, token)
    }

    fn unregister(&mut self, poll: &mut Poll) -> calloop::Result<()> {
        self.token = None;
        poll.unregister(self.queue.as_fd())
    }

    fn before_sleep(&mut self) -> calloop::Result<Option<(Readiness, Token)>> {
        Ok(backlog_turn(self.token, self.queue.has_queued_events()))
    }
}

#[cfg(feature = "flutter")]
const JOYSTICK_EVENT_BYTES: usize = 8;
#[cfg(feature = "flutter")]
const JOYSTICK_AXIS_ACTIVITY_THRESHOLD: i32 = 512;
#[cfg(feature = "flutter")]
const JS_EVENT_BUTTON: u8 = 0x01;
#[cfg(feature = "flutter")]
const JS_EVENT_AXIS: u8 = 0x02;
#[cfg(feature = "flutter")]
const JS_EVENT_INIT: u8 = 0x80;

/// libinput deliberately excludes gamepads. Keep a read-only watch on Linux's
/// joystick character devices so gamepad buttons and meaningful axis motion
/// participate in the same compositor-owned idle clock. `input_hotplug` runs
/// the returned scan.
#[cfg(feature = "flutter")]
pub(super) fn joystick_scan(
    handle: &LoopHandle<'static, RuntimeState>,
    session: LibSeatSession,
) -> Box<dyn FnMut()> {
    let watched = Rc::new(RefCell::new(HashSet::new()));
    let handle = handle.clone();
    Box::new(move || scan_joysticks(&handle, &session, &watched))
}

#[cfg(feature = "flutter")]
fn scan_joysticks(
    handle: &LoopHandle<'static, RuntimeState>,
    session: &LibSeatSession,
    watched: &Rc<RefCell<HashSet<PathBuf>>>,
) {
    let Ok(entries) = std::fs::read_dir("/dev/input") else {
        return;
    };
    for path in entries.flatten().filter_map(|entry| {
        let name = entry.file_name();
        let name = name.to_str()?;
        name.strip_prefix("js")
            .is_some_and(|suffix| {
                !suffix.is_empty() && suffix.bytes().all(|byte| byte.is_ascii_digit())
            })
            .then(|| entry.path())
    }) {
        if watched.borrow().contains(&path) {
            continue;
        }
        if let Err(error) = watch_joystick(handle, session.clone(), watched.clone(), path.clone()) {
            debug!(%error, device = %path.display(), "could not watch joystick for idle activity");
        }
    }
}

#[cfg(feature = "flutter")]
fn watch_joystick(
    handle: &LoopHandle<'static, RuntimeState>,
    mut session: LibSeatSession,
    watched: Rc<RefCell<HashSet<PathBuf>>>,
    path: PathBuf,
) -> Result<(), Box<dyn std::error::Error>> {
    let fd = session.open(
        Path::new(&path),
        OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NONBLOCK,
    )?;
    watched.borrow_mut().insert(path.clone());
    let device = SeatJoystickFd {
        fd: Some(fd),
        session,
        path,
        watched,
        axes: RefCell::new(JoystickAxes::default()),
    };
    handle.insert_source(
        Generic::new(device, Interest::READ, Mode::Level),
        |_, device, state| {
            let mut buffer = [0u8; JOYSTICK_EVENT_BYTES * 64];
            let mut activity = false;
            loop {
                match rustix_io::read(device.as_fd(), &mut buffer) {
                    Ok(0) => return Ok(PostAction::Remove),
                    Ok(read) => {
                        activity |= joystick_events_have_activity(
                            &buffer[..read],
                            &mut device.as_ref().axes.borrow_mut(),
                        );
                    }
                    Err(rustix_io::Errno::AGAIN) => break,
                    Err(error) => {
                        warn!(%error, "joystick idle-activity source stopped");
                        return Ok(PostAction::Remove);
                    }
                }
            }
            if activity {
                state.note_user_activity();
            }
            Ok(PostAction::Continue)
        },
    )?;
    Ok(())
}

#[cfg(feature = "flutter")]
struct SeatJoystickFd {
    fd: Option<OwnedFd>,
    session: LibSeatSession,
    path: PathBuf,
    watched: Rc<RefCell<HashSet<PathBuf>>>,
    axes: RefCell<JoystickAxes>,
}

#[cfg(feature = "flutter")]
impl AsFd for SeatJoystickFd {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.fd
            .as_ref()
            .expect("joystick fd is unavailable before drop")
            .as_fd()
    }
}

#[cfg(feature = "flutter")]
impl Drop for SeatJoystickFd {
    fn drop(&mut self) {
        self.watched.borrow_mut().remove(&self.path);
        if let Some(fd) = self.fd.take()
            && let Err(error) = self.session.close(fd)
        {
            debug!(%error, device = %self.path.display(), "could not close joystick seat device");
        }
    }
}

#[cfg(feature = "flutter")]
struct JoystickAxes {
    values: [i16; 256],
    known: [bool; 256],
}

#[cfg(feature = "flutter")]
impl Default for JoystickAxes {
    fn default() -> Self {
        Self {
            values: [0; 256],
            known: [false; 256],
        }
    }
}

#[cfg(feature = "flutter")]
fn joystick_events_have_activity(bytes: &[u8], axes: &mut JoystickAxes) -> bool {
    let mut activity = false;
    for event in bytes.as_chunks::<JOYSTICK_EVENT_BYTES>().0 {
        let value = i16::from_ne_bytes([event[4], event[5]]);
        let kind = event[6];
        let axis = usize::from(event[7]);
        let initial = kind & JS_EVENT_INIT != 0;
        match kind & !JS_EVENT_INIT {
            JS_EVENT_BUTTON if !initial => activity = true,
            JS_EVENT_AXIS => {
                if initial {
                    axes.values[axis] = value;
                    axes.known[axis] = true;
                } else if !axes.known[axis] {
                    axes.values[axis] = value;
                    axes.known[axis] = true;
                    activity = true;
                } else if i32::from(value).abs_diff(i32::from(axes.values[axis]))
                    >= JOYSTICK_AXIS_ACTIVITY_THRESHOLD as u32
                {
                    axes.values[axis] = value;
                    activity = true;
                }
            }
            _ => {}
        }
    }
    activity
}

#[cfg(test)]
mod tests {
    use std::cell::{Cell, RefCell};
    use std::collections::VecDeque;
    use std::io::{self, Read, Write};
    use std::os::fd::{AsFd, BorrowedFd, OwnedFd};
    use std::os::unix::net::UnixStream;
    use std::path::Path;
    use std::rc::Rc;
    use std::time::{Duration, Instant};

    use smithay::reexports::calloop::EventLoop;
    use smithay::reexports::input::{Libinput, LibinputInterface};
    use smithay::reexports::rustix::io::Errno;

    use super::{InputBatchEvent, InputQueue, LibinputBatchSource, LibinputQueue};

    /// A queue the test fills as libinput fills its own: directly, as
    /// `udev_assign_seat` and `resume` do, or when the descriptor is read.
    struct ScriptedQueue {
        descriptor: UnixStream,
        queued: Rc<RefCell<VecDeque<u32>>>,
        queued_on_read: Rc<RefCell<VecDeque<u32>>>,
        reads: Rc<Cell<usize>>,
    }

    impl AsFd for ScriptedQueue {
        fn as_fd(&self) -> BorrowedFd<'_> {
            self.descriptor.as_fd()
        }
    }

    impl InputQueue for ScriptedQueue {
        type Event = u32;

        fn read(&mut self) -> io::Result<()> {
            self.reads.set(self.reads.get() + 1);
            let mut buffer = [0; 16];
            loop {
                match self.descriptor.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(_) => {}
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => break,
                    Err(error) => return Err(error),
                }
            }
            let mut arrived = self.queued_on_read.borrow_mut();
            self.queued.borrow_mut().extend(arrived.drain(..));
            Ok(())
        }

        fn has_queued_events(&self) -> bool {
            !self.queued.borrow().is_empty()
        }

        fn next_event(&mut self) -> Option<u32> {
            self.queued.borrow_mut().pop_front()
        }
    }

    #[derive(Debug, PartialEq)]
    enum Delivered {
        Event(u32),
        Complete,
    }

    /// The test's side of the scripted queue. The peer keeps the descriptor
    /// open and quiet until the test writes to it.
    struct Script {
        peer: UnixStream,
        queued: Rc<RefCell<VecDeque<u32>>>,
        queued_on_read: Rc<RefCell<VecDeque<u32>>>,
        reads: Rc<Cell<usize>>,
    }

    fn running_source(backlog: &[u32]) -> (EventLoop<'static, Vec<Delivered>>, Script) {
        let (descriptor, peer) = UnixStream::pair().expect("socket pair");
        descriptor
            .set_nonblocking(true)
            .expect("non-blocking descriptor");
        let script = Script {
            peer,
            queued: Rc::new(RefCell::new(backlog.iter().copied().collect())),
            queued_on_read: Rc::default(),
            reads: Rc::default(),
        };
        let source = LibinputBatchSource::with_queue(ScriptedQueue {
            descriptor,
            queued: Rc::clone(&script.queued),
            queued_on_read: Rc::clone(&script.queued_on_read),
            reads: Rc::clone(&script.reads),
        });
        let event_loop = EventLoop::try_new().expect("event loop");
        event_loop
            .handle()
            .insert_source(source, |event, _, delivered: &mut Vec<Delivered>| {
                delivered.push(match event {
                    InputBatchEvent::Input(event) => Delivered::Event(event),
                    InputBatchEvent::Complete => Delivered::Complete,
                });
            })
            .expect("insert the input source");
        (event_loop, script)
    }

    const LONG_WAIT: Duration = Duration::from_secs(5);

    #[test]
    fn devices_queued_before_the_loop_runs_arrive_without_descriptor_activity() {
        let (mut event_loop, script) = running_source(&[1, 2, 3]);
        let mut delivered = Vec::new();
        let started = Instant::now();
        event_loop
            .dispatch(Some(LONG_WAIT), &mut delivered)
            .expect("dispatch");
        assert_eq!(
            delivered,
            [
                Delivered::Event(1),
                Delivered::Event(2),
                Delivered::Event(3),
                Delivered::Complete,
            ]
        );
        assert_eq!(script.reads.get(), 1);
        assert!(
            started.elapsed() < LONG_WAIT,
            "the loop slept on its backlog"
        );
    }

    #[test]
    fn devices_queued_by_a_resume_arrive_in_the_next_turn() {
        let (mut event_loop, script) = running_source(&[]);
        let mut delivered = Vec::new();
        event_loop
            .dispatch(Some(Duration::ZERO), &mut delivered)
            .expect("dispatch");
        assert!(delivered.is_empty());

        script.queued.borrow_mut().extend([7, 8]);
        event_loop
            .dispatch(Some(LONG_WAIT), &mut delivered)
            .expect("dispatch");
        assert_eq!(
            delivered,
            [
                Delivered::Event(7),
                Delivered::Event(8),
                Delivered::Complete
            ]
        );
    }

    #[test]
    fn an_empty_queue_lets_the_loop_sleep() {
        let (mut event_loop, script) = running_source(&[]);
        let mut delivered = Vec::new();
        let started = Instant::now();
        event_loop
            .dispatch(Some(Duration::from_millis(40)), &mut delivered)
            .expect("dispatch");
        assert!(started.elapsed() >= Duration::from_millis(30));
        assert!(delivered.is_empty());
        assert_eq!(
            script.reads.get(),
            0,
            "the source took a turn with nothing queued"
        );
    }

    #[test]
    fn a_readable_descriptor_still_drives_the_queue() {
        let (mut event_loop, mut script) = running_source(&[]);
        script.queued_on_read.borrow_mut().push_back(5);
        script
            .peer
            .write_all(b"x")
            .expect("make the descriptor readable");
        let mut delivered = Vec::new();
        event_loop
            .dispatch(Some(LONG_WAIT), &mut delivered)
            .expect("dispatch");
        assert_eq!(delivered, [Delivered::Event(5), Delivered::Complete]);

        delivered.clear();
        event_loop
            .dispatch(Some(Duration::ZERO), &mut delivered)
            .expect("dispatch");
        assert!(delivered.is_empty());
        assert_eq!(script.reads.get(), 1);
    }

    #[test]
    fn a_turn_without_events_has_no_batch_edge() {
        let (mut event_loop, mut script) = running_source(&[]);
        script
            .peer
            .write_all(b"x")
            .expect("make the descriptor readable");
        let mut delivered = Vec::new();
        event_loop
            .dispatch(Some(LONG_WAIT), &mut delivered)
            .expect("dispatch");
        assert!(delivered.is_empty());
        assert_eq!(script.reads.get(), 1);
    }

    struct NoDevices;

    impl LibinputInterface for NoDevices {
        fn open_restricted(&mut self, _: &Path, _: i32) -> Result<OwnedFd, i32> {
            Err(Errno::NODEV.raw_os_error())
        }

        fn close_restricted(&mut self, _: OwnedFd) {}
    }

    #[test]
    fn libinput_queue_sees_an_empty_queue() {
        let mut queue = LibinputQueue(Libinput::new_from_path(NoDevices));
        assert!(!queue.has_queued_events());
        queue.read().expect("read libinput's descriptor");
        assert!(!queue.has_queued_events());
        assert!(queue.next_event().is_none());
    }
}
