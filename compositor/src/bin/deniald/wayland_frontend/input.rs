use std::collections::HashSet;
use std::error::Error;
use std::ffi::OsStr;

use denial_core::topology::OutputTransform;
use smithay::backend::input::{
    AbsolutePositionEvent, Axis, AxisSource, ButtonState, Device, DeviceCapability, Event,
    GestureBeginEvent, GestureEndEvent, GestureSwipeUpdateEvent, InputEvent, InputTime, KeyState,
    KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent, PointerMotionEvent, TouchEvent,
};
#[cfg(feature = "flutter")]
use smithay::backend::input::{Switch, SwitchState, SwitchToggleEvent};
use smithay::backend::libinput::{LibinputInputBackend, LibinputSessionInterface};
use smithay::backend::session::Session;
use smithay::backend::session::libseat::LibSeatSession;
#[cfg(feature = "flutter")]
use smithay::desktop::{WindowSurfaceType, utils::under_from_surface_tree};
use smithay::input::keyboard::{FilterResult, KeyboardHandle, Keycode};
#[cfg(feature = "flutter")]
use smithay::input::keyboard::{KeyboardSource, XkbConfig, xkb};
use smithay::input::pointer::{
    AxisFrame, ButtonEvent, MotionEvent, PointerHandle, RelativeMotionEvent,
};
#[cfg(feature = "flutter")]
use smithay::input::pointer::{CursorImageStatus, Focus, GrabStartData};
use smithay::input::touch::{DownEvent, MotionEvent as TouchMotionEvent, UpEvent};
use smithay::reexports::calloop::EventLoop;
#[cfg(feature = "flutter")]
use smithay::reexports::calloop::timer::{TimeoutAction, Timer};
use smithay::reexports::input::{
    AccelProfile, ClickMethod, ClickfingerButtonMap, Device as LibinputDevice, Libinput,
    TapButtonMap,
};
#[cfg(feature = "flutter")]
use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel;
#[cfg(feature = "flutter")]
use smithay::reexports::wayland_server::Resource;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
#[cfg(feature = "flutter")]
use smithay::utils::Serial;
use smithay::utils::{Logical, Point, Rectangle, SERIAL_COUNTER};
use smithay::wayland::pointer_constraints::{PointerConstraint, with_pointer_constraint};
use tracing::{info, warn};

#[cfg(feature = "flutter")]
use super::super::PendingWindowEvent;
#[cfg(feature = "flutter")]
use super::super::lid_switch;
use super::super::lifecycle::ShutdownReason;
#[cfg(feature = "flutter")]
use super::super::mac_keys;
#[cfg(feature = "flutter")]
use super::super::native_shortcut::AppSwitcherStep;
use super::super::native_shortcut::{
    ShortcutAction, ShortcutDisposition, ShortcutGesture, ShortcutTarget,
};
#[cfg(feature = "flutter")]
use super::super::settings::KeyboardSettings;
use super::super::settings::{MouseSettings, TouchpadClickMethod, TouchpadSettings};
#[cfg(feature = "flutter")]
use super::super::window_grab::{
    LocalFlutterWindowGrab, MoveSurfaceGrab, ResizeEdges, ResizeSurfaceGrab, TileMoveGrab,
    TileResizeGrab,
};
#[cfg(feature = "flutter")]
use super::super::window_layout::{LayoutDirection, LayoutResizeEdges};
#[cfg(feature = "flutter")]
use super::super::wire::{
    InputLayoutSnapshot, InputWindowRegion, WindowPlacementChange, WindowPlacementPhase,
};
use super::super::{RuntimeState, logical_axis_scroll_delta};
use super::ClientSurface;
#[cfg(feature = "flutter")]
use super::FlutterPointerPress;
use super::WaylandFrontend;
use super::input_source::{InputBatchEvent, LibinputBatchSource};
#[cfg(feature = "flutter")]
use super::touch_gestures::{
    self, TouchGestureUpdate, TouchWindowTarget, WINDOW_TOUCH_CORNER_SIZE,
    WINDOW_TOUCH_STRIP_HEIGHT,
};
#[cfg(feature = "flutter")]
use denial_core::portal_protocol::DesktopPresentation;

#[path = "input/client_gestures.rs"]
mod client_gestures;
#[cfg(feature = "flutter")]
#[path = "input/edge_swipe.rs"]
pub(super) mod edge_swipe;
#[path = "input/flutter_route.rs"]
pub(super) mod flutter_route;
#[path = "input/tablet.rs"]
mod tablet;
#[path = "input/wayland_route.rs"]
mod wayland_route;

pub(super) use client_gestures::ClientGestures;
use client_gestures::{cancel_client_gesture, process_client_gesture};
#[cfg(feature = "flutter")]
use flutter_route::process_flutter_input_event;
#[cfg(feature = "flutter")]
use flutter_route::process_wayland_keyboard_transition_from;
#[cfg(feature = "flutter")]
pub(crate) use flutter_route::reconcile_flutter_pointer_route;
#[cfg(feature = "flutter")]
pub(super) use flutter_route::release_client_geometry_for_shell_grab;
use wayland_route::process_wayland_input_event;

/// Cancel the whole client sequence before retiring any of its surface routes.
/// wl_touch.cancel is client-wide, not a per-slot or per-surface event.
pub(super) fn cancel_touch_for_surface(state: &mut RuntimeState, surface: &WlSurface) -> bool {
    let frontend = state.frontend();
    let touch = frontend.seat.get_touch().expect("seat has no touch");
    let belongs_to_surface = |focus: &WlSurface| {
        let mut current = Some(focus.clone());
        while let Some(candidate) = current {
            if &candidate == surface {
                return true;
            }
            current = smithay::wayland::compositor::get_parent(&candidate);
        }
        #[cfg(feature = "flutter")]
        if frontend.owning_toplevel_surface(focus).as_ref() == Some(surface) {
            return true;
        }
        false
    };
    let affected = touch
        .with_grab(|_, grab| {
            grab.downcast_ref::<denial_core::touch_grab::TouchSessionGrab<RuntimeState>>()
                .and_then(|grab| grab.focus())
                .is_some_and(|focus| belongs_to_surface(focus))
        })
        .unwrap_or(false);
    #[cfg(feature = "flutter")]
    let affected = affected
        || frontend.client_touch_routes.values().any(|route| {
            belongs_to_surface(&route.surface) || route.layer_root.as_ref() == Some(surface)
        });
    if affected {
        touch.cancel(state);
        #[cfg(feature = "flutter")]
        {
            let frontend = state.frontend_mut();
            frontend.client_touch_routes.clear();
            frontend.client_touch_frame_pending = false;
        }
    }
    affected
}

pub(super) fn touch_output_for_device<'a>(
    frontend: &'a WaylandFrontend,
    device: &LibinputDevice,
) -> Option<&'a super::WaylandOutput> {
    if let Some(name) = device.output_name() {
        return frontend
            .outputs
            .iter()
            .find(|output| output.connector == name.as_ref());
    }
    frontend
        .outputs
        .iter()
        .find(|output| {
            ["DSI-", "eDP-", "LVDS-"]
                .iter()
                .any(|prefix| output.connector.starts_with(prefix))
        })
        .or_else(|| {
            frontend
                .outputs
                .iter()
                .find(|output| output.logical_geometry == frontend.touch_bounds)
        })
}

fn touch_device_mapping(
    frontend: &WaylandFrontend,
    device: &LibinputDevice,
) -> (Rectangle<i32, Logical>, OutputTransform) {
    touch_output_for_device(frontend, device)
        .map(|output| (output.logical_geometry, output.transform))
        .unwrap_or((frontend.touch_bounds, frontend.touch_transform))
}

fn output_bound_absolute_position<E>(
    event: &E,
    bounds: Rectangle<i32, Logical>,
    transform: OutputTransform,
) -> Point<f64, Logical>
where
    E: AbsolutePositionEvent<LibinputInputBackend>,
{
    project_touch_position(
        bounds,
        transform,
        event.x_transformed(1),
        event.y_transformed(1),
    )
}

fn project_touch_position(
    bounds: Rectangle<i32, Logical>,
    transform: OutputTransform,
    x: f64,
    y: f64,
) -> Point<f64, Logical> {
    let (x, y) = transform.native_to_logical(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    let left = f64::from(bounds.loc.x);
    let top = f64::from(bounds.loc.y);
    // Output bounds are half-open, including at transformed touch endpoints.
    Point::from((
        (left + x * f64::from(bounds.size.w))
            .clamp(left, (left + f64::from(bounds.size.w)).next_down()),
        (top + y * f64::from(bounds.size.h))
            .clamp(top, (top + f64::from(bounds.size.h)).next_down()),
    ))
}

#[cfg(test)]
mod absolute_touch_bounds_tests {
    use super::*;
    #[test]
    fn edge_contacts_remain_on_their_associated_output_after_rotation() {
        let bounds = Rectangle::new((-800, 150).into(), (800, 600).into());
        for transform in [
            OutputTransform::Normal,
            OutputTransform::Rotate90,
            OutputTransform::Rotate180,
            OutputTransform::Rotate270,
        ] {
            for (x, y) in [(0.0, 0.0), (1.0, 1.0), (0.0, 1.0), (1.0, 0.0)] {
                let position = project_touch_position(bounds, transform, x, y);
                assert!(position.x >= -800.0 && position.x < 0.0);
                assert!(position.y >= 150.0 && position.y < 750.0);
            }
        }
    }
}

#[cfg(feature = "flutter")]
const BTN_LEFT: u32 = 0x110;
#[cfg(feature = "flutter")]
const BTN_MIDDLE: u32 = 0x112;
#[cfg(feature = "flutter")]
const BTN_RIGHT: u32 = 0x111;
#[cfg(feature = "flutter")]
const MAX_CLIENT_POINTER_PRESSES: usize = 16;

#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct ShellKeyStroke {
    pub(super) evdev_keycode: u32,
    pub(super) shift: bool,
}

#[cfg(feature = "flutter")]
fn shell_text_key_stroke(character: char) -> Option<ShellKeyStroke> {
    let (evdev_keycode, shift) = match character {
        'a'..='z' => (
            [
                30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22,
                47, 17, 45, 21, 44,
            ][usize::from(character as u8 - b'a')],
            false,
        ),
        'A'..='Z' => (
            [
                30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22,
                47, 17, 45, 21, 44,
            ][usize::from(character as u8 - b'A')],
            true,
        ),
        '1' => (2, false),
        '2' => (3, false),
        '3' => (4, false),
        '4' => (5, false),
        '5' => (6, false),
        '6' => (7, false),
        '7' => (8, false),
        '8' => (9, false),
        '9' => (10, false),
        '0' => (11, false),
        '!' => (2, true),
        '@' => (3, true),
        '#' => (4, true),
        '$' => (5, true),
        '%' => (6, true),
        '^' => (7, true),
        '&' => (8, true),
        '*' => (9, true),
        '(' => (10, true),
        ')' => (11, true),
        '-' => (12, false),
        '_' => (12, true),
        '=' => (13, false),
        '+' => (13, true),
        '[' => (26, false),
        '{' => (26, true),
        ']' => (27, false),
        '}' => (27, true),
        ';' => (39, false),
        ':' => (39, true),
        '\'' => (40, false),
        '"' => (40, true),
        '`' => (41, false),
        '~' => (41, true),
        '\\' => (43, false),
        '|' => (43, true),
        ',' => (51, false),
        '<' => (51, true),
        '.' => (52, false),
        '>' => (52, true),
        '/' => (53, false),
        '?' => (53, true),
        ' ' => (57, false),
        _ => return None,
    };
    Some(ShellKeyStroke {
        evdev_keycode,
        shift,
    })
}

#[cfg(feature = "flutter")]
fn shell_named_key_stroke(key: &str) -> Option<ShellKeyStroke> {
    let (evdev_keycode, shift) = match key {
        "Escape" => (1, false),
        "Alt" => (56, false),
        "BackSpace" | "Backspace" => (14, false),
        "Tab" => (15, false),
        "Return" | "Enter" => (28, false),
        "space" | "Space" => (57, false),
        "Up" => (103, false),
        "Left" => (105, false),
        "Right" => (106, false),
        "Down" => (108, false),
        "Delete" => (111, false),
        "comma" => (51, false),
        "period" => (52, false),
        "slash" => (53, false),
        "backslash" => (43, false),
        "minus" => (12, false),
        "equal" => (13, false),
        "apostrophe" => (40, false),
        "semicolon" => (39, false),
        "colon" => (39, true),
        "bracketleft" => (26, false),
        "bracketright" => (27, false),
        value if value.chars().count() == 1 => shell_text_key_stroke(value.chars().next()?)
            .map(|stroke| (stroke.evdev_keycode, stroke.shift))?,
        _ => return None,
    };
    Some(ShellKeyStroke {
        evdev_keycode,
        shift,
    })
}

/// A key of the seat keymap that types one character of shell-keyboard
/// text, and the keymap layout it types the character in.
#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct PlannedShellStroke {
    pub(super) stroke: ShellKeyStroke,
    pub(super) layout: u32,
}

/// Finds the key of `keymap` that types `character` with no modifier or
/// with Shift alone, so that every client, Xwayland's included, reads it
/// from the keymap it already has: the key of [`shell_text_key_stroke`]
/// when the `active` layout types the character there, else another key of
/// the active layout, else a key of another layout in the keymap's order.
/// Keypad keys are left out: a terminal may turn them into escape
/// sequences. `None` when no layout types the character that way.
#[cfg(feature = "flutter")]
fn plan_shell_text_stroke(
    keymap: &xkb::Keymap,
    active: u32,
    character: char,
) -> Option<PlannedShellStroke> {
    const XKB_KEYCODE_OFFSET: u32 = 8;

    let shift_index = keymap.mod_get_index(xkb::MOD_NAME_SHIFT);
    let shift_mask = (shift_index != xkb::MOD_INVALID).then(|| 1 << shift_index);
    let types = |keycode: Keycode, layout: u32, shift: bool| {
        let wanted = if shift { shift_mask } else { Some(0) };
        let Some(wanted) = wanted else {
            return false;
        };
        let mut masks = [0; 16];
        (0..keymap.num_levels_for_key(keycode, layout)).any(|level| {
            let syms = keymap.key_get_syms_by_level(keycode, layout, level);
            if !syms
                .iter()
                .any(|sym| xkb::keysym_to_utf32(*sym) == u32::from(character))
            {
                return false;
            }
            let count = keymap.key_get_mods_for_level(keycode, layout, level, &mut masks);
            masks[..count.min(masks.len())].contains(&wanted)
        })
    };

    if let Some(stroke) = shell_text_key_stroke(character)
        && types(
            Keycode::new(stroke.evdev_keycode + XKB_KEYCODE_OFFSET),
            active,
            stroke.shift,
        )
    {
        return Some(PlannedShellStroke {
            stroke,
            layout: active,
        });
    }
    let first = keymap.min_keycode().raw().max(XKB_KEYCODE_OFFSET);
    let last = keymap.max_keycode().raw();
    let layouts =
        std::iter::once(active).chain((0..keymap.num_layouts()).filter(|&layout| layout != active));
    for layout in layouts {
        for shift in [false, true] {
            for raw in first..=last {
                let keycode = Keycode::new(raw);
                let keypad = (0..keymap.num_levels_for_key(keycode, layout)).any(|level| {
                    keymap
                        .key_get_syms_by_level(keycode, layout, level)
                        .iter()
                        .any(|sym| sym.is_keypad_key())
                });
                if !keypad && types(keycode, layout, shift) {
                    return Some(PlannedShellStroke {
                        stroke: ShellKeyStroke {
                            evdev_keycode: raw - XKB_KEYCODE_OFFSET,
                            shift,
                        },
                        layout,
                    });
                }
            }
        }
    }
    None
}

/// Plans every character of `text` against the seat keymap as it is now.
#[cfg(feature = "flutter")]
fn plan_shell_text(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    text: &str,
) -> Vec<(char, Option<PlannedShellStroke>)> {
    keyboard.with_xkb_state(state, |context| {
        let xkb = context.xkb().lock().unwrap();
        let active = xkb.active_layout().0;
        // SAFETY: the keymap reference is used only while the owning XKB
        // mutex is held and is not retained beyond this call.
        let keymap = unsafe { xkb.keymap() };
        text.chars()
            .map(|character| (character, plan_shell_text_stroke(keymap, active, character)))
            .collect()
    })
}

/// Types one planned key. A key of another layout types with that layout
/// locked around it, as a layout switch reaches clients, and the active
/// layout back after it; the shell is not told of the passing switch.
#[cfg(feature = "flutter")]
fn inject_planned_shell_stroke(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    planned: PlannedShellStroke,
    time: InputTime,
) -> bool {
    let active = keyboard.with_xkb_state(state, |context| {
        context.xkb().lock().unwrap().active_layout().0
    });
    if planned.layout == active {
        return inject_shell_key_stroke(state, keyboard, planned.stroke, false, time);
    }
    state.frontend_mut().shell_keyboard_borrows_layout = true;
    keyboard.with_xkb_state(state, |mut context| {
        context.set_layout(smithay::input::keyboard::Layout(planned.layout));
    });
    let delivered = inject_shell_key_stroke(state, keyboard, planned.stroke, false, time);
    keyboard.with_xkb_state(state, |mut context| {
        context.set_layout(smithay::input::keyboard::Layout(active));
    });
    state.frontend_mut().shell_keyboard_borrows_layout = false;
    delivered
}

/// Types characters that no layout of the seat keymap has. Smithay hands
/// the focused client a keymap of just these keysyms for the strokes and
/// then the seat keymap again, which reaches clients without text-input,
/// Xwayland's among them. Only a client window takes them: not the shell,
/// which reads text from the seat keymap, and not a locked session.
#[cfg(feature = "flutter")]
fn inject_unplanned_shell_text(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    characters: &mut Vec<char>,
) -> bool {
    if characters.is_empty() {
        return false;
    }
    let characters = std::mem::take(characters);
    let client = keyboard
        .current_focus()
        .is_some_and(|focus| !matches!(focus, super::focus::KeyboardFocusTarget::Flutter));
    if !client || state.secure_session_locked() {
        warn!(
            count = characters.len(),
            "ignored characters the keymap lacks without a client window to take them"
        );
        return false;
    }
    let keysyms = characters
        .iter()
        .map(|character| xkb::utf32_to_keysym(u32::from(*character)))
        .filter(|keysym| keysym.raw() != xkb::keysyms::KEY_NoSymbol)
        .collect::<Vec<_>>();
    if keysyms.is_empty() {
        return false;
    }
    keyboard.inject_text_keysyms(state, &keysyms);
    true
}

/// Whether `text` types on the keys a US keyboard has it on, in the active
/// layout: as every client reads keys, also one that reads only keycodes
/// through a US map of its own, as Droidloom's Android apps do.
#[cfg(feature = "flutter")]
fn types_on_us_keys(active: u32, planned: &[(char, Option<PlannedShellStroke>)]) -> bool {
    planned.iter().all(|(character, planned)| {
        planned.is_some_and(|planned| {
            planned.layout == active && Some(planned.stroke) == shell_text_key_stroke(*character)
        })
    })
}

/// Shell-keyboard text. On the keys a US keyboard has it on, in the active
/// layout, it is typed: the keyboard as it always was. Anything else, a
/// letter of another layout or a mark another layout moves, goes to a
/// focused editor whole, as an input method's commit; with no editor
/// speaking text-input, Xwayland's clients and terminals among them, it is
/// typed on the keymap's keys in whichever layout has them, and the rest
/// with keysyms of its own.
#[cfg(feature = "flutter")]
fn type_or_commit_shell_text(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    text: &str,
    time: InputTime,
) -> bool {
    let planned = plan_shell_text(state, keyboard, text);
    let active = keyboard.with_xkb_state(state, |context| {
        context.xkb().lock().unwrap().active_layout().0
    });
    if !types_on_us_keys(active, &planned) {
        let frontend = state.frontend_mut();
        if let Some(delivered) = frontend.commit_shell_keyboard_text(None, text) {
            return delivered;
        }
    }
    type_shell_text(state, keyboard, text, time)
}

#[cfg(feature = "flutter")]
fn inject_shell_key_stroke(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    stroke: ShellKeyStroke,
    ctrl: bool,
    time: InputTime,
) -> bool {
    const XKB_KEYCODE_OFFSET: u32 = 8;
    const LEFT_CTRL: u32 = 29;
    const LEFT_SHIFT: u32 = 42;

    let keycode = Keycode::new(stroke.evdev_keycode + XKB_KEYCODE_OFFSET);
    if keyboard.pressed_keys().contains(&keycode) {
        warn!(
            keycode = stroke.evdev_keycode,
            "ignored shell keyboard key already held by another input source"
        );
        return false;
    }

    let modifiers = keyboard.modifier_state();
    let inject_ctrl = ctrl && !modifiers.ctrl;
    let inject_shift = stroke.shift && !modifiers.shift;
    let ctrl_keycode = Keycode::new(LEFT_CTRL + XKB_KEYCODE_OFFSET);
    let shift_keycode = Keycode::new(LEFT_SHIFT + XKB_KEYCODE_OFFSET);
    let mut delivered = false;
    let mut send = |state: &mut RuntimeState, keycode: Keycode, key_state: KeyState| {
        delivered |= process_shell_keyboard_transition(state, keycode, key_state, time);
    };

    if inject_ctrl {
        send(state, ctrl_keycode, KeyState::Pressed);
    }
    if inject_shift {
        send(state, shift_keycode, KeyState::Pressed);
    }
    send(state, keycode, KeyState::Pressed);
    send(state, keycode, KeyState::Released);
    if inject_shift {
        send(state, shift_keycode, KeyState::Released);
    }
    if inject_ctrl {
        send(state, ctrl_keycode, KeyState::Released);
    }
    delivered
}

#[cfg(feature = "flutter")]
pub(super) fn inject_shell_key_transition(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    stroke: ShellKeyStroke,
    key_state: KeyState,
    time: InputTime,
) -> bool {
    const XKB_KEYCODE_OFFSET: u32 = 8;

    // Held modified keys require explicit modifier ownership. The OSK uses
    // this lifecycle for unmodified Backspace and to hold Alt around a key;
    // complete modified taps continue through inject_shell_key_stroke().
    if stroke.shift {
        return false;
    }
    let keycode = Keycode::new(stroke.evdev_keycode + XKB_KEYCODE_OFFSET);
    let seat_pressed = keyboard.pressed_keys().contains(&keycode);
    let accepted = {
        let frontend = state.frontend_mut();
        route_shell_key_transition(
            &mut frontend.shell_keyboard_keys,
            keycode.raw(),
            key_state,
            seat_pressed,
        )
    };
    accepted && process_shell_keyboard_transition(state, keycode, key_state, time)
}

/// Linux evdev `KEY_BACK`: a phone's hardware Back key. XKB names it
/// `XF86Back`, and Android, including Droidloom, maps it to `KEYCODE_BACK`.
#[cfg(feature = "flutter")]
const EVDEV_KEY_BACK: u32 = 158;

/// Delivers the system Back action to a client window as one Back key tap.
///
/// Browsers, GTK, Qt and Droidloom's Android tasks treat this key as
/// navigation back, so the action follows keyboard focus like Android's own
/// Back. A dialog of the same client that already holds the focus keeps it:
/// Back belongs to whatever the application presents on top.
#[cfg(feature = "flutter")]
pub(super) fn navigate_back(state: &mut RuntimeState, window: &smithay::desktop::Window) -> bool {
    let (keyboard, time, focused) = {
        let frontend = state.frontend();
        let keyboard = frontend.seat.get_keyboard().expect("seat has no keyboard");
        let client = frontend
            .window_root_surface(window)
            .and_then(|root| root.client())
            .map(|client| client.id());
        let focused = client.is_some()
            && keyboard.current_focus().is_some_and(|focus| {
                smithay::wayland::seat::WaylandFocus::wl_surface(&focus)
                    .and_then(|surface| surface.client())
                    .map(|client| client.id())
                    == client
            });
        (keyboard, InputTime::now(), focused)
    };
    if !focused
        && !super::window_management::activate_window(state, window, SERIAL_COUNTER.next_serial())
    {
        warn!("ignored Back for a window that cannot take keyboard focus");
        return false;
    }
    inject_shell_key_stroke(
        state,
        &keyboard,
        ShellKeyStroke {
            evdev_keycode: EVDEV_KEY_BACK,
            shift: false,
        },
        false,
        time,
    )
}

#[cfg(feature = "flutter")]
/// Turn one shell-keyboard intent into complete virtual key lifecycles.
///
/// These transitions enter the same focus, XKB, shortcut, Flutter and Wayland
/// router as libinput keyboard events. The software keyboard is an input
/// source; only text off the keys a US keyboard has it on, in the active
/// layout, and replacements of the word before the cursor, go to the
/// focused editor as input-method commits.
pub(crate) fn dispatch_shell_keyboard(
    state: &mut RuntimeState,
    command: &super::super::wire::KeyboardCommand,
) -> bool {
    let (keyboard, time) = {
        let frontend = state.frontend();
        (
            frontend.seat.get_keyboard().expect("seat has no keyboard"),
            InputTime::now(),
        )
    };
    // Do not gate the shared router on a focused Wayland surface. Flutter is a
    // first-class seat focus target, so software and physical keyboards both
    // use process_keyboard_transition() and the same seat dispatch.
    match command {
        super::super::wire::KeyboardCommand::DismissPanel { activation_serial } => {
            let frontend = state.frontend_mut();
            frontend.text_input.dismiss_panel(*activation_serial);
            true
        }
        super::super::wire::KeyboardCommand::PanelMotion {
            height,
            duration_ms,
        } => {
            let frontend = state.frontend_mut();
            frontend.set_keyboard_height(*height, *duration_ms);
            true
        }
        super::super::wire::KeyboardCommand::Text(text) => {
            type_or_commit_shell_text(state, &keyboard, text, time)
        }
        super::super::wire::KeyboardCommand::SelectLayout { layout } => {
            select_keyboard_layout(state, *layout)
        }
        super::super::wire::KeyboardCommand::TypingLayouts(layouts) => {
            set_shell_typing_layouts(state, layouts)
        }
        super::super::wire::KeyboardCommand::Replace { replaced, text } => {
            let frontend = state.frontend_mut();
            match frontend.commit_shell_keyboard_text(Some(replaced), text) {
                Some(true) => true,
                Some(false) => {
                    tracing::debug!("kept the typed word: the cursor left it");
                    false
                }
                None => {
                    // No text-input: erase the word with keys and retype it.
                    let Some(backspace) = shell_named_key_stroke("BackSpace") else {
                        return false;
                    };
                    for _ in replaced.chars() {
                        inject_shell_key_stroke(state, &keyboard, backspace, false, time);
                    }
                    type_shell_text(state, &keyboard, text, time)
                }
            }
        }
        super::super::wire::KeyboardCommand::Key { key, ctrl, phase } => {
            let Some(stroke) = shell_named_key_stroke(key) else {
                warn!(%key, "ignored unsupported shell keyboard key");
                return false;
            };
            match phase {
                super::super::wire::KeyboardKeyPhase::Tap => {
                    inject_shell_key_stroke(state, &keyboard, stroke, *ctrl, time)
                }
                super::super::wire::KeyboardKeyPhase::Pressed => {
                    inject_shell_key_transition(state, &keyboard, stroke, KeyState::Pressed, time)
                }
                super::super::wire::KeyboardKeyPhase::Released => {
                    inject_shell_key_transition(state, &keyboard, stroke, KeyState::Released, time)
                }
            }
        }
    }
}

/// Types `text` key by key through the seat keymap, in order; characters no
/// layout has go with keysyms of their own.
#[cfg(feature = "flutter")]
fn type_shell_text(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
    text: &str,
    time: InputTime,
) -> bool {
    let mut delivered = false;
    let mut unplanned = Vec::new();
    for (character, planned) in plan_shell_text(state, keyboard, text) {
        match planned {
            Some(planned) => {
                delivered |= inject_unplanned_shell_text(state, keyboard, &mut unplanned);
                delivered |= inject_planned_shell_stroke(state, keyboard, planned, time);
            }
            None => unplanned.push(character),
        }
    }
    delivered |= inject_unplanned_shell_text(state, keyboard, &mut unplanned);
    delivered
}

#[cfg(feature = "flutter")]
#[derive(Clone)]
pub(super) struct ClientInputRoute {
    window: Option<smithay::desktop::Window>,
    pub(super) layer_root: Option<WlSurface>,
    pub(super) surface: WlSurface,
    region: InputWindowRegion,
    layout_index: usize,
    scene_origin: Point<f64, Logical>,
}

/// A pointer press serial that was actually delivered to a Wayland client.
///
/// Smithay exposes only the serial of its current click grab. Keeping this
/// tiny, physically-bounded list lets XDG move/resize validate a later button
/// in a multi-button grab, and preserves the atlas-routed focus used when the
/// event was delivered.
#[cfg(feature = "flutter")]
pub(super) struct ClientPointerPress {
    serial: Serial,
    button: u32,
    focus: (ClientSurface, Point<f64, Logical>),
    location: Point<f64, Logical>,
}

/// A compositor-forced pointer release remains authoritative until the user
/// deliberately clicks the same toplevel again. Clients may destroy and
/// recreate their protocol constraint after receiving `unlocked`; keying this
/// policy to the window keeps those replacement constraints inactive too.
#[cfg(feature = "flutter")]
#[derive(Debug, Default)]
pub(super) struct PointerConstraintEscape {
    released_window_id: Option<u64>,
}

#[cfg(feature = "flutter")]
impl PointerConstraintEscape {
    fn release_window(&mut self, window_id: u64) {
        self.released_window_id = Some(window_id);
    }

    fn suppresses_window(&self, window_id: u64) -> bool {
        self.released_window_id == Some(window_id)
    }

    fn resume_window(&mut self, window_id: u64) -> bool {
        if !self.suppresses_window(window_id) {
            return false;
        }
        self.released_window_id = None;
        true
    }

    pub(super) fn forget_window(&mut self, window_id: u64) {
        if self.suppresses_window(window_id) {
            self.released_window_id = None;
        }
    }

    fn reset(&mut self) {
        self.released_window_id = None;
    }
}

#[cfg(feature = "flutter")]
impl ClientInputRoute {
    fn mapped_position(&self, position: Point<f64, Logical>) -> Point<f64, Logical> {
        let scene_position = position - self.scene_origin;
        let (local_x, local_y) =
            self.region
                .rect
                .map_to(self.region.source_rect, scene_position.x, scene_position.y);
        Point::from((local_x, local_y))
    }

    fn focus_at_if_hit(
        &self,
        position: Point<f64, Logical>,
    ) -> Option<(ClientSurface, Point<f64, Logical>)> {
        let local_point = self.mapped_position(position);
        let (surface, local_origin) =
            under_from_surface_tree(&self.surface, local_point, (0, 0), WindowSurfaceType::ALL)?;
        Some((
            surface.into(),
            position - local_point + local_origin.to_f64(),
        ))
    }

    fn focus_at(&self, position: Point<f64, Logical>) -> (ClientSurface, Point<f64, Logical>) {
        let local_point = self.mapped_position(position);
        let (surface, local_origin) =
            under_from_surface_tree(&self.surface, local_point, (0, 0), WindowSurfaceType::ALL)
                .unwrap_or_else(|| (self.surface.clone(), (0, 0).into()));
        (
            surface.into(),
            position - local_point + local_origin.to_f64(),
        )
    }

    fn touch_at(
        &self,
        position: Point<f64, Logical>,
    ) -> ((ClientSurface, Point<f64, Logical>), Point<f64, Logical>) {
        let (location, origin) = projected_touch_point(
            self.region.rect,
            self.region.source_rect,
            self.scene_origin,
            position,
        );
        let local_point = location - origin;
        let (surface, local_origin) =
            under_from_surface_tree(&self.surface, local_point, (0, 0), WindowSurfaceType::ALL)
                .unwrap_or_else(|| (self.surface.clone(), (0, 0).into()));
        // Smithay retains the down event's origin for the whole contact. Feed
        // it source-space motion around a fixed origin, so scaling/cropping
        // the texture does not scale input deltas or add the mobile strip.
        ((surface.into(), origin + local_origin.to_f64()), location)
    }
}

#[cfg(feature = "flutter")]
fn projected_touch_point(
    rect: super::super::wire::InputRect,
    source: super::super::wire::InputRect,
    scene_origin: Point<f64, Logical>,
    position: Point<f64, Logical>,
) -> (Point<f64, Logical>, Point<f64, Logical>) {
    let scene = position - scene_origin;
    let (x, y) = rect.map_to(source, scene.x, scene.y);
    let origin = scene_origin
        + Point::from((
            rect.x - source.x * rect.width / source.width,
            rect.y - source.y * rect.height / source.height,
        ));
    (origin + Point::from((x, y)), origin)
}

#[cfg(all(test, feature = "flutter"))]
mod touch_projection_tests {
    use super::super::super::wire::InputRect;
    use super::*;

    #[test]
    fn captured_touch_tracks_source_pixels_through_scale_crop_and_atlas_offset() {
        let scene_origin = Point::from((-1920.0, 100.0));
        let rect = InputRect {
            x: 100.0,
            y: 148.0,
            width: 600.0,
            height: 352.0,
        };
        let source = InputRect {
            x: 12.0,
            y: 48.0,
            width: 1200.0,
            height: 704.0,
        };
        let down = scene_origin + Point::from((250.0, 248.0));
        let (location, origin) = projected_touch_point(rect, source, scene_origin, down);
        assert_eq!(location - origin, Point::from((312.0, 248.0)));
        let captured_origin = origin;
        let moved = down + Point::from((30.0, 60.0));
        let (location, origin) = projected_touch_point(rect, source, scene_origin, moved);
        assert_eq!(origin, captured_origin);
        assert_eq!(location - captured_origin, Point::from((372.0, 368.0)));
        // The second contact uses the same source coordinate system, even
        // while Smithay retains the first contact's down origin.
        let (second, second_origin) = projected_touch_point(
            rect,
            source,
            scene_origin,
            down + Point::from((100.0, 20.0)),
        );
        assert_eq!(second_origin, captured_origin);
        assert_eq!(second - captured_origin, Point::from((512.0, 288.0)));
    }
}

#[cfg(feature = "flutter")]
impl WaylandFrontend {
    #[cfg(feature = "xwayland")]
    pub(super) fn invalidate_window_input_routes(&mut self, window: &smithay::desktop::Window) {
        if self
            .client_input_route_cache
            .as_ref()
            .is_some_and(|route| route.window.as_ref() == Some(window))
        {
            self.client_input_route_cache = None;
        }
        if self
            .client_pointer_capture
            .as_ref()
            .is_some_and(|route| route.window.as_ref() == Some(window))
        {
            self.client_pointer_capture = None;
            self.client_pointer_buttons.clear();
            self.client_pointer_presses.clear();
        }
        self.client_touch_routes
            .retain(|_, route| route.window.as_ref() != Some(window));
    }

    fn window_id_for_input_surface(&self, surface: &WlSurface) -> Option<u64> {
        let root = self
            .owning_toplevel_surface(surface)
            .or_else(|| self.layer_root_surface(surface).map(|(root, _)| root))?;
        self.surface_id(&root)
    }

    pub(super) fn pointer_constraint_released_for_surface(&self, surface: &WlSurface) -> bool {
        self.window_id_for_input_surface(surface)
            .is_some_and(|window_id| self.pointer_constraint_escape.suppresses_window(window_id))
    }

    fn resume_pointer_constraint_for_route(&mut self, route: &ClientInputRoute) -> bool {
        self.pointer_constraint_escape
            .resume_window(route.region.window_id)
    }

    fn remember_client_pointer_press(
        &mut self,
        route: &ClientInputRoute,
        serial: Serial,
        button: u32,
    ) {
        self.client_pointer_presses
            .retain(|press| press.button != button && press.serial != serial);
        if self.client_pointer_presses.len() == MAX_CLIENT_POINTER_PRESSES {
            self.client_pointer_presses.remove(0);
        }
        self.client_pointer_presses.push(ClientPointerPress {
            serial,
            button,
            focus: route.focus_at(self.pointer_location),
            location: self.pointer_location,
        });
    }

    fn forget_client_pointer_button(&mut self, button: u32) {
        self.client_pointer_presses
            .retain(|press| press.button != button);
    }

    pub(super) fn take_client_pointer_press(
        &mut self,
        surface: &WlSurface,
        serial: Serial,
    ) -> Option<GrabStartData<RuntimeState>> {
        let index = self.client_pointer_presses.iter().position(|press| {
            press.serial == serial && press.focus.0.id().same_client_as(&surface.id())
        })?;
        let press = self.client_pointer_presses.remove(index);
        Some(GrabStartData {
            focus: Some(press.focus),
            button: press.button,
            location: press.location,
        })
    }

    /// The contact whose touch down had `serial`, if it is still down on a
    /// surface of the client that names it: its slot, and where it came
    /// down.
    pub(super) fn take_client_touch_press(
        &mut self,
        surface: &WlSurface,
        serial: Serial,
    ) -> Option<(i32, Point<f64, Logical>)> {
        let (slot, position) = self
            .client_touch_downs
            .iter()
            .find(|(slot, (down, _))| {
                *down == serial
                    && self
                        .client_touch_routes
                        .get(slot)
                        .is_some_and(|route| route.surface.id().same_client_as(&surface.id()))
            })
            .map(|(slot, (_, position))| (*slot, *position))?;
        self.client_touch_downs.remove(&slot);
        Some((slot, position))
    }
}

#[cfg(feature = "flutter")]
enum InputTarget {
    Flutter,
    Client(ClientInputRoute),
}

#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SuperPointerAction {
    Move,
    Resize,
}

#[cfg(feature = "flutter")]
fn super_pointer_action(logo: bool, button: u32) -> Option<SuperPointerAction> {
    if !logo {
        return None;
    }
    match button {
        BTN_LEFT => Some(SuperPointerAction::Move),
        BTN_RIGHT => Some(SuperPointerAction::Resize),
        _ => None,
    }
}

#[cfg(feature = "flutter")]
fn resize_edge_for_geometry(
    pointer: Point<f64, Logical>,
    geometry: Rectangle<i32, Logical>,
) -> xdg_toplevel::ResizeEdge {
    let midpoint_x = f64::from(geometry.loc.x) + f64::from(geometry.size.w) / 2.0;
    let midpoint_y = f64::from(geometry.loc.y) + f64::from(geometry.size.h) / 2.0;
    match (pointer.x < midpoint_x, pointer.y < midpoint_y) {
        (true, true) => xdg_toplevel::ResizeEdge::TopLeft,
        (true, false) => xdg_toplevel::ResizeEdge::BottomLeft,
        (false, true) => xdg_toplevel::ResizeEdge::TopRight,
        (false, false) => xdg_toplevel::ResizeEdge::BottomRight,
    }
}

#[cfg(feature = "flutter")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum RoutedPointerTarget {
    Flutter,
    Client(u64),
}

#[cfg(feature = "flutter")]
pub(super) struct PointerMotionTarget {
    routed: RoutedPointerTarget,
    focus: Option<(ClientSurface, Point<f64, Logical>)>,
}

#[cfg(feature = "flutter")]
impl PointerMotionTarget {
    pub(super) const FLUTTER: Self = Self {
        routed: RoutedPointerTarget::Flutter,
        focus: None,
    };

    pub(super) fn client(route: &ClientInputRoute, position: Point<f64, Logical>) -> Self {
        Self {
            routed: RoutedPointerTarget::Client(route.region.surface_id),
            focus: Some(route.focus_at(position)),
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct InputDeviceReset {
    keyboard: bool,
    pointer: bool,
    touch: bool,
}

impl InputDeviceReset {
    const ALL: Self = Self {
        keyboard: true,
        pointer: true,
        touch: true,
    };

    const fn any(self) -> bool {
        self.keyboard || self.pointer || self.touch
    }
}

fn retired_key_consumes_transition(
    retired: &mut HashSet<u32>,
    keycode: u32,
    state: KeyState,
) -> bool {
    match state {
        KeyState::Pressed => retired.contains(&keycode),
        KeyState::Released => retired.remove(&keycode),
    }
}

#[cfg(feature = "flutter")]
fn retired_pointer_button_consumes_transition(
    retired: &mut HashSet<u32>,
    button: u32,
    state: ButtonState,
) -> bool {
    match state {
        ButtonState::Pressed => retired.contains(&button),
        ButtonState::Released => retired.remove(&button),
    }
}

fn update_pressed_buttons(buttons: &mut HashSet<u32>, button: u32, state: ButtonState) {
    match state {
        ButtonState::Pressed => {
            buttons.insert(button);
        }
        ButtonState::Released => {
            buttons.remove(&button);
        }
    }
}

#[cfg(feature = "flutter")]
pub(super) fn retire_flutter_generation_keys(
    active: &mut HashSet<u32>,
    retired: &mut HashSet<u32>,
) {
    retired.extend(active.drain());
}

#[cfg(feature = "flutter")]
fn route_shell_key_transition(
    held: &mut HashSet<u32>,
    keycode: u32,
    state: KeyState,
    seat_pressed: bool,
) -> bool {
    match state {
        KeyState::Pressed => !seat_pressed && held.insert(keycode),
        KeyState::Released => held.remove(&keycode),
    }
}

#[cfg(feature = "flutter")]
pub(super) fn region_accepts_input(
    region: &InputWindowRegion,
    position: Point<f64, Logical>,
) -> bool {
    region.rect.contains(position.x, position.y)
        && region.visible()
        && region.hit_test_enabled()
        && region.window_id == region.object_id
}

#[cfg(feature = "flutter")]
fn software_keyboard_owns_touch(
    layout: Option<&InputLayoutSnapshot>,
    scene_position: Point<f64, Logical>,
) -> bool {
    layout.is_some_and(|layout| {
        layout
            .software_keyboard_regions
            .iter()
            .any(|region| region.contains(scene_position.x, scene_position.y))
    })
}

#[cfg(feature = "flutter")]
impl WaylandFrontend {
    fn client_input_route_is_live(&self, route: &ClientInputRoute) -> bool {
        // Window unmap paths invalidate their cached routes explicitly. The
        // stable surface map is therefore the only lifecycle check needed at
        // input frequency; avoiding Space's element lookup keeps a cache hit
        // independent of the number of windows.
        self.surfaces_by_id
            .get(&route.region.surface_id)
            .is_some_and(|surface| surface == &route.surface)
            && (route.window.is_some()
                || route.layer_root.as_ref().is_some_and(|expected| {
                    self.layer_root_surface(&route.surface)
                        .is_some_and(|(current, _)| current == *expected)
                })
                || self.input_method.owns_popup_surface(&route.surface))
    }

    pub(super) fn input_route(
        &mut self,
        position: Point<f64, Logical>,
    ) -> Option<&ClientInputRoute> {
        let layout = self.input_layout.as_ref()?;
        let scene_position = position - self.atlas_origin;
        if layout.exclusive_shell()
            || layout
                .shell_regions
                .iter()
                .any(|region| region.contains(scene_position.x, scene_position.y))
        {
            return None;
        }

        // Local Flutter windows participate in the same front-to-back window
        // region list as client surfaces. They intentionally have no Smithay
        // input target: once the topmost hit is local, stop traversal so a
        // covered Wayland client cannot receive the event through it.
        if layout
            .windows
            .iter()
            .find(|region| region_accepts_input(region, scene_position))
            .is_some_and(|region| self.local_windows.contains(region.window_id))
        {
            self.client_input_route_cache = None;
            return None;
        }

        // Pointer samples commonly arrive much faster than Flutter layout
        // snapshots. Reuse the fully validated route while it remains the
        // topmost candidate instead of walking Space and the surface tree at
        // input frequency. Regions preceding it still need a cheap geometry
        // check because windows are ordered front-to-back and may overlap.
        let cached_is_valid = self.client_input_route_cache.as_ref().is_some_and(|route| {
            region_accepts_input(&route.region, scene_position)
                && route.focus_at_if_hit(position).is_some()
                && layout
                    .windows
                    .get(..route.layout_index)
                    .is_some_and(|higher_regions| {
                        !higher_regions
                            .iter()
                            .any(|region| region_accepts_input(region, scene_position))
                    })
                && self.client_input_route_is_live(route)
        });
        if cached_is_valid {
            return self.client_input_route_cache.as_ref();
        }

        let route = layout
            .windows
            .iter()
            .enumerate()
            .find_map(|(layout_index, region)| {
                if !region_accepts_input(region, scene_position) {
                    return None;
                }
                let surface = self.surfaces_by_id.get(&region.surface_id).cloned()?;
                if self.input_method.owns_popup_surface(&surface) {
                    return Some(ClientInputRoute {
                        window: None,
                        layer_root: None,
                        surface,
                        region: *region,
                        layout_index,
                        scene_origin: self.atlas_origin,
                    });
                }
                if let Some((layer_root, _)) = self.layer_root_surface(&surface) {
                    if self.surface_id(&layer_root) != Some(region.window_id) {
                        return None;
                    }
                    let route = ClientInputRoute {
                        window: None,
                        layer_root: Some(layer_root),
                        surface,
                        region: *region,
                        layout_index,
                        scene_origin: self.atlas_origin,
                    };
                    return route.focus_at_if_hit(position).is_some().then_some(route);
                }
                let window = self.window_for_id(region.window_id)?;
                let root_surface = self.window_root_surface(&window)?;
                if self.owning_toplevel_surface(&surface).as_ref() != Some(&root_surface) {
                    return None;
                }
                let route = ClientInputRoute {
                    window: Some(window.clone()),
                    layer_root: None,
                    surface,
                    region: *region,
                    layout_index,
                    scene_origin: self.atlas_origin,
                };
                route.focus_at_if_hit(position).is_some().then_some(route)
            });

        if let Some(route) = route {
            self.client_input_route_cache = Some(route);
            return self.client_input_route_cache.as_ref();
        }

        None
    }

    fn local_flutter_window_region_at(
        &self,
        position: Point<f64, Logical>,
    ) -> Option<InputWindowRegion> {
        let layout = self.input_layout.as_ref()?;
        let scene_position = position - self.atlas_origin;
        if layout.exclusive_shell()
            || layout
                .shell_regions
                .iter()
                .any(|region| region.contains(scene_position.x, scene_position.y))
        {
            return None;
        }
        layout
            .windows
            .iter()
            .find(|region| region_accepts_input(region, scene_position))
            .copied()
            .filter(|region| self.local_windows.contains(region.window_id))
    }

    fn touch_window_target_at(&self, position: Point<f64, Logical>) -> Option<TouchWindowTarget> {
        let layout = self.input_layout.as_ref()?;
        let scene_position = position - self.atlas_origin;
        if layout.exclusive_shell()
            || layout
                .shell_regions
                .iter()
                .any(|region| region.contains(scene_position.x, scene_position.y))
        {
            return None;
        }
        let region = layout
            .windows
            .iter()
            .find(|region| region_accepts_input(region, scene_position))?;
        let geometry = if self.local_windows.contains(region.window_id) {
            self.local_flutter_window_geometry(region.window_id)?
        } else {
            let window = self.window_for_id(region.window_id)?;
            let geometry = self.window_geometry_target(&window);
            super::super::wire::WindowGeometry {
                x: f64::from(geometry.loc.x),
                y: f64::from(geometry.loc.y),
                width: f64::from(geometry.size.w),
                height: f64::from(geometry.size.h),
            }
        };
        Some(TouchWindowTarget {
            window_id: region.window_id,
            geometry,
            in_gesture_strip: scene_position.y
                >= region.rect.y + region.rect.height
                    - WINDOW_TOUCH_STRIP_HEIGHT.min(region.rect.height),
            in_move_corner: {
                let corner_width = WINDOW_TOUCH_CORNER_SIZE.min(region.rect.width * 0.5);
                let corner_height = WINDOW_TOUCH_CORNER_SIZE.min(region.rect.height * 0.5);
                let on_horizontal_edge = scene_position.x < region.rect.x + corner_width
                    || scene_position.x >= region.rect.x + region.rect.width - corner_width;
                let on_vertical_edge = scene_position.y < region.rect.y + corner_height
                    || scene_position.y >= region.rect.y + region.rect.height - corner_height;
                on_horizontal_edge && on_vertical_edge
            },
            geometry_locked: region.geometry_locked(),
        })
    }

    fn input_target(&mut self, position: Point<f64, Logical>) -> InputTarget {
        self.input_route(position)
            .cloned()
            .map_or(InputTarget::Flutter, InputTarget::Client)
    }

    /// While the phone is locked, only the calls app's window shown over the
    /// lock screen takes input; everything else goes to the lock screen.
    #[cfg(feature = "flutter")]
    fn locked_input_target(&mut self, position: Point<f64, Logical>) -> InputTarget {
        match self.input_target(position) {
            InputTarget::Client(route)
                if route
                    .window
                    .as_ref()
                    .is_some_and(|window| self.window_over_lock(window)) =>
            {
                InputTarget::Client(route)
            }
            _ => InputTarget::Flutter,
        }
    }

    pub(super) fn pointer_motion_target(
        &mut self,
        position: Point<f64, Logical>,
    ) -> PointerMotionTarget {
        self.input_route(position)
            .map_or(PointerMotionTarget::FLUTTER, |route| {
                PointerMotionTarget::client(route, position)
            })
    }
}

pub(in super::super) fn init_libinput(
    event_loop: &mut EventLoop<'static, RuntimeState>,
    session: LibSeatSession,
    seat_name: &str,
) -> Result<Libinput, Box<dyn Error>> {
    let mut context =
        Libinput::new_with_udev::<LibinputSessionInterface<LibSeatSession>>(session.into());
    context
        .udev_assign_seat(seat_name)
        .map_err(|()| "libinput could not assign the active seat")?;
    // Libinput's context survives a libseat pause, but its device descriptors
    // do not. Keep one reference beside the event source so the session
    // lifecycle can suspend the old descriptors and reopen them on activation.
    // The seat's devices are queued now, and again on every resume, with
    // nothing to read on libinput's descriptor: the source delivers them in
    // the loop's next turn instead of waiting for unrelated input.
    let lifecycle_context = context.clone();
    let backend = LibinputBatchSource::new(context);
    event_loop
        .handle()
        .insert_source(backend, |event, batch, state| {
            match event {
                InputBatchEvent::Input(event) => {
                    batch.flush_clients |= process_input_event(state, event);
                }
                // libinput is independent from the Wayland client socket
                // source. Flush after the source has drained the complete batch:
                // clients still observe input immediately, while a burst of
                // samples costs one non-blocking socket flush instead of one
                // syscall per event.
                InputBatchEvent::Complete => {
                    if batch.flush_clients
                        && let Some(frontend) = state.wayland.as_mut()
                        && let Err(error) = frontend.display_handle.flush_clients()
                    {
                        warn!(%error, "could not flush Wayland clients after native input batch");
                    }
                }
            }
        })?;
    Ok(lifecycle_context)
}

impl WaylandFrontend {
    pub(in super::super) fn suspend_input_session(&mut self) {
        self.libinput.suspend();
    }

    pub(in super::super) fn resume_input_session(&mut self) -> Result<(), &'static str> {
        #[cfg(feature = "flutter")]
        self.input_rescan.request();
        self.libinput
            .resume()
            .map_err(|()| "libinput rejected session resume")
    }
}

/// A key from a keyboard: shortcuts first, then the Mac preset's
/// translation, then the seat.
#[cfg(feature = "flutter")]
fn process_keyboard_transition(
    state: &mut RuntimeState,
    keycode: Keycode,
    key_state: KeyState,
    time: InputTime,
) -> bool {
    process_key_transition(state, keycode, key_state, time, false)
}

/// A key the shell's own keyboard types: the Mac preset leaves it as it is,
/// so the on-screen Alt stays Alt.
#[cfg(feature = "flutter")]
fn process_shell_keyboard_transition(
    state: &mut RuntimeState,
    keycode: Keycode,
    key_state: KeyState,
    time: InputTime,
) -> bool {
    process_key_transition(state, keycode, key_state, time, true)
}

#[cfg(feature = "flutter")]
fn process_key_transition(
    state: &mut RuntimeState,
    keycode: Keycode,
    key_state: KeyState,
    time: InputTime,
    from_shell: bool,
) -> bool {
    state.note_user_activity();
    let consumed = intercept_native_escape(state, keycode.raw(), key_state);
    let Some(evdev_keycode) = keycode.raw().checked_sub(8) else {
        if !consumed {
            deliver_key(state, keycode, key_state, time, KeyboardSource::MAIN);
        }
        return true;
    };
    let pressed = key_state == KeyState::Pressed;
    let context = mac_keys::KeyContext {
        client: if pressed && !consumed {
            focused_client_kind(state)
        } else {
            mac_keys::ClientKind::Ordinary
        },
        consumed,
        raw: from_shell || keys_reach_apps_raw(state),
    };
    let events = state.mac_keys.key(evdev_keycode, pressed, context);
    if !events.is_empty() {
        if !state.secure_session_locked() {
            focus_exclusive_layer_for_keyboard_event(state);
        }
        deliver_mac_key_events(state, &events, time);
    }
    // The app the app switcher took the keyboard from gets it back once the
    // switcher's modifier went up, past the shell, or Escape closed it.
    if !state.native_escape_shortcut.app_switcher_held() {
        super::focus::restore_keyboard_focus_after_switcher(state);
    }
    true
}

/// Feeds the Mac preset's transitions to the seat.
#[cfg(feature = "flutter")]
fn deliver_mac_key_events(
    state: &mut RuntimeState,
    events: &[mac_keys::KeyEvent],
    time: InputTime,
) {
    for event in events {
        let source = match event.source {
            mac_keys::KeySource::Physical => KeyboardSource::MAIN,
            mac_keys::KeySource::Synthetic => mac_keys_source(),
        };
        let key_state = if event.pressed {
            KeyState::Pressed
        } else {
            KeyState::Released
        };
        deliver_key(state, Keycode::new(event.key + 8), key_state, time, source);
    }
}

#[cfg(feature = "flutter")]
fn deliver_key(
    state: &mut RuntimeState,
    keycode: Keycode,
    key_state: KeyState,
    time: InputTime,
    source: KeyboardSource,
) {
    if state.flutter_active {
        process_flutter_keyboard_transition(state, keycode, key_state, time, source);
        return;
    }
    if state.secure_session_locked() {
        // Native lock state remains authoritative if Flutter is restarting or
        // unavailable. No keyboard source may fall through to a client.
        return;
    }
    process_wayland_keyboard_transition_from(state, keycode, key_state, time, source);
}

/// The keyboard source of the keys the Mac preset adds: a synthetic Ctrl
/// joins a held physical Ctrl instead of replacing it.
#[cfg(feature = "flutter")]
fn mac_keys_source() -> KeyboardSource {
    static SOURCE: std::sync::OnceLock<KeyboardSource> = std::sync::OnceLock::new();
    *SOURCE.get_or_init(KeyboardSource::new_auxiliary)
}

/// Keys reach the focused app as they are: the session is locked, or the
/// app holds Denial's shortcuts (a remote desktop, a virtual machine).
#[cfg(feature = "flutter")]
fn keys_reach_apps_raw(state: &RuntimeState) -> bool {
    state.secure_session_locked()
        || state
            .wayland
            .as_ref()
            .is_some_and(|frontend| frontend.shortcuts_inhibit.active())
}

/// Whether the keyboard's focus is a terminal, by its app ID or X11 class.
/// The shell and windows without an ID are ordinary.
#[cfg(feature = "flutter")]
fn focused_client_kind(state: &RuntimeState) -> mac_keys::ClientKind {
    let Some(frontend) = state.wayland.as_ref() else {
        return mac_keys::ClientKind::Ordinary;
    };
    let Some(keyboard) = frontend.seat.get_keyboard() else {
        return mac_keys::ClientKind::Ordinary;
    };
    let metadata = match keyboard.current_focus() {
        Some(super::focus::KeyboardFocusTarget::Wayland(surface)) => {
            let root = frontend
                .owning_toplevel_surface(&surface)
                .unwrap_or(surface);
            super::focus::KeyboardFocusTarget::Wayland(root).window_metadata()
        }
        Some(focus) => focus.window_metadata(),
        None => None,
    };
    metadata.map_or(mac_keys::ClientKind::Ordinary, |(_, app_id)| {
        mac_keys::client_kind(&app_id)
    })
}

/// The Mac preset follows `shortcuts.preset`. Turning it off lets go of the
/// keys it holds for an app.
#[cfg(feature = "flutter")]
pub(in super::super) fn set_mac_keys_enabled(state: &mut RuntimeState, enabled: bool) {
    let events = state.mac_keys.set_enabled(enabled);
    if !events.is_empty() {
        deliver_mac_key_events(state, &events, InputTime::now());
    }
}

/// Whether the focused app saw a modifier that is still held go down, as
/// Alt does in the standard keys: the app switcher then takes the keyboard
/// from the app until it ends.
#[cfg(feature = "flutter")]
fn app_saw_a_held_modifier(state: &RuntimeState) -> bool {
    [
        mac_keys::KEY_LEFTALT,
        mac_keys::KEY_RIGHTALT,
        mac_keys::KEY_LEFTCTRL,
        mac_keys::KEY_RIGHTCTRL,
        mac_keys::KEY_LEFTSHIFT,
        mac_keys::KEY_RIGHTSHIFT,
    ]
    .into_iter()
    .any(|key| state.mac_keys.delivers(key))
}

/// A pointer button goes down: with ⌘ held in the Mac preset, the app gets
/// Ctrl with it (⌘-click).
#[cfg(feature = "flutter")]
fn note_mac_keys_pointer_button(state: &mut RuntimeState) {
    let raw = keys_reach_apps_raw(state);
    let events = state.mac_keys.pointer_button(raw);
    if !events.is_empty() {
        deliver_mac_key_events(state, &events, InputTime::now());
    }
}

fn focus_exclusive_layer_for_keyboard_event(state: &mut RuntimeState) {
    let Some((keyboard, focus)) = state.wayland.as_ref().and_then(|frontend| {
        if frontend.text_input.shell_captures_keyboard() {
            return None;
        }
        Some((
            frontend.seat.get_keyboard()?,
            frontend.exclusive_layer_keyboard_focus()?,
        ))
    }) else {
        return;
    };
    if keyboard.current_focus().as_ref() != Some(&focus) {
        super::focus::request_keyboard_focus(
            state,
            &keyboard,
            Some(focus),
            SERIAL_COUNTER.next_serial(),
        );
    }
}

fn configure_touchpad_device(
    device: &mut LibinputDevice,
    settings: &TouchpadSettings,
) -> Result<(), String> {
    let finger_count = device.config_tap_finger_count();
    if finger_count > 0 {
        if let Err(error) = device.config_tap_set_button_map(TapButtonMap::LeftRightMiddle) {
            // Keep tap-to-click usable if a device rejects explicit remapping;
            // libinput's normal default is the same left/right/middle order.
            warn!(
                ?error,
                device = %device.name(),
                "could not configure multi-finger tap button mapping"
            );
        }

        device
            .config_tap_set_enabled(settings.tap_to_click_enabled)
            .map_err(|error| {
                format!(
                    "could not set tap-to-click on {} to {}: {error:?}",
                    device.name(),
                    settings.tap_to_click_enabled
                )
            })?;
    }

    let natural_scroll_supported = device.config_scroll_has_natural_scroll();
    if natural_scroll_supported {
        device
            .config_scroll_set_natural_scroll_enabled(settings.natural_scroll_enabled)
            .map_err(|error| {
                format!(
                    "could not set natural scrolling on {} to {}: {error:?}",
                    device.name(),
                    settings.natural_scroll_enabled
                )
            })?;
    }

    // libinput's own touchpad curve, with the same speed and profile choice
    // as a mouse's.
    let acceleration_supported = device.config_accel_is_available();
    let acceleration_profile = if settings.acceleration_enabled {
        AccelProfile::Adaptive
    } else {
        AccelProfile::Flat
    };
    if acceleration_supported {
        device
            .config_accel_set_speed(settings.speed)
            .map_err(|error| {
                format!(
                    "could not set pointer speed on {} to {}: {error:?}",
                    device.name(),
                    settings.speed
                )
            })?;
        device
            .config_accel_set_profile(acceleration_profile)
            .map_err(|error| {
                format!(
                    "could not set pointer acceleration on {} to {acceleration_profile:?}: {error:?}",
                    device.name()
                )
            })?;
    }

    // Only a clickpad, whose surface is its one button, offers both methods;
    // a touchpad with separate buttons offers none.
    let click_method = match settings.click_method {
        TouchpadClickMethod::Clickfinger => ClickMethod::Clickfinger,
        TouchpadClickMethod::ButtonAreas => ClickMethod::ButtonAreas,
    };
    let click_method_supported = device.config_click_methods().contains(&click_method);
    if click_method_supported {
        device
            .config_click_set_method(click_method)
            .map_err(|error| {
                format!(
                    "could not set the click method of {} to {click_method:?}: {error:?}",
                    device.name()
                )
            })?;
        if click_method == ClickMethod::Clickfinger
            && let Err(error) = device
                .config_click_clickfinger_set_button_map(ClickfingerButtonMap::LeftRightMiddle)
        {
            // libinput's normal default is the same left/right/middle order.
            warn!(
                ?error,
                device = %device.name(),
                "could not configure the clickfinger button mapping"
            );
        }
    }

    info!(
        device = %device.name(),
        finger_count,
        tap_to_click_enabled = settings.tap_to_click_enabled,
        natural_scroll_enabled = settings.natural_scroll_enabled,
        natural_scroll_supported,
        two_finger_tap_right_click = finger_count >= 2,
        speed = settings.speed,
        ?acceleration_profile,
        acceleration_supported,
        ?click_method,
        click_method_supported,
        "configured touchpad"
    );
    Ok(())
}

fn is_touchpad_device(device: &LibinputDevice) -> bool {
    // SAFETY: this device came from the same udev-backed libinput context used
    // to construct the event source, as required by input::Device::udev_device.
    let udev_marks_touchpad = unsafe { device.udev_device() }.and_then(|device| {
        device
            .property_value("ID_INPUT_TOUCHPAD")
            .map(|value| value == OsStr::new("1"))
    });
    udev_marks_touchpad.unwrap_or_else(|| device.config_tap_finger_count() > 0)
}

/// Whether a keyboard device is one to type on. To libinput, power buttons,
/// volume rockers and media key pads are keyboards too. udev marks a keyboard
/// (ID_INPUT_KEYBOARD) when it has the first 31 keys, Esc to D; it must also
/// have every letter, the space bar and Enter.
#[cfg(feature = "flutter")]
fn is_typing_keyboard(device: &LibinputDevice) -> bool {
    // SAFETY: this device came from the same udev-backed libinput context used
    // to construct the event source, as required by input::Device::udev_device.
    let udev_marks_keyboard = unsafe { device.udev_device() }.map(|device| {
        device
            .property_value("ID_INPUT_KEYBOARD")
            .is_some_and(|value| value == OsStr::new("1"))
    });
    udev_marks_keyboard.unwrap_or(true)
        && has_typing_keys(|key| device.keyboard_has_key(key).unwrap_or(false))
}

/// linux/input-event-codes.h: the letters, the space bar and Enter.
#[cfg(feature = "flutter")]
const TYPING_KEYS: [u32; 28] = [
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, // Q W E R T Y U I O P
    30, 31, 32, 33, 34, 35, 36, 37, 38, // A S D F G H J K L
    44, 45, 46, 47, 48, 49, 50, // Z X C V B N M
    57, // Space
    28, // Enter
];

#[cfg(feature = "flutter")]
fn has_typing_keys(has_key: impl Fn(u32) -> bool) -> bool {
    TYPING_KEYS.into_iter().all(has_key)
}

/// linux/input.h BUS_VIRTUAL: uinput devices made by programs.
#[cfg(feature = "flutter")]
const BUS_VIRTUAL: u16 = 0x06;

/// Whether a keyboard on this bus is a physical one, for the shell's
/// presentation to follow. Virtual (uinput) keyboards of test tools and
/// remappers do not count. Bluetooth keyboards come through uhid with their
/// own bus (BUS_BLUETOOTH), so they count; so does a device whose bus cannot
/// be read.
#[cfg(feature = "flutter")]
fn is_physical_keyboard_bus(bus: Option<u16>) -> bool {
    bus != Some(BUS_VIRTUAL)
}

/// What decides whether a device is ignored while the lid is closed.
#[cfg(feature = "flutter")]
fn lid_device_traits(device: &LibinputDevice) -> lid_switch::InputDeviceTraits {
    lid_switch::InputDeviceTraits {
        bus: input_device_bus(device),
        touch: Device::has_capability(device, DeviceCapability::Touch),
        tablet: Device::has_capability(device, DeviceCapability::TabletTool)
            || Device::has_capability(device, DeviceCapability::TabletPad),
        keyboard: Device::has_capability(device, DeviceCapability::Keyboard)
            && is_typing_keyboard(device),
        touchpad: is_touchpad_device(device),
    }
}

/// The kernel's bus type of an input device: `id/bustype` of the input
/// device above its event node.
#[cfg(feature = "flutter")]
fn input_device_bus(device: &LibinputDevice) -> Option<u16> {
    // SAFETY: this device came from the same udev-backed libinput context used
    // to construct the event source, as required by input::Device::udev_device.
    let node = unsafe { device.udev_device() }?;
    let input = node.parent()?;
    let bus = input.attribute_value("id/bustype")?.to_str()?;
    u16::from_str_radix(bus.trim(), 16).ok()
}

/// The device an input event came from; none for a device added or removed.
#[cfg(feature = "flutter")]
fn input_event_device(event: &InputEvent<LibinputInputBackend>) -> Option<LibinputDevice> {
    Some(match event {
        InputEvent::Keyboard { event } => event.device(),
        InputEvent::PointerMotion { event } => event.device(),
        InputEvent::PointerMotionAbsolute { event } => event.device(),
        InputEvent::PointerButton { event } => event.device(),
        InputEvent::PointerAxis { event } => event.device(),
        InputEvent::GestureSwipeBegin { event } => event.device(),
        InputEvent::GestureSwipeUpdate { event } => event.device(),
        InputEvent::GestureSwipeEnd { event } => event.device(),
        InputEvent::GesturePinchBegin { event } => event.device(),
        InputEvent::GesturePinchUpdate { event } => event.device(),
        InputEvent::GesturePinchEnd { event } => event.device(),
        InputEvent::GestureHoldBegin { event } => event.device(),
        InputEvent::GestureHoldEnd { event } => event.device(),
        InputEvent::TouchDown { event } => event.device(),
        InputEvent::TouchMotion { event } => event.device(),
        InputEvent::TouchUp { event } => event.device(),
        InputEvent::TouchCancel { event } => event.device(),
        InputEvent::TouchFrame { event } => event.device(),
        InputEvent::TabletToolAxis { event } => event.device(),
        InputEvent::TabletToolProximity { event } => event.device(),
        InputEvent::TabletToolTip { event } => event.device(),
        InputEvent::TabletToolButton { event } => event.device(),
        InputEvent::SwitchToggle { event } => event.device(),
        InputEvent::DeviceAdded { .. }
        | InputEvent::DeviceRemoved { .. }
        | InputEvent::Special(_) => return None,
    })
}

fn is_mouse_device(device: &LibinputDevice) -> bool {
    // Do not infer this from pointer capability alone: touchpads expose the
    // same capability and have an independently configurable input model.
    let udev_marks_mouse = unsafe { device.udev_device() }.and_then(|device| {
        device
            .property_value("ID_INPUT_MOUSE")
            .map(|value| value == OsStr::new("1"))
    });
    udev_marks_mouse.unwrap_or(false) && device.config_accel_is_available()
}

fn configure_mouse_device(
    device: &mut LibinputDevice,
    settings: &MouseSettings,
) -> Result<(), String> {
    device
        .config_accel_set_speed(settings.speed)
        .map_err(|error| {
            format!(
                "could not set pointer speed on {} to {}: {error:?}",
                device.name(),
                settings.speed
            )
        })?;
    let profile = if settings.acceleration_enabled {
        AccelProfile::Adaptive
    } else {
        AccelProfile::Flat
    };
    device.config_accel_set_profile(profile).map_err(|error| {
        format!(
            "could not set pointer acceleration on {} to {profile:?}: {error:?}",
            device.name()
        )
    })?;
    let natural_scroll_supported = device.config_scroll_has_natural_scroll();
    if natural_scroll_supported {
        device
            .config_scroll_set_natural_scroll_enabled(settings.natural_scroll_enabled)
            .map_err(|error| {
                format!(
                    "could not set wheel natural scrolling on {} to {}: {error:?}",
                    device.name(),
                    settings.natural_scroll_enabled
                )
            })?;
    }
    info!(
        device = %device.name(),
        speed = settings.speed,
        ?profile,
        natural_scroll_enabled = settings.natural_scroll_enabled,
        natural_scroll_supported,
        "configured mouse"
    );
    Ok(())
}

#[cfg(feature = "flutter")]
pub(in super::super) fn install_mouse_settings(
    state: &mut RuntimeState,
    settings: &MouseSettings,
) -> Result<(), String> {
    for device in state.input_devices.mice.values_mut() {
        configure_mouse_device(device, settings)?;
    }
    Ok(())
}

#[cfg(feature = "flutter")]
pub(in super::super) fn install_touchpad_settings(
    state: &mut RuntimeState,
    settings: &TouchpadSettings,
) -> Result<(), String> {
    for device in state.input_devices.touchpads.values_mut() {
        configure_touchpad_device(device, settings)?;
    }
    Ok(())
}

#[cfg(feature = "flutter")]
fn process_touchpad_gesture_event(
    state: &mut RuntimeState,
    event: &InputEvent<LibinputInputBackend>,
) -> Option<bool> {
    if !state.flutter_active || state.secure_session_locked() {
        if matches!(
            event,
            InputEvent::GestureSwipeBegin { .. }
                | InputEvent::GestureSwipeUpdate { .. }
                | InputEvent::GestureSwipeEnd { .. }
        ) {
            settle_touchpad_swipe_reset(state, "the shell is locked or restarting");
            state.native_escape_shortcut.cancel_gestures();
            return Some(false);
        }
        return None;
    }

    let gesture_event = match event {
        InputEvent::GestureSwipeBegin { event } => {
            let device = event.device();
            let tracking = swipe_tracking(state, None);
            state
                .touchpad_gestures
                .begin_swipe(device.sysname(), event.fingers(), tracking);
            None
        }
        InputEvent::GestureSwipeUpdate { event } => {
            let device = event.device();
            state.touchpad_gestures.update_swipe(
                device.sysname(),
                event.delta_x(),
                event.delta_y(),
                event.time().micros(),
            )
        }
        InputEvent::GestureSwipeEnd { event } => {
            let device = event.device();
            state.touchpad_gestures.end_swipe(
                device.sysname(),
                event.cancelled(),
                event.time().micros(),
            )
        }
        _ => return None,
    };

    Some(gesture_event.is_some_and(|event| dispatch_swipe_gesture(state, event, None)))
}

/// Which motions of a three-finger swipe starting now follow the fingers:
/// sideways the strip of a scrolling or full-screen apps layout, up and down
/// the full-screen apps layout's overview and app windows. `position`: where
/// fingers on the touchscreen came down.
#[cfg(feature = "flutter")]
fn swipe_tracking(
    state: &RuntimeState,
    position: Option<Point<f64, Logical>>,
) -> super::super::touchpad_gestures::SwipeTracking {
    use super::super::touchpad_gestures::SwipeTracking;
    let vertical = state.wayland.as_ref().is_some_and(|frontend| {
        frontend.screens_layout_active()
            && position.is_none_or(|position| !frontend.point_on_phone(position))
    });
    SwipeTracking {
        horizontal: horizontal_swipe_directions(state, position),
        vertical,
    }
}

#[cfg(feature = "flutter")]
fn horizontal_swipe_directions(
    state: &RuntimeState,
    position: Option<Point<f64, Logical>>,
) -> super::super::touchpad_gestures::HorizontalScrollDirections {
    use super::super::touchpad_gestures::HorizontalScrollDirections;
    let scrolling_layout = state
        .wayland
        .as_ref()
        .is_some_and(|frontend| frontend.can_scroll_layout_horizontally_at(position));
    if !scrolling_layout {
        return HorizontalScrollDirections::default();
    }
    // The full-screen apps layout always moves its strip with three
    // fingers; the scrolling layout does when the user's shortcuts bind them
    // to the window switcher.
    if state
        .wayland
        .as_ref()
        .is_some_and(WaylandFrontend::screens_layout_active)
    {
        return HorizontalScrollDirections {
            left: true,
            right: true,
        };
    }
    HorizontalScrollDirections {
        left: state.native_escape_shortcut.gesture_invokes(
            ShortcutGesture::ThreeFingerSwipeLeft,
            ShortcutAction::WindowSwitcher,
        ),
        right: state.native_escape_shortcut.gesture_invokes(
            ShortcutGesture::ThreeFingerSwipeRight,
            ShortcutAction::WindowSwitcher,
        ),
    }
}

#[cfg(feature = "flutter")]
pub(super) fn dispatch_swipe_gesture(
    state: &mut RuntimeState,
    gesture_event: super::super::touchpad_gestures::TouchpadGestureEvent,
    position: Option<Point<f64, Logical>>,
) -> bool {
    use super::super::touchpad_gestures::TouchpadGestureEvent;

    if !state.flutter_active || state.secure_session_locked() {
        match gesture_event {
            TouchpadGestureEvent::HorizontalScrollEnd { .. } => {
                finish_horizontal_layout_scroll(state, true, None);
            }
            TouchpadGestureEvent::VerticalBegin { .. }
            | TouchpadGestureEvent::VerticalUpdate { .. }
            | TouchpadGestureEvent::VerticalEnd { .. } => {
                cancel_shell_gesture(
                    state,
                    Some(shell_gesture_source(position)),
                    "the shell is locked or restarting",
                );
            }
            _ => {}
        }
        state.native_escape_shortcut.cancel_gestures();
        return false;
    }

    match gesture_event {
        TouchpadGestureEvent::HorizontalScrollBegin { delta_x } => {
            let handled = update_horizontal_layout_scroll(state, delta_x, position.is_some());
            if handled {
                info!("began continuous scrolling-layout gesture");
            }
            return handled;
        }
        TouchpadGestureEvent::HorizontalScrollUpdate { delta_x } => {
            return update_horizontal_layout_scroll(state, delta_x, position.is_some());
        }
        TouchpadGestureEvent::HorizontalScrollEnd {
            cancelled,
            projected_delta_x,
        } => {
            return finish_horizontal_layout_scroll_from(
                state,
                cancelled,
                Some(projected_delta_x),
                position.is_some(),
            );
        }
        TouchpadGestureEvent::VerticalBegin { .. }
        | TouchpadGestureEvent::VerticalUpdate { .. }
        | TouchpadGestureEvent::VerticalEnd { .. } => {
            return follow_vertical_swipe(state, gesture_event, position);
        }
        TouchpadGestureEvent::Trigger(_)
        | TouchpadGestureEvent::Repeat(_)
        | TouchpadGestureEvent::End(_) => {}
    }

    if state
        .wayland
        .as_ref()
        .is_some_and(WaylandFrontend::screens_layout_active)
    {
        return dispatch_screens_gesture(state, gesture_event, position);
    }

    let (gesture, disposition) = match gesture_event {
        TouchpadGestureEvent::Trigger(gesture) => (
            gesture,
            state.native_escape_shortcut.observe_gesture(gesture),
        ),
        TouchpadGestureEvent::Repeat(gesture) => (
            gesture,
            state.native_escape_shortcut.observe_gesture_repeat(gesture),
        ),
        TouchpadGestureEvent::End(gesture) => {
            (gesture, state.native_escape_shortcut.end_gesture(gesture))
        }
        TouchpadGestureEvent::HorizontalScrollBegin { .. }
        | TouchpadGestureEvent::HorizontalScrollUpdate { .. }
        | TouchpadGestureEvent::HorizontalScrollEnd { .. }
        | TouchpadGestureEvent::VerticalBegin { .. }
        | TouchpadGestureEvent::VerticalUpdate { .. }
        | TouchpadGestureEvent::VerticalEnd { .. } => {
            unreachable!("continuous swipe events return before shortcut dispatch")
        }
    };
    let handled = execute_shortcut_disposition_at(state, disposition, position);
    if handled {
        info!(
            ?gesture,
            "recognized configured compositor shortcut gesture"
        );
    }
    handled
}

/// Travel of three fingers on a touchpad that opens the full-screen apps
/// layout's overview or app windows fully: the same hand movement that
/// moves its strip by one screen (400 units, about 37 mm on the cover's
/// touchpad; `TOUCHPAD_SCREEN_SWIPE_DISTANCE`).
#[cfg(feature = "flutter")]
const TOUCHPAD_SHELL_GESTURE_TRAVEL: f64 = 400.0;

/// The same for three fingers on the touchscreen, as a share of the height
/// of the output under them: 288 of the tablet's 960 logical px, about
/// 55 mm of its 185 mm panel.
#[cfg(feature = "flutter")]
const TOUCHSCREEN_SHELL_GESTURE_SHARE: f64 = 0.3;

/// Where a swipe comes from: the touchscreen (with where its fingers came
/// down) or a touchpad.
#[cfg(feature = "flutter")]
const fn shell_gesture_source(
    position: Option<Point<f64, Logical>>,
) -> super::super::shell_gestures::ShellGestureSource {
    use super::super::shell_gestures::ShellGestureSource;
    if position.is_some() {
        ShellGestureSource::Touchscreen
    } else {
        ShellGestureSource::Touchpad
    }
}

/// The travel that opens a shell gesture's view fully, in the units of the
/// swipe (see [`TOUCHPAD_SHELL_GESTURE_TRAVEL`] and
/// [`TOUCHSCREEN_SHELL_GESTURE_SHARE`]).
#[cfg(feature = "flutter")]
pub(in super::super) fn shell_gesture_travel(
    state: &RuntimeState,
    position: Option<Point<f64, Logical>>,
) -> f64 {
    let Some(position) = position else {
        return TOUCHPAD_SHELL_GESTURE_TRAVEL;
    };
    let height = state
        .wayland
        .as_ref()
        .and_then(|frontend| {
            frontend
                .outputs
                .iter()
                .find(|output| output.logical_geometry.to_f64().contains(position))
                .or_else(|| frontend.outputs.first())
        })
        .map_or(960.0, |output| f64::from(output.logical_geometry.size.h));
    (height * TOUCHSCREEN_SHELL_GESTURE_SHARE).max(1.0)
}

#[cfg(feature = "flutter")]
const fn shell_gesture_kind(
    direction: super::super::touchpad_gestures::VerticalSwipe,
) -> super::super::wire::ShellGestureKind {
    use super::super::touchpad_gestures::VerticalSwipe;
    use super::super::wire::ShellGestureKind;
    match direction {
        VerticalSwipe::Up => ShellGestureKind::Up,
        VerticalSwipe::Down => ShellGestureKind::Down,
    }
}

/// Three fingers up or down in the full-screen apps layout: the shell's
/// overview or app windows follow them (`wire::ShellGesture`), instead of
/// opening at once when the swipe is recognized.
#[cfg(feature = "flutter")]
fn follow_vertical_swipe(
    state: &mut RuntimeState,
    gesture_event: super::super::touchpad_gestures::TouchpadGestureEvent,
    position: Option<Point<f64, Logical>>,
) -> bool {
    use super::super::touchpad_gestures::TouchpadGestureEvent;
    let source = shell_gesture_source(position);
    let full = shell_gesture_travel(state, position);
    match gesture_event {
        TouchpadGestureEvent::VerticalBegin { direction, travel } => {
            // As for the overview opened by a key: a constrained pointer (a
            // game's) is let go while the shell's view is up. Not inside
            // begin_shell_gesture, which a pointer grab calls.
            if state
                .shell_gestures
                .active()
                .is_none_or(|(_, active)| active == source)
            {
                let _ = prepare_shell_overlay_action(state, position);
            }
            begin_shell_gesture(
                state,
                source,
                shell_gesture_kind(direction),
                travel / full,
                position,
            )
        }
        TouchpadGestureEvent::VerticalUpdate {
            travel, velocity, ..
        } => update_shell_gesture(state, source, travel / full, velocity / full),
        TouchpadGestureEvent::VerticalEnd {
            cancelled: true, ..
        } => cancel_shell_gesture(state, Some(source), "the swipe was cancelled"),
        TouchpadGestureEvent::VerticalEnd {
            travel,
            velocity,
            committed,
            ..
        } => end_shell_gesture(state, source, travel / full, velocity / full, committed),
        _ => false,
    }
}

/// `source` starts a shell gesture toward `kind`; `position`: where on the
/// touchscreen, if there. A gesture of another source under way keeps the
/// shell. True: the input was the gesture's.
///
/// It must not touch the seat's pointer: the middle-button drag calls it
/// from its pointer grab, while smithay holds the pointer's lock, and
/// asking the pointer for its focus there deadlocks the compositor. Callers
/// outside a grab release a constrained pointer first
/// ([`prepare_shell_overlay_action`]); the middle-button drag never starts
/// while an app holds the pointer.
#[cfg(feature = "flutter")]
pub(in super::super) fn begin_shell_gesture(
    state: &mut RuntimeState,
    source: super::super::shell_gestures::ShellGestureSource,
    kind: super::super::wire::ShellGestureKind,
    progress: f64,
    position: Option<Point<f64, Logical>>,
) -> bool {
    let Some(gesture) = state.shell_gestures.begin(source, kind, progress) else {
        info!(
            ?source,
            ?kind,
            "full-screen apps gesture ignored: another one drives the shell"
        );
        return true;
    };
    info!(
        ?source,
        ?kind,
        progress = gesture.progress,
        "full-screen apps gesture follows"
    );
    state.queue_shell_gesture(gesture);
    true
}

#[cfg(feature = "flutter")]
pub(in super::super) fn update_shell_gesture(
    state: &mut RuntimeState,
    source: super::super::shell_gestures::ShellGestureSource,
    progress: f64,
    velocity: f64,
) -> bool {
    if let Some(gesture) = state.shell_gestures.update(source, progress, velocity) {
        state.queue_shell_gesture(gesture);
    }
    true
}

#[cfg(feature = "flutter")]
pub(in super::super) fn end_shell_gesture(
    state: &mut RuntimeState,
    source: super::super::shell_gestures::ShellGestureSource,
    progress: f64,
    velocity: f64,
    committed: bool,
) -> bool {
    if let Some(gesture) = state
        .shell_gestures
        .end(source, progress, velocity, committed)
    {
        info!(
            ?source,
            kind = ?gesture.kind,
            committed,
            progress = gesture.progress,
            velocity = gesture.velocity,
            "full-screen apps gesture ended"
        );
        state.queue_shell_gesture(gesture);
    }
    true
}

/// Abandons the shell gesture of `source`, or any (`None`), telling the
/// shell to settle its view back where it was before the gesture.
#[cfg(feature = "flutter")]
pub(in super::super) fn cancel_shell_gesture(
    state: &mut RuntimeState,
    source: Option<super::super::shell_gestures::ShellGestureSource>,
    reason: &str,
) -> bool {
    if let Some(gesture) = state.shell_gestures.cancel(source) {
        info!(
            ?source,
            kind = ?gesture.kind,
            reason,
            "full-screen apps gesture cancelled"
        );
        state.queue_shell_gesture(gesture);
    }
    true
}

/// Settles what a reset of the touchpad's swipes cut short: a strip moving
/// with the fingers snaps back, a shell gesture is cancelled.
#[cfg(feature = "flutter")]
fn settle_touchpad_swipe_reset(state: &mut RuntimeState, reason: &str) {
    let reset = state.touchpad_gestures.reset();
    if reset.horizontal_scrolling {
        finish_horizontal_layout_scroll(state, true, None);
    }
    if reset.vertical {
        cancel_shell_gesture(
            state,
            Some(super::super::shell_gestures::ShellGestureSource::Touchpad),
            reason,
        );
    }
}

/// The full-screen apps layout answers swipes itself, whatever the user's
/// shortcuts say, as the scrolling layout does for three fingers left and
/// right: up opens the screens overview, down the app windows, four fingers
/// up the launcher, and the other swipes do nothing.
#[cfg(feature = "flutter")]
fn dispatch_screens_gesture(
    state: &mut RuntimeState,
    gesture_event: super::super::touchpad_gestures::TouchpadGestureEvent,
    position: Option<Point<f64, Logical>>,
) -> bool {
    use super::super::touchpad_gestures::{ScreensGesture, TouchpadGestureEvent, screens_gesture};

    let gesture = match gesture_event {
        TouchpadGestureEvent::Trigger(gesture) => gesture,
        // The swipe was answered when it was recognized.
        TouchpadGestureEvent::Repeat(_) | TouchpadGestureEvent::End(_) => return true,
        TouchpadGestureEvent::HorizontalScrollBegin { .. }
        | TouchpadGestureEvent::HorizontalScrollUpdate { .. }
        | TouchpadGestureEvent::HorizontalScrollEnd { .. }
        | TouchpadGestureEvent::VerticalBegin { .. }
        | TouchpadGestureEvent::VerticalUpdate { .. }
        | TouchpadGestureEvent::VerticalEnd { .. } => return false,
    };
    let route = screens_gesture(gesture);
    info!(?gesture, ?route, "full-screen apps gesture");
    match route {
        ScreensGesture::Overview => {
            execute_shortcut_disposition_at(state, ShortcutDisposition::RequestOverview, position)
        }
        ScreensGesture::AppWindows => {
            let monitor_id = prepare_shell_overlay_action(state, position);
            state.queue_shell_action(super::super::wire::ShellAction::AppWindows, monitor_id);
            true
        }
        ScreensGesture::Launcher => execute_shortcut_disposition_at(
            state,
            ShortcutDisposition::RequestApplications,
            position,
        ),
        ScreensGesture::Nothing => true,
    }
}

#[cfg(feature = "flutter")]
/// `direct`: fingers on the touchscreen rather than a touchpad.
fn update_horizontal_layout_scroll(state: &mut RuntimeState, delta_x: f64, direct: bool) -> bool {
    let Some(frame) = state
        .wayland
        .as_mut()
        .and_then(|frontend| frontend.scroll_layout_horizontally(delta_x, direct))
    else {
        return false;
    };
    let changed = !frame.placements.is_empty();
    for (window, geometry) in frame.placements {
        super::window_management::queue_transient_window_placement_for_monitor(
            state,
            &window,
            geometry,
            frame.monitor_geometry,
            WindowPlacementPhase::Update,
            WindowPlacementChange::Move,
        );
    }
    if changed {
        state.scene_sync.mark_dirty();
    }
    changed
}

/// A middle-button drag moves the full-screen apps layout's strip by
/// `delta_x` logical px, exactly with the pointer.
#[cfg(feature = "flutter")]
pub(in super::super) fn middle_drag_moves_strip(state: &mut RuntimeState, delta_x: f64) -> bool {
    update_horizontal_layout_scroll(state, delta_x, true)
}

/// A middle-button drag that moved the strip ended: it settles on the
/// screen `projected_delta_x` reaches, or goes back where it was
/// (`cancelled`).
#[cfg(feature = "flutter")]
pub(in super::super) fn middle_drag_releases_strip(
    state: &mut RuntimeState,
    cancelled: bool,
    projected_delta_x: f64,
) -> bool {
    finish_horizontal_layout_scroll_from(state, cancelled, Some(projected_delta_x), true)
}

#[cfg(feature = "flutter")]
fn update_mouse_wheel_layout_scroll(state: &mut RuntimeState, vertical_delta: f64) -> bool {
    let Some(frame) = state
        .wayland
        .as_mut()
        .and_then(|frontend| frontend.scroll_layout_with_mouse_wheel(vertical_delta))
    else {
        return false;
    };
    let changed = !frame.placements.is_empty();
    for (window, geometry) in frame.placements {
        super::window_management::queue_transient_window_placement_for_monitor(
            state,
            &window,
            geometry,
            frame.monitor_geometry,
            WindowPlacementPhase::Update,
            WindowPlacementChange::Move,
        );
    }
    if changed {
        state.scene_sync.mark_dirty();
    }
    changed
}

#[cfg(feature = "flutter")]
fn finish_horizontal_layout_scroll(
    state: &mut RuntimeState,
    cancelled: bool,
    projected_delta_x: Option<f64>,
) -> bool {
    finish_horizontal_layout_scroll_from(state, cancelled, projected_delta_x, false)
}

#[cfg(feature = "flutter")]
fn finish_horizontal_layout_scroll_from(
    state: &mut RuntimeState,
    cancelled: bool,
    projected_delta_x: Option<f64>,
    direct: bool,
) -> bool {
    let Some(frame) = state.wayland.as_mut().and_then(|frontend| {
        frontend.finish_layout_horizontal_scroll(cancelled, projected_delta_x, direct)
    }) else {
        return false;
    };
    let selected = frame.selected.clone();
    let changed = !frame.placements.is_empty();
    for (window, geometry) in frame.placements {
        super::window_management::queue_transient_window_placement_for_monitor(
            state,
            &window,
            geometry,
            frame.monitor_geometry,
            WindowPlacementPhase::End,
            WindowPlacementChange::Move,
        );
    }
    if !cancelled && let Some(selected) = selected {
        super::window_management::activate_window(state, &selected, SERIAL_COUNTER.next_serial());
    }
    if changed {
        state.scene_sync.mark_dirty();
    }
    changed
}

fn process_input_event(
    state: &mut RuntimeState,
    mut event: InputEvent<LibinputInputBackend>,
) -> bool {
    let mut tablet_clients_changed = false;
    #[cfg(feature = "flutter")]
    let device_kinds = state.input_devices.kinds();
    if let InputEvent::DeviceAdded { device } = &mut event {
        tablet_clients_changed = tablet::register_device(state, device);
        #[cfg(feature = "flutter")]
        if Device::has_capability(device, DeviceCapability::Touch) {
            state
                .input_devices
                .touchscreens
                .insert(device.sysname().to_owned(), device.clone());
        }
        if Device::has_capability(device, DeviceCapability::Keyboard) {
            if let Some(led_state) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_keyboard())
                .map(|keyboard| keyboard.led_state())
            {
                device.led_update(led_state.into());
            }
            state
                .input_devices
                .keyboards
                .insert(device.sysname().to_owned(), device.clone());
            #[cfg(feature = "flutter")]
            if is_typing_keyboard(device) {
                let physical = is_physical_keyboard_bus(input_device_bus(device));
                info!(device = %device.name(), physical, "a keyboard to type on is attached");
                state
                    .input_devices
                    .typing_keyboards
                    .insert(device.sysname().to_owned());
                if physical {
                    state
                        .input_devices
                        .physical_keyboards
                        .insert(device.sysname().to_owned());
                }
            }
        }
        #[cfg(feature = "flutter")]
        if lid_switch::ignored_under_closed_lid(lid_device_traits(device)) {
            info!(device = %device.name(), "ignored while the lid is closed");
            state
                .input_devices
                .lid_covered
                .insert(device.sysname().to_owned());
        }
        let touchpad = is_touchpad_device(device);
        if touchpad {
            let settings = state
                .wayland
                .as_ref()
                .map(|frontend| frontend.settings.touchpad().clone())
                .unwrap_or_default();
            // libinput recognizes taps and emits ordinary BTN_LEFT transitions.
            // Keeping recognition at the device boundary lets synthesized
            // clicks use the same Flutter/Wayland focus and grab path as
            // physical buttons.
            if let Err(error) = configure_touchpad_device(device, &settings) {
                warn!(%error, "could not apply persisted touchpad settings");
            }
            #[cfg(feature = "flutter")]
            state
                .input_devices
                .touchpads
                .insert(device.sysname().to_owned(), device.clone());
        }
        let mouse = is_mouse_device(device);
        if mouse {
            let settings = state
                .wayland
                .as_ref()
                .map(|frontend| frontend.settings.mouse().clone())
                .unwrap_or_default();
            if let Err(error) = configure_mouse_device(device, &settings) {
                warn!(%error, "could not apply persisted mouse settings");
            }
            #[cfg(feature = "flutter")]
            state
                .input_devices
                .mice
                .insert(device.sysname().to_owned(), device.clone());
        }
        #[cfg(feature = "flutter")]
        {
            state.input_device_capabilities_changed |= state.input_devices.kinds() != device_kinds;
        }
    }

    if let InputEvent::DeviceRemoved { device } = &event {
        #[cfg(feature = "flutter")]
        state.power_button.remove_device(device.sysname());
        tablet_clients_changed = tablet::unregister_device(state, device);
        #[cfg(feature = "flutter")]
        if state
            .input_devices
            .typing_keyboards
            .contains(device.sysname())
        {
            info!(device = %device.name(), "a keyboard to type on is detached");
        }
        state.input_devices.remove(device.sysname());
        #[cfg(feature = "flutter")]
        {
            state.screen_off_touch.remove_device(device.sysname());
            state.input_device_capabilities_changed |= state.input_devices.kinds() != device_kinds;
        }
        let reset = InputDeviceReset {
            keyboard: Device::has_capability(device, DeviceCapability::Keyboard),
            pointer: Device::has_capability(device, DeviceCapability::Pointer),
            touch: Device::has_capability(device, DeviceCapability::Touch),
        };
        if reset.any() {
            reset_input_devices(state, reset);
        }
        return reset.any() || tablet_clients_changed;
    }

    // While the lid is closed the built-in touchscreen and pen reach neither
    // the shell nor a client, and they are no activity: they neither light
    // the screen nor restart the idle timer.
    #[cfg(feature = "flutter")]
    if state.lid.closed()
        && input_event_device(&event)
            .is_some_and(|device| state.input_devices.lid_covered.contains(device.sysname()))
    {
        return false;
    }

    #[cfg(feature = "flutter")]
    if let InputEvent::Keyboard {
        event: key_event, ..
    } = &event
    {
        // KEY_POWER (116) plus the XKB offset. Handle the entire physical key
        // sequence before note_user_activity: waking first would invert an
        // off-to-on toggle, and routing the release would undo on-to-off.
        // Power plus Volume Down is the mobile shell's screenshot.
        let chords = state
            .wayland
            .as_ref()
            .is_some_and(|frontend| frontend.mobile_shell);
        // KEY_WAKEUP (143) wakes the built-in panel and reaches no client.
        if key_event.key_code().raw() == 143 + 8 {
            state.wake_key_pressed |= key_event.state() == KeyState::Pressed;
            return false;
        }
        if key_event.key_code().raw() == 116 + 8 {
            state.power_button.note_key(
                key_event.device().sysname(),
                key_event.state() == KeyState::Pressed,
                chords,
                std::time::Instant::now(),
            );
            return false;
        }
        // KEY_VOLUMEDOWN (114).
        if key_event.key_code().raw() == 114 + 8 {
            use super::super::idle_policy::VolumeDownRoute;
            let keycode = key_event.key_code();
            match state
                .power_button
                .note_volume_down(key_event.state() == KeyState::Pressed, chords)
            {
                VolumeDownRoute::Deliver => {}
                VolumeDownRoute::Take => return false,
                VolumeDownRoute::HoldBack => {
                    hold_back_volume_down(state, keycode);
                    return false;
                }
                VolumeDownRoute::DeliverHeldPress => {
                    let time = key_event.time();
                    let pressed =
                        process_keyboard_transition(state, keycode, KeyState::Pressed, time);
                    return process_keyboard_transition(state, keycode, KeyState::Released, time)
                        || pressed;
                }
            }
        }
        return process_keyboard_transition(
            state,
            key_event.key_code(),
            key_event.state(),
            key_event.time(),
        );
    }

    #[cfg(feature = "flutter")]
    {
        use crate::screen_off_touch::Event as TouchPowerEvent;
        let touch = match &event {
            InputEvent::TouchDown { event, .. } => Some((
                event.device(),
                TouchPowerEvent::Down(i32::from(event.slot())),
            )),
            InputEvent::TouchMotion { event, .. } => Some((
                event.device(),
                TouchPowerEvent::Motion(i32::from(event.slot())),
            )),
            InputEvent::TouchUp { event, .. } => {
                Some((event.device(), TouchPowerEvent::Up(i32::from(event.slot()))))
            }
            InputEvent::TouchCancel { event, .. } => {
                Some((event.device(), TouchPowerEvent::Cancel))
            }
            InputEvent::TouchFrame { event, .. } => Some((event.device(), TouchPowerEvent::Frame)),
            _ => None,
        };
        if let Some((device, touch)) = touch {
            let powered = state
                .wayland
                .as_ref()
                .and_then(|frontend| touch_output_for_device(frontend, &device))
                .is_none_or(|output| {
                    state
                        .output_power_requests
                        .get(&output.id)
                        .copied()
                        .unwrap_or(output.powered)
                });
            // The root fingerprint listener has its own read-only evdev stream.
            // Only its bounded presentation or an explicit wake gesture/button
            // may wake this panel; raw DOWN/MOTION must not expose the lock UI.
            if state
                .screen_off_touch
                .suppress(device.sysname(), touch, powered)
            {
                return false;
            }
        }
    }

    #[cfg(feature = "flutter")]
    if state.fingerprint.active()
        && matches!(
            &event,
            InputEvent::TouchDown { .. }
                | InputEvent::TouchMotion { .. }
                | InputEvent::TouchUp { .. }
                | InputEvent::TouchCancel { .. }
                | InputEvent::TouchFrame { .. }
        )
    {
        return false;
    }

    // libinput's own event type has an inherent `switch()`; ask Smithay's.
    #[cfg(feature = "flutter")]
    if let InputEvent::SwitchToggle { event } = &event
        && SwitchToggleEvent::switch(event) == Some(Switch::Lid)
    {
        let closed = SwitchToggleEvent::state(event) == SwitchState::On;
        if !closed
            && state
                .system_controls
                .as_ref()
                .and_then(crate::system_controls::SystemControls::logind_lid_closed)
                == Some(true)
        {
            // libinput synthesizes LIBINPUT_SWITCH_LID=OFF whenever a paired
            // internal keyboard sends a key event, even though the hardware
            // Hall switch is still closed. Re-check with logind in case the
            // property signal is still in flight, without waking the display
            // or re-enabling covered input prematurely.
            state.lid.request_reading();
            info!("ignored libinput lid-open while logind still reports the lid closed");
            return false;
        }
        let was_closed = state.lid.closed();
        state.lid.note_toggle(closed);
        if closed && !was_closed {
            // End the touches under way: their lift comes from a touchscreen
            // the closed lid silences.
            reset_input_devices(
                state,
                InputDeviceReset {
                    keyboard: false,
                    pointer: false,
                    touch: true,
                },
            );
            info!("the lid closed: covered built-in inputs are ignored until it opens");
            return true;
        }
        if !closed {
            // Opening the lid asks to see the panel, as a key press would.
            state.note_user_activity();
        }
        return false;
    }

    #[cfg(feature = "flutter")]
    if !matches!(&event, InputEvent::DeviceAdded { .. }) {
        state.note_user_activity();
    }

    // New windows open where the user last pressed: the phone or a desk.
    #[cfg(feature = "flutter")]
    if let Some(frontend) = state.wayland.as_mut() {
        let output = match &event {
            InputEvent::TouchDown { event, .. } => {
                touch_output_for_device(frontend, &event.device()).map(|output| output.id)
            }
            InputEvent::PointerButton { event, .. }
                if event.state() == smithay::backend::input::ButtonState::Pressed =>
            {
                frontend.output_id_at(frontend.pointer_location)
            }
            _ => None,
        };
        frontend.note_press_output(output);
        if matches!(&event, InputEvent::TouchDown { .. })
            && output.is_some_and(|output| state.idle_policy.phone_output() == Some(output))
        {
            state
                .idle_policy
                .note_phone_touch(std::time::Instant::now());
        }
    }

    #[cfg(feature = "flutter")]
    if let Some(flush_clients) = process_touchpad_gesture_event(state, &event) {
        return flush_clients;
    }

    // Touchpad pinches and holds go to the client under the pointer; the
    // swipes, deniald's own, were taken above.
    if let Some(flush_clients) = process_client_gesture(state, &event) {
        return flush_clients;
    }

    if tablet::process_event(state, &event) {
        return true;
    }

    if tablet_clients_changed {
        return true;
    }

    #[cfg(not(feature = "flutter"))]
    match &event {
        InputEvent::Keyboard {
            event: key_event, ..
        } if intercept_native_escape(state, key_event.key_code().raw(), key_event.state()) => {
            // Native window actions may emit configure/focus messages. This
            // edge is infrequent, so retain the conservative immediate flush.
            return true;
        }
        _ => {}
    }

    #[cfg(feature = "flutter")]
    if let InputEvent::PointerButton { event, .. } = &event
        && event.state() == ButtonState::Pressed
    {
        note_mac_keys_pointer_button(state);
    }

    #[cfg(feature = "flutter")]
    if state.flutter_active {
        return process_flutter_input_event(state, event);
    }

    #[cfg(feature = "flutter")]
    if state.secure_session_locked() {
        // Native lock state remains authoritative if Flutter is restarting or
        // unavailable. No physical input may fall through to a client.
        return true;
    }

    process_wayland_input_event(state, event);
    true
}

pub(in super::super) fn reset_all_input_devices(state: &mut RuntimeState) {
    #[cfg(feature = "flutter")]
    {
        state.power_button = Default::default();
    }
    reset_input_devices(state, InputDeviceReset::ALL);
}

#[cfg(feature = "flutter")]
pub(in super::super) fn reset_touch_input_devices(state: &mut RuntimeState) {
    reset_input_devices(
        state,
        InputDeviceReset {
            keyboard: false,
            pointer: false,
            touch: true,
        },
    );
}

#[cfg(feature = "flutter")]
pub(in super::super) fn install_keyboard_settings(
    state: &mut RuntimeState,
    settings: &KeyboardSettings,
) -> Result<Vec<String>, Box<dyn Error>> {
    let layout_names = settings.compiled_layout_names()?;
    let names = settings.xkb_names();
    let (layout, variant) = keymap_layouts_with_typing_layouts(
        &names.layout,
        &names.variant,
        &state.frontend().shell_typing_layouts,
    );
    // Retire every key against the old map before replacing it. A later
    // physical release is consumed, so neither Flutter nor a client can keep
    // a modifier logically held across the keymap boundary.
    reset_input_devices(
        state,
        InputDeviceReset {
            keyboard: true,
            pointer: false,
            touch: false,
        },
    );
    let keyboard = state
        .wayland
        .as_ref()
        .and_then(|frontend| frontend.seat.get_keyboard())
        .ok_or("seat has no keyboard")?;
    let with_typing_layouts = keyboard.set_xkb_config(
        state,
        XkbConfig {
            rules: "evdev",
            model: "pc105",
            layout: &layout,
            variant: &variant,
            options: Some(names.options.clone()),
        },
    );
    if let Err(error) = with_typing_layouts {
        if layout == names.layout {
            return Err(error.into());
        }
        // The configured layouts compile: the software keyboard's own
        // layouts must not cost the hardware keyboard its keymap.
        warn!(
            %error,
            layouts = %layout,
            "keymap without the software keyboard's layouts, which do not compile"
        );
        keyboard.set_xkb_config(
            state,
            XkbConfig {
                rules: "evdev",
                model: "pc105",
                layout: &names.layout,
                variant: &names.variant,
                options: Some(names.options),
            },
        )?;
    }
    keyboard.change_repeat_info(
        i32::try_from(settings.repeat_rate_hz)?,
        i32::try_from(settings.repeat_delay_ms)?,
    );
    #[cfg(feature = "flutter")]
    {
        let altgr = right_alt_types(state, &keyboard);
        state.mac_keys.set_right_alt_is_command(!altgr);
    }
    {
        let frontend = state.frontend_mut();
        #[cfg(feature = "flutter")]
        if let Some(compose) = frontend.flutter_compose.as_mut() {
            compose.reset();
        }
        frontend.keyboard_layout_names = layout_names.clone();
        frontend.active_keyboard_layout = 0;
        frontend.keyboard_configuration_changed = true;
    }
    super::input_method::refresh_keyboard_grab(
        state,
        i32::try_from(settings.repeat_rate_hz)?,
        i32::try_from(settings.repeat_delay_ms)?,
    );
    Ok(layout_names)
}

/// Whether Right Alt types in a layout of the keymap: AltGr
/// (ISO_Level3_Shift) or Mode_switch. The Mac preset then leaves it alone.
#[cfg(feature = "flutter")]
fn right_alt_types(state: &mut RuntimeState, keyboard: &KeyboardHandle<RuntimeState>) -> bool {
    keyboard.with_xkb_state(state, |context| {
        let xkb = context.xkb().lock().unwrap();
        // SAFETY: the keymap reference is used only while the owning XKB
        // mutex is held and is not retained beyond this closure.
        let keymap = unsafe { xkb.keymap() };
        let right_alt = Keycode::new(mac_keys::KEY_RIGHTALT + 8);
        (0..keymap.num_layouts_for_key(right_alt)).any(|layout| {
            keymap
                .key_get_syms_by_level(right_alt, layout, 0)
                .iter()
                .any(|&sym| {
                    matches!(
                        xkb::keysym_get_name(sym).as_str(),
                        "ISO_Level3_Shift" | "Mode_switch"
                    )
                })
        })
    })
}

/// An X server's keymap holds four layouts at most.
#[cfg(feature = "flutter")]
const MAX_KEYMAP_LAYOUTS: usize = 4;

/// XKB layout and variant lists: the configured `layout` and `variant`,
/// then each of `typing` that no configured layout is named, as long as the
/// keymap has room. The software keyboard types with those; layout cycling
/// and the shell never see them.
#[cfg(feature = "flutter")]
fn keymap_layouts_with_typing_layouts(
    layout: &str,
    variant: &str,
    typing: &[String],
) -> (String, String) {
    let configured = layout.split(',').collect::<Vec<_>>();
    let mut layouts = layout.to_owned();
    let mut variants = variant.to_owned();
    let mut count = configured.len();
    for name in typing {
        if count >= MAX_KEYMAP_LAYOUTS {
            break;
        }
        if configured.contains(&name.as_str()) {
            continue;
        }
        layouts.push(',');
        layouts.push_str(name);
        variants.push(',');
        count += 1;
    }
    (layouts, variants)
}

/// Gives the keymap a layout for each layout the shell keyboard's letter
/// pages are made for: compiles it again when they change, the active
/// layout kept.
#[cfg(feature = "flutter")]
fn set_shell_typing_layouts(state: &mut RuntimeState, layouts: &[String]) -> bool {
    let settings = state.frontend().settings.keyboard().clone();
    let names = settings.xkb_names();
    let keymap_before = keymap_layouts_with_typing_layouts(
        &names.layout,
        &names.variant,
        &state.frontend().shell_typing_layouts,
    );
    let previous = std::mem::replace(
        &mut state.frontend_mut().shell_typing_layouts,
        layouts.to_vec(),
    );
    // Layouts the configuration already has change nothing.
    if keymap_layouts_with_typing_layouts(&names.layout, &names.variant, layouts) == keymap_before {
        return true;
    }
    let active = state.frontend().active_keyboard_layout;
    if let Err(error) = install_keyboard_settings(state, &settings) {
        warn!(%error, "could not install the keymap for the software keyboard's layouts");
        state.frontend_mut().shell_typing_layouts = previous;
        return false;
    }
    info!(layouts = %layouts.join(","), "software keyboard layouts");
    if active != 0 {
        select_keyboard_layout(state, u32::try_from(active).unwrap_or(0));
    }
    true
}

fn reset_input_devices(state: &mut RuntimeState, reset: InputDeviceReset) {
    // End direct-touch shortcut lifecycles before a seat-wide reset clears
    // their shortcut owner; otherwise the window switcher cannot finish.
    #[cfg(feature = "flutter")]
    if reset.touch {
        super::input_deck::cancel_screen_gestures(state);
        let actions = state
            .wayland
            .as_mut()
            .map(|frontend| frontend.touch_gestures.cancel_all())
            .unwrap_or_default();
        touch_gestures::apply_actions(state, actions);
        // A finger holding a divider lifts no more: settle the drag, so the
        // slot is free for the next finger.
        if let Some(drag) = state
            .wayland
            .as_mut()
            .and_then(|frontend| frontend.touch_dividers.release_all())
        {
            flutter_route::end_touch_divider(state, drag);
        }
    }
    if reset.keyboard {
        state.native_escape_shortcut.reset();
        #[cfg(feature = "flutter")]
        {
            cancel_flutter_repeat(state);
            // The keys the Mac preset holds go with the device's.
            state.mac_keys.reset();
            if let Some(keyboard) = state
                .wayland
                .as_ref()
                .and_then(|frontend| frontend.seat.get_keyboard())
            {
                keyboard.release_source(state, mac_keys_source());
            }
            super::focus::restore_keyboard_focus_after_switcher(state);
        }
    }
    #[cfg(feature = "flutter")]
    if reset.pointer {
        settle_touchpad_swipe_reset(state, "the pointer devices were reset");
        state.native_escape_shortcut.cancel_gestures();
    }
    if reset.pointer {
        // libinput ends no gesture of a device it removed or suspended.
        cancel_client_gesture(state, InputTime::now());
    }
    #[cfg(feature = "flutter")]
    if state.flutter_active {
        state
            .flutter_input
            .cancel_device_lifecycles(reset.pointer, reset.touch);
    }
    let Some(frontend) = state.wayland.as_mut() else {
        return;
    };
    let time = InputTime::now();
    let pointer = reset
        .pointer
        .then(|| frontend.seat.get_pointer().expect("seat has no pointer"));
    let touch = reset
        .touch
        .then(|| frontend.seat.get_touch().expect("seat has no touch"));
    let keyboard = reset
        .keyboard
        .then(|| frontend.seat.get_keyboard().expect("seat has no keyboard"));
    let mut pointer_buttons = if reset.pointer {
        let mut buttons = std::mem::take(&mut frontend.wayland_pointer_buttons)
            .into_iter()
            .collect::<Vec<_>>();
        buttons.sort_unstable();
        #[cfg(feature = "flutter")]
        {
            frontend.client_pointer_capture = None;
            frontend.pointer_constraint_escape.reset();
            frontend.client_pointer_buttons.clear();
            frontend.client_pointer_presses.clear();
            frontend.flutter_pointer_press = None;
            frontend.set_clipboard_drag_active(false);
            frontend.retired_pointer_buttons.clear();
            frontend.set_routed_pointer_target(RoutedPointerTarget::Flutter);
        }
        buttons
    } else {
        Vec::new()
    };
    #[cfg(feature = "flutter")]
    let cancel_client_touch = reset.touch
        && (!frontend.client_touch_routes.is_empty()
            || touch.as_ref().is_some_and(|touch| touch.is_grabbed()));
    #[cfg(not(feature = "flutter"))]
    let cancel_client_touch = reset.touch;
    if reset.touch {
        #[cfg(feature = "flutter")]
        {
            frontend.flutter_touch_slots.clear();
            frontend.client_touch_routes.clear();
            frontend.client_touch_frame_pending = false;
        }
    }

    #[cfg(feature = "flutter")]
    if reset.keyboard {
        frontend.shell_keyboard_keys.clear();
    }
    let previously_retired_keys = if reset.keyboard {
        frontend.retired_keyboard_keys.clone()
    } else {
        HashSet::new()
    };
    if let Some(keyboard) = keyboard.as_ref() {
        for keycode in keyboard.pressed_keys() {
            frontend.retired_keyboard_keys.insert(keycode.raw());
        }
    }
    if let Some(pointer) = pointer {
        let had_buttons = !pointer_buttons.is_empty();
        let had_grab = pointer.is_grabbed();
        for button in pointer_buttons.drain(..) {
            pointer.button(
                state,
                &ButtonEvent {
                    button,
                    state: ButtonState::Released,
                    serial: SERIAL_COUNTER.next_serial(),
                    time,
                },
            );
        }
        if pointer.is_grabbed() {
            pointer.unset_grab(state, SERIAL_COUNTER.next_serial(), time);
        }
        if had_buttons || had_grab {
            pointer.frame(state);
        }
    }

    if cancel_client_touch && let Some(touch) = touch {
        touch.cancel(state);
        if touch.is_grabbed() {
            touch.unset_grab(state);
        }
    }

    if let Some(keyboard) = keyboard {
        let mut pressed_keys = keyboard.pressed_keys().into_iter().collect::<Vec<_>>();
        pressed_keys.sort_unstable_by_key(|keycode| keycode.raw());
        for keycode in pressed_keys {
            let raw_keycode = keycode.raw();
            let was_retired = previously_retired_keys.contains(&raw_keycode);
            super::input_method::input_key(
                state,
                &keyboard,
                keycode,
                KeyState::Released,
                SERIAL_COUNTER.next_serial(),
                time,
                move |_, _, _| {
                    if was_retired {
                        FilterResult::Intercept(())
                    } else {
                        FilterResult::Forward
                    }
                },
            );
        }
        if keyboard.is_grabbed() {
            keyboard.unset_grab(state);
        }
    }
    state.scene_sync.mark_dirty();
}

#[cfg(feature = "flutter")]
fn flutter_unicode_for_keysym(
    compose: Option<&mut xkb::compose::State>,
    keysym: xkb::Keysym,
) -> u32 {
    let direct = || keysym.key_char().map(u32::from).unwrap_or(0);
    let Some(compose) = compose else {
        return direct();
    };
    match compose.feed(keysym) {
        xkb::compose::FeedResult::Ignored => direct(),
        xkb::compose::FeedResult::Accepted => match compose.status() {
            xkb::compose::Status::Nothing => direct(),
            xkb::compose::Status::Composing | xkb::compose::Status::Cancelled => 0,
            xkb::compose::Status::Composed => compose
                .utf8()
                .as_deref()
                .and_then(single_unicode_scalar)
                .or_else(|| {
                    compose
                        .keysym()
                        .and_then(|symbol| symbol.key_char().map(u32::from))
                })
                .unwrap_or(0),
        },
    }
}

#[cfg(feature = "flutter")]
fn single_unicode_scalar(value: &str) -> Option<u32> {
    let mut characters = value.chars();
    let character = characters.next()?;
    characters.next().is_none().then(|| u32::from(character))
}

#[cfg(feature = "flutter")]
fn flutter_key_repeats(key: &smithay::input::keyboard::KeysymHandle<'_>) -> bool {
    let xkb = key.xkb().lock().unwrap();
    // SAFETY: the keymap reference is used only while the owning XKB mutex is
    // held and is not retained beyond this call.
    unsafe { xkb.keymap() }.key_repeats(key.raw_code())
}

#[cfg(feature = "flutter")]
fn flutter_modifiers_for_key(
    key: &smithay::input::keyboard::KeysymHandle<'_>,
) -> smithay::input::keyboard::ModifiersState {
    let xkb = key.xkb().lock().unwrap();
    let mut modifiers = smithay::input::keyboard::ModifiersState::default();
    // SAFETY: the state reference remains inside the XKB mutex guard.
    modifiers.update_with(unsafe { xkb.state() });
    modifiers
}

/// Deliver a seat keyboard event whose real focus target is the compositor's
/// Flutter shell.
///
/// This is the sole Flutter hardware-key delivery point. Physical keys and
/// keys returned by an input method both arrive here through Smithay's seat.
#[cfg(feature = "flutter")]
pub(super) fn dispatch_focused_flutter_key(
    state: &mut RuntimeState,
    key: smithay::input::keyboard::KeysymHandle<'_>,
    key_state: KeyState,
) {
    let raw_keycode = key.raw_code().raw();
    let (dispatch, input_method_owns_repeat) = {
        let frontend = state.frontend_mut();
        let dispatch = match key_state {
            KeyState::Pressed => {
                frontend.flutter_keyboard_keys.insert(raw_keycode);
                true
            }
            KeyState::Released => frontend.flutter_keyboard_keys.remove(&raw_keycode),
        };
        (dispatch, frontend.input_method.flutter_editor_active())
    };
    if !dispatch || !state.flutter_active {
        return;
    }

    let repeatable = matches!(key_state, KeyState::Pressed) && flutter_key_repeats(&key);
    let unicode = if matches!(key_state, KeyState::Pressed) {
        let frontend = state.frontend_mut();
        flutter_unicode_for_keysym(frontend.flutter_compose.as_mut(), key.modified_sym())
    } else {
        key.modified_sym().key_char().map(u32::from).unwrap_or(0)
    };
    let modifiers = flutter_modifiers_for_key(&key);
    state
        .flutter_input
        .handle_keyboard_with_unicode(raw_keycode, key_state, &modifiers, unicode);
    if repeatable && !input_method_owns_repeat {
        start_flutter_repeat(state, raw_keycode);
    } else if matches!(key_state, KeyState::Released)
        && state
            .wayland
            .as_ref()
            .is_some_and(|frontend| frontend.flutter_repeat_key == Some(raw_keycode))
    {
        cancel_flutter_repeat(state);
    }
}

#[cfg(feature = "flutter")]
pub(super) fn leave_focused_flutter_keyboard(state: &mut RuntimeState) {
    cancel_flutter_repeat(state);
    let mut keys = {
        let frontend = state.frontend_mut();
        std::mem::take(&mut frontend.flutter_keyboard_keys)
            .into_iter()
            .collect::<Vec<_>>()
    };
    keys.sort_unstable();
    let modifiers = smithay::input::keyboard::ModifiersState::default();
    for keycode in keys {
        state.flutter_input.handle_keyboard_with_unicode(
            keycode,
            KeyState::Released,
            &modifiers,
            0,
        );
    }
}

/// How long a Volume Down press waits for Power to join it as a
/// screenshot before it changes the volume.
#[cfg(feature = "flutter")]
const SCREENSHOT_CHORD_WINDOW: std::time::Duration = std::time::Duration::from_millis(150);

#[cfg(feature = "flutter")]
fn hold_back_volume_down(state: &mut RuntimeState, keycode: Keycode) {
    let Some(frontend) = state.wayland.as_ref() else {
        return;
    };
    let loop_handle = frontend.loop_handle.clone();
    let scheduled = loop_handle.insert_source(
        Timer::from_duration(SCREENSHOT_CHORD_WINDOW),
        move |_, _, state| {
            if state.power_button.take_held_volume_down()
                && process_keyboard_transition(state, keycode, KeyState::Pressed, InputTime::now())
                && let Some(frontend) = state.wayland.as_mut()
                && let Err(error) = frontend.display_handle.flush_clients()
            {
                warn!(%error, "could not flush Wayland clients after Volume Down");
            }
            TimeoutAction::Drop
        },
    );
    if let Err(error) = scheduled {
        warn!(%error, "could not hold Volume Down back for the screenshot chord");
        if state.power_button.take_held_volume_down() {
            process_keyboard_transition(state, keycode, KeyState::Pressed, InputTime::now());
        }
    }
}

#[cfg(feature = "flutter")]
fn cancel_flutter_repeat(state: &mut RuntimeState) {
    let Some(frontend) = state.wayland.as_mut() else {
        return;
    };
    frontend.flutter_repeat_generation = frontend.flutter_repeat_generation.wrapping_add(1);
    frontend.flutter_repeat_key = None;
    if let Some(token) = frontend.flutter_repeat_token.take() {
        frontend.loop_handle.remove(token);
    }
}

#[cfg(feature = "flutter")]
fn start_flutter_repeat(state: &mut RuntimeState, keycode: u32) {
    cancel_flutter_repeat(state);
    let Some(frontend) = state.wayland.as_mut() else {
        return;
    };
    let rate = frontend.settings.keyboard().repeat_rate_hz;
    if rate == 0 {
        return;
    }
    let delay =
        std::time::Duration::from_millis(u64::from(frontend.settings.keyboard().repeat_delay_ms));
    let interval = std::time::Duration::from_secs_f64(1.0 / f64::from(rate));
    frontend.flutter_repeat_generation = frontend.flutter_repeat_generation.wrapping_add(1);
    let generation = frontend.flutter_repeat_generation;
    frontend.flutter_repeat_key = Some(keycode);
    let loop_handle = frontend.loop_handle.clone();
    match loop_handle.insert_source(Timer::from_duration(delay), move |_, _, state| {
        let current = state.wayland.as_ref().is_some_and(|frontend| {
            frontend.flutter_repeat_generation == generation
                && frontend.flutter_repeat_key == Some(keycode)
        });
        if !current || !dispatch_flutter_repeat(state, keycode) {
            return TimeoutAction::Drop;
        }
        TimeoutAction::ToDuration(interval)
    }) {
        Ok(token) => {
            state.frontend_mut().flutter_repeat_token = Some(token);
        }
        Err(error) => {
            warn!(%error, "could not schedule Flutter keyboard repeat");
            cancel_flutter_repeat(state);
        }
    }
}

#[cfg(feature = "flutter")]
fn dispatch_flutter_repeat(state: &mut RuntimeState, keycode: u32) -> bool {
    if !state.flutter_active {
        return false;
    }
    let Some(keyboard) = state
        .wayland
        .as_ref()
        .and_then(|frontend| frontend.seat.get_keyboard())
    else {
        return false;
    };
    let owned = state
        .wayland
        .as_ref()
        .is_some_and(|frontend| frontend.flutter_keyboard_keys.contains(&keycode));
    if !owned {
        return false;
    }
    let time = InputTime::now();
    super::input_method::forward_key(
        state,
        &keyboard,
        Keycode::new(keycode),
        KeyState::Pressed,
        SERIAL_COUNTER.next_serial(),
        time,
        false,
    );
    true
}

#[cfg(feature = "flutter")]
fn start_system_control_repeat(state: &mut RuntimeState, keycode: u32) {
    cancel_flutter_repeat(state);
    let Some(frontend) = state.wayland.as_mut() else {
        return;
    };
    let rate = frontend.settings.keyboard().repeat_rate_hz;
    if rate == 0 {
        return;
    }
    let delay =
        std::time::Duration::from_millis(u64::from(frontend.settings.keyboard().repeat_delay_ms));
    let interval = std::time::Duration::from_secs_f64(1.0 / f64::from(rate));
    frontend.flutter_repeat_generation = frontend.flutter_repeat_generation.wrapping_add(1);
    let generation = frontend.flutter_repeat_generation;
    frontend.flutter_repeat_key = Some(keycode);
    let loop_handle = frontend.loop_handle.clone();
    match loop_handle.insert_source(Timer::from_duration(delay), move |_, _, state| {
        let current = state.wayland.as_ref().is_some_and(|frontend| {
            frontend.flutter_repeat_generation == generation
                && frontend.flutter_repeat_key == Some(keycode)
        });
        if !current || !dispatch_system_control_repeat(state, keycode) {
            return TimeoutAction::Drop;
        }
        TimeoutAction::ToDuration(interval)
    }) {
        Ok(token) => {
            state.frontend_mut().flutter_repeat_token = Some(token);
        }
        Err(error) => {
            warn!(%error, "could not schedule system-control keyboard repeat");
            cancel_flutter_repeat(state);
        }
    }
}

#[cfg(feature = "flutter")]
fn dispatch_system_control_repeat(state: &mut RuntimeState, xkb_keycode: u32) -> bool {
    if !state.flutter_active || state.secure_session_locked() {
        return false;
    }
    let Some(evdev_keycode) = xkb_keycode.checked_sub(8) else {
        return false;
    };
    let disposition = state.native_escape_shortcut.observe(evdev_keycode, true);
    if !disposition.repeats_with_timer() {
        return false;
    }
    execute_shortcut_disposition(state, disposition)
}

fn intercept_native_escape(
    state: &mut RuntimeState,
    xkb_keycode: u32,
    key_state: KeyState,
) -> bool {
    // Smithay/XKB keycodes carry the conventional eight-code offset over the
    // Linux evdev values emitted by libinput.
    let Some(evdev_keycode) = xkb_keycode.checked_sub(8) else {
        return false;
    };
    #[cfg(feature = "flutter")]
    if key_state == KeyState::Released
        && state
            .wayland
            .as_ref()
            .is_some_and(|frontend| frontend.flutter_repeat_key == Some(xkb_keycode))
    {
        cancel_flutter_repeat(state);
    }
    let disposition = state
        .native_escape_shortcut
        .observe(evdev_keycode, key_state == KeyState::Pressed);
    // VT switching is a seat-level escape, not a client, window, or shell
    // action. Keep it available while the native lock screen owns input.
    if let ShortcutDisposition::RequestVtSwitch(vt) = &disposition {
        return execute_shortcut_disposition(state, ShortcutDisposition::RequestVtSwitch(*vt));
    }
    #[cfg(feature = "flutter")]
    if state.secure_session_locked() {
        return match disposition {
            ShortcutDisposition::Forward => false,
            ShortcutDisposition::RequestLock => {
                if let Some(authentication) = state.authentication.as_ref() {
                    authentication.lock();
                }
                true
            }
            ShortcutDisposition::RequestShutdown => {
                state
                    .lifecycle
                    .request_shutdown(ShutdownReason::NativeEscapeShortcut);
                true
            }
            // Shortcut state still observes every transition so releases stay
            // balanced, but locked sessions cannot trigger client/window or
            // system-control actions.
            _ => true,
        };
    }
    // The shortcut engine has observed the key either way, so its modifier
    // and chord state stays balanced while an app holds the shortcuts.
    if let Some(frontend) = state.wayland.as_mut() {
        let inhibit = &mut frontend.shortcuts_inhibit;
        if key_state == KeyState::Released {
            if inhibit.take_forwarded_release(xkb_keycode) {
                return false;
            }
        } else {
            let forwarded = inhibit.active() && !disposition.survives_shortcuts_inhibit();
            inhibit.note_press(xkb_keycode, forwarded);
            if forwarded {
                state.native_escape_shortcut.pass_through_key(evdev_keycode);
                return false;
            }
        }
    }
    #[cfg(feature = "flutter")]
    let repeats_system_control = key_state == KeyState::Pressed && disposition.repeats_with_timer();
    let handled = execute_shortcut_disposition(state, disposition);
    if !handled && key_state == KeyState::Pressed {
        state.native_escape_shortcut.pass_through_key(evdev_keycode);
    }
    #[cfg(feature = "flutter")]
    if handled && repeats_system_control {
        start_system_control_repeat(state, xkb_keycode);
    }
    handled
}

pub(super) fn execute_shortcut_disposition(
    state: &mut RuntimeState,
    disposition: ShortcutDisposition,
) -> bool {
    execute_shortcut_disposition_at(state, disposition, None)
}

fn execute_shortcut_disposition_at(
    state: &mut RuntimeState,
    disposition: ShortcutDisposition,
    _position: Option<Point<f64, Logical>>,
) -> bool {
    match disposition {
        ShortcutDisposition::Forward => false,
        ShortcutDisposition::Consume => true,
        ShortcutDisposition::RequestVtSwitch(vt) => {
            let result = if let Some(frontend) = state.wayland.as_mut() {
                frontend
                    .session
                    .change_vt(vt)
                    .map_err(|error| error.to_string())
            } else {
                Err("Wayland frontend is unavailable".to_owned())
            };
            match result {
                Ok(()) => info!(vt, "requested virtual terminal switch"),
                Err(error) => warn!(%error, vt, "could not switch virtual terminal"),
            }
            true
        }
        ShortcutDisposition::RequestShutdown => {
            state
                .lifecycle
                .request_shutdown(ShutdownReason::NativeEscapeShortcut);
            true
        }
        ShortcutDisposition::PluginAction(id) => {
            #[cfg(feature = "flutter")]
            if state.secure_session_locked() {
                return false;
            }
            state.plugin_actions.queue(id, None)
        }
        ShortcutDisposition::RequestApplications => {
            #[cfg(feature = "flutter")]
            if state.secure_session_locked() {
                return false;
            }
            state
                .plugin_actions
                .queue(crate::plugin_actions::LEGACY_LAUNCHER_ACTION.into(), None)
        }
        ShortcutDisposition::RequestDashboard => {
            #[cfg(feature = "flutter")]
            state.queue_shell_action(super::super::wire::ShellAction::Dashboard, None);
            true
        }
        ShortcutDisposition::RequestOverview => {
            #[cfg(feature = "flutter")]
            {
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(super::super::wire::ShellAction::Overview, monitor_id);
            }
            true
        }
        direction @ (ShortcutDisposition::RequestPreviousWorkspace
        | ShortcutDisposition::RequestNextWorkspace) => {
            #[cfg(feature = "flutter")]
            {
                let delta = if matches!(direction, ShortcutDisposition::RequestPreviousWorkspace) {
                    -1
                } else {
                    1
                };
                let Some(monitor_id) = prepare_shell_overlay_action(state, _position) else {
                    return false;
                };
                let target = state
                    .wayland
                    .as_ref()
                    .and_then(|frontend| frontend.adjacent_workspace(monitor_id, delta));
                let Some(target) = target else {
                    return false;
                };
                return super::window_management::switch_monitor_workspace(
                    state, monitor_id, target,
                );
            }
            #[cfg(not(feature = "flutter"))]
            false
        }
        ShortcutDisposition::RequestSwitchWorkspace(workspace_id) => {
            #[cfg(feature = "flutter")]
            {
                let Some(monitor_id) = prepare_shell_overlay_action(state, _position) else {
                    return false;
                };
                return super::window_management::switch_monitor_workspace(
                    state,
                    monitor_id,
                    workspace_id,
                );
            }
            #[cfg(not(feature = "flutter"))]
            false
        }
        direction @ (ShortcutDisposition::RequestMoveToPreviousWorkspace
        | ShortcutDisposition::RequestMoveToNextWorkspace) => {
            #[cfg(feature = "flutter")]
            {
                let delta = if matches!(
                    direction,
                    ShortcutDisposition::RequestMoveToPreviousWorkspace
                ) {
                    -1
                } else {
                    1
                };
                let Some((window_id, monitor_id)) =
                    super::window_management::focused_workspace_window(state)
                else {
                    return false;
                };
                let target = state
                    .wayland
                    .as_ref()
                    .and_then(|frontend| frontend.adjacent_workspace(monitor_id, delta));
                let Some(target) = target else {
                    return false;
                };
                return super::window_management::move_window_to_workspace(
                    state, window_id, None, target, true,
                );
            }
            #[cfg(not(feature = "flutter"))]
            false
        }
        ShortcutDisposition::RequestMoveToWorkspace(workspace_id) => {
            #[cfg(feature = "flutter")]
            {
                let Some((window_id, _)) =
                    super::window_management::focused_workspace_window(state)
                else {
                    return false;
                };
                return super::window_management::move_window_to_workspace(
                    state,
                    window_id,
                    None,
                    workspace_id,
                    true,
                );
            }
            #[cfg(not(feature = "flutter"))]
            false
        }
        ShortcutDisposition::RequestResize(action) => {
            #[cfg(feature = "flutter")]
            super::window_management::resize_focused_toplevel(state, action);
            #[cfg(not(feature = "flutter"))]
            let _ = action;
            true
        }
        ShortcutDisposition::RequestToggleVerticalMaximize => {
            #[cfg(feature = "flutter")]
            super::window_management::toggle_shell_vertical_maximize_focused_toplevel(state);
            true
        }
        ShortcutDisposition::RequestFocus(direction) => {
            #[cfg(feature = "flutter")]
            {
                let shell_owns_scene = state
                    .wayland
                    .as_ref()
                    .and_then(|frontend| frontend.input_layout.as_ref())
                    .is_some_and(InputLayoutSnapshot::exclusive_shell);
                if shell_owns_scene {
                    let action = match direction {
                        LayoutDirection::Left => super::super::wire::ShellAction::FocusLeft,
                        LayoutDirection::Right => super::super::wire::ShellAction::FocusRight,
                        LayoutDirection::Up => super::super::wire::ShellAction::FocusUp,
                        LayoutDirection::Down => super::super::wire::ShellAction::FocusDown,
                    };
                    state.queue_shell_action(action, None);
                    true
                } else {
                    super::window_management::focus_toplevel_in_direction(state, direction);
                    true
                }
            }
            #[cfg(not(feature = "flutter"))]
            false
        }
        ShortcutDisposition::RequestSwap(direction) => {
            #[cfg(feature = "flutter")]
            super::window_management::swap_toplevel_in_direction(state, direction);
            true
        }
        ShortcutDisposition::RequestWindowSwitcherNext => {
            #[cfg(feature = "flutter")]
            {
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(
                    super::super::wire::ShellAction::WindowSwitcherNext,
                    monitor_id,
                );
            }
            true
        }
        ShortcutDisposition::RequestWindowSwitcherPrevious => {
            #[cfg(feature = "flutter")]
            {
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(
                    super::super::wire::ShellAction::WindowSwitcherPrevious,
                    monitor_id,
                );
            }
            true
        }
        ShortcutDisposition::RequestWindowSwitcherEnd { forward } => {
            #[cfg(feature = "flutter")]
            state.queue_shell_action(super::super::wire::ShellAction::WindowSwitcherEnd, None);
            !forward
        }
        ShortcutDisposition::RequestAppSwitcher(step) => {
            #[cfg(feature = "flutter")]
            {
                // The app switcher is the desktop's; the tablet's keys go to
                // the app.
                if state.shell_presentation != DesktopPresentation::Desktop {
                    return false;
                }
                if app_saw_a_held_modifier(state) {
                    super::focus::park_keyboard_focus_for_switcher(state);
                }
                let action = match step {
                    AppSwitcherStep::Next => super::super::wire::ShellAction::AppSwitcherNext,
                    AppSwitcherStep::Previous => {
                        super::super::wire::ShellAction::AppSwitcherPrevious
                    }
                    AppSwitcherStep::WindowNext => {
                        super::super::wire::ShellAction::AppSwitcherWindowNext
                    }
                    AppSwitcherStep::WindowPrevious => {
                        super::super::wire::ShellAction::AppSwitcherWindowPrevious
                    }
                };
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(action, monitor_id);
            }
            #[cfg(not(feature = "flutter"))]
            let _ = step;
            true
        }
        ShortcutDisposition::RequestAppSwitcherEnd { forward } => {
            #[cfg(feature = "flutter")]
            state.queue_shell_action(super::super::wire::ShellAction::AppSwitcherEnd, None);
            !forward
        }
        ShortcutDisposition::RequestAppSwitcherCancel => {
            #[cfg(feature = "flutter")]
            state.queue_shell_action(super::super::wire::ShellAction::AppSwitcherCancel, None);
            true
        }
        ShortcutDisposition::RequestSearch => {
            #[cfg(feature = "flutter")]
            {
                if state.shell_presentation != DesktopPresentation::Desktop {
                    return false;
                }
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(super::super::wire::ShellAction::Search, monitor_id);
            }
            true
        }
        ShortcutDisposition::RequestHideApplication => {
            #[cfg(feature = "flutter")]
            super::window_management::minimize_focused_application(state);
            true
        }
        ShortcutDisposition::RequestCaptureScreen => {
            #[cfg(feature = "flutter")]
            {
                state.screenshot_requested = true;
            }
            true
        }
        ShortcutDisposition::RequestAppWindows => {
            #[cfg(feature = "flutter")]
            {
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(super::super::wire::ShellAction::AppWindows, monitor_id);
            }
            true
        }
        ShortcutDisposition::RequestClipboard => {
            #[cfg(feature = "flutter")]
            {
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.queue_shell_action(super::super::wire::ShellAction::Clipboard, monitor_id);
            }
            true
        }
        ShortcutDisposition::RequestScreenshotRegion => {
            #[cfg(feature = "flutter")]
            {
                let monitor_id = prepare_shell_overlay_action(state, _position);
                state.request_screenshot_selection(monitor_id);
            }
            true
        }
        ShortcutDisposition::RequestMinimize => {
            #[cfg(feature = "flutter")]
            super::window_management::minimize_focused_toplevel(state);
            true
        }
        ShortcutDisposition::RequestMinimizeAll => {
            #[cfg(feature = "flutter")]
            super::window_management::minimize_all_toplevels(state);
            true
        }
        ShortcutDisposition::RequestClose => {
            #[cfg(feature = "flutter")]
            super::window_management::close_focused_toplevel(state);
            true
        }
        ShortcutDisposition::RequestToggleMaximize => {
            #[cfg(feature = "flutter")]
            super::window_management::toggle_shell_maximize_focused_toplevel(state);
            true
        }
        ShortcutDisposition::RequestToggleFullscreen => {
            #[cfg(feature = "flutter")]
            super::window_management::toggle_shell_fullscreen_focused_toplevel(state);
            true
        }
        ShortcutDisposition::RequestToggleWindowAlwaysOnTop => {
            #[cfg(feature = "flutter")]
            super::window_management::toggle_always_on_top_focused_toplevel(state);
            true
        }
        ShortcutDisposition::RequestReleasePointer => {
            if let Some(frontend) = state.wayland.as_mut() {
                frontend.suspend_shortcuts_inhibit();
            }
            #[cfg(feature = "flutter")]
            release_pointer_to_shell(state);
            true
        }
        ShortcutDisposition::RequestLock => {
            #[cfg(feature = "flutter")]
            if let Some(authentication) = state.authentication.as_ref() {
                authentication.lock();
            }
            true
        }
        ShortcutDisposition::RequestVolumeUp => {
            if let Some(controls) = state.system_controls.as_ref() {
                controls.volume_up();
            }
            true
        }
        ShortcutDisposition::RequestVolumeDown => {
            if let Some(controls) = state.system_controls.as_ref() {
                controls.volume_down();
            }
            true
        }
        ShortcutDisposition::RequestMute => {
            if let Some(controls) = state.system_controls.as_ref() {
                controls.toggle_mute();
            }
            true
        }
        ShortcutDisposition::RequestBrightnessUp => {
            adjust_brightness_for_pointer_output(state, true);
            true
        }
        ShortcutDisposition::RequestBrightnessDown => {
            adjust_brightness_for_pointer_output(state, false);
            true
        }
        ShortcutDisposition::RequestNextKeyboardLayout => {
            cycle_keyboard_layout(state, true);
            true
        }
        ShortcutDisposition::RequestPreviousKeyboardLayout => {
            cycle_keyboard_layout(state, false);
            true
        }
        ShortcutDisposition::RequestOpenSettings => {
            #[cfg(feature = "flutter")]
            state.queue_shell_action(super::super::wire::ShellAction::OpenSettings, None);
            true
        }
        ShortcutDisposition::Spawn {
            command,
            desktop_file_id,
        } => {
            #[cfg(feature = "flutter")]
            state
                .pending_shortcut_launches
                .push_back(ShortcutTarget::Spawn {
                    command,
                    desktop_file_id,
                });
            true
        }
        ShortcutDisposition::SpawnSh(command) => {
            #[cfg(feature = "flutter")]
            state
                .pending_shortcut_launches
                .push_back(ShortcutTarget::SpawnSh { command });
            true
        }
    }
}

/// The layouts the configuration lists. The keymap may hold more after
/// them, for the software keyboard alone.
fn configured_keyboard_layouts(state: &RuntimeState) -> usize {
    state
        .wayland
        .as_ref()
        .map_or(1, |frontend| frontend.keyboard_layout_names.len())
        .max(1)
}

/// The configured layout after `active` in one direction, round the list.
fn next_configured_layout(active: usize, count: usize, forward: bool) -> usize {
    match (active < count, forward) {
        (true, true) => (active + 1) % count,
        (true, false) => (active + count - 1) % count,
        (false, true) => 0,
        (false, false) => count - 1,
    }
}

/// The configured layout an XKB group action means when it reached
/// `active`, one of the software keyboard's layouts after the configured
/// ones: on past the last configured layout to the first, or back from the
/// first to the last.
fn configured_layout_after_group_action(active: usize, previous: usize, count: usize) -> usize {
    if active < count {
        active
    } else if previous + 1 >= count {
        0
    } else {
        count - 1
    }
}

fn cycle_keyboard_layout(state: &mut RuntimeState, forward: bool) {
    let Some(keyboard) = state
        .wayland
        .as_ref()
        .and_then(|frontend| frontend.seat.get_keyboard())
    else {
        return;
    };
    // Only configured layouts: the software keyboard's own come after them.
    let count = configured_keyboard_layouts(state);
    let active = keyboard.with_xkb_state(state, |mut context| {
        let active = context.xkb().lock().unwrap().active_layout().0 as usize;
        let next = next_configured_layout(active, count, forward);
        context.set_layout(smithay::input::keyboard::Layout(next as u32));
        context.xkb().lock().unwrap().active_layout().0 as usize
    });
    publish_active_keyboard_layout(state, active);
}

/// Makes `layout`, one of the configured layouts, the active one, as
/// Super+Space does: the software keyboard's language key. The shell hears
/// of it as of a switch on a hardware keyboard.
#[cfg(feature = "flutter")]
fn select_keyboard_layout(state: &mut RuntimeState, layout: u32) -> bool {
    let Some(keyboard) = state
        .wayland
        .as_ref()
        .and_then(|frontend| frontend.seat.get_keyboard())
    else {
        return false;
    };
    let count = configured_keyboard_layouts(state);
    if usize::try_from(layout).map_or(true, |layout| layout >= count) {
        warn!(
            layout,
            "ignored a keyboard layout the configuration does not have"
        );
        return false;
    }
    let active = keyboard.with_xkb_state(state, |mut context| {
        context.set_layout(smithay::input::keyboard::Layout(layout));
        context.xkb().lock().unwrap().active_layout().0 as usize
    });
    publish_active_keyboard_layout(state, active);
    true
}

fn synchronize_active_keyboard_layout(
    state: &mut RuntimeState,
    keyboard: &KeyboardHandle<RuntimeState>,
) {
    // A shell-keyboard key that lends itself another layout for a stroke
    // switches back before it returns.
    #[cfg(feature = "flutter")]
    if state
        .wayland
        .as_ref()
        .is_some_and(|frontend| frontend.shell_keyboard_borrows_layout)
    {
        return;
    }
    let count = configured_keyboard_layouts(state);
    let previous = state
        .wayland
        .as_ref()
        .map_or(0, |frontend| frontend.active_keyboard_layout);
    let active = keyboard.with_xkb_state(state, |mut context| {
        let active = context.xkb().lock().unwrap().active_layout().0 as usize;
        // An XKB option such as grp:alt_shift_toggle steps through every
        // layout of the keymap; the software keyboard's are skipped.
        let configured = configured_layout_after_group_action(active, previous, count);
        if configured != active {
            context.set_layout(smithay::input::keyboard::Layout(configured as u32));
        }
        context.xkb().lock().unwrap().active_layout().0 as usize
    });
    publish_active_keyboard_layout(state, active);
}

fn publish_active_keyboard_layout(state: &mut RuntimeState, active: usize) {
    let Some(frontend) = state.wayland.as_mut() else {
        return;
    };
    if frontend.active_keyboard_layout == active {
        return;
    }
    frontend.active_keyboard_layout = active;
    frontend.keyboard_configuration_changed = true;
    let name = frontend
        .keyboard_layout_names
        .get(active)
        .map(String::as_str)
        .unwrap_or("unknown");
    info!(
        layout_index = active,
        layout_name = name,
        "switched keyboard layout"
    );
}

#[cfg(feature = "flutter")]
fn release_pointer_to_shell(state: &mut RuntimeState) {
    let Some(pointer) = state
        .wayland
        .as_ref()
        .and_then(|frontend| frontend.seat.get_pointer())
    else {
        return;
    };
    let focused_surface = pointer.current_focus();
    let released_window_id = focused_surface.as_ref().and_then(|surface| {
        state
            .wayland
            .as_ref()
            .and_then(|frontend| frontend.window_id_for_input_surface(surface))
    });
    let had_constraint = focused_surface.as_ref().is_some_and(|surface| {
        with_pointer_constraint(surface, &pointer, |constraint| {
            let Some(constraint) = constraint else {
                return false;
            };
            constraint.deactivate();
            true
        })
    });

    let (mut pressed_buttons, time) = {
        let frontend = state.frontend_mut();
        if let Some(window_id) = released_window_id {
            frontend.pointer_constraint_escape.release_window(window_id);
        }
        frontend.client_pointer_capture = None;
        frontend.client_pointer_buttons.clear();
        frontend.client_pointer_presses.clear();
        frontend.flutter_pointer_press = None;
        frontend.set_clipboard_drag_active(false);
        let mut pressed_buttons = std::mem::take(&mut frontend.wayland_pointer_buttons)
            .into_iter()
            .collect::<Vec<_>>();
        pressed_buttons.sort_unstable();
        frontend
            .retired_pointer_buttons
            .extend(pressed_buttons.iter().copied());
        frontend.update_cursor_image(CursorImageStatus::default_named());
        (pressed_buttons, InputTime::now())
    };

    let had_grab = pointer.is_grabbed();
    for button in pressed_buttons.drain(..) {
        pointer.button(
            state,
            &ButtonEvent {
                button,
                state: ButtonState::Released,
                serial: SERIAL_COUNTER.next_serial(),
                time,
            },
        );
    }
    if pointer.is_grabbed() {
        pointer.unset_grab(state, SERIAL_COUNTER.next_serial(), time);
    }
    if had_grab || !state.frontend().retired_pointer_buttons.is_empty() {
        pointer.frame(state);
    }
    state.scene_sync.mark_dirty();
    info!(
        window_id = ?released_window_id,
        had_constraint,
        had_grab,
        "released pointer capture until the client is clicked again"
    );
}

#[cfg(feature = "flutter")]
fn prepare_shell_overlay_action(
    state: &mut RuntimeState,
    position: Option<Point<f64, Logical>>,
) -> Option<i64> {
    let pointer = state
        .wayland
        .as_ref()
        .and_then(|frontend| frontend.seat.get_pointer());
    let focused_surface = pointer.as_ref().and_then(PointerHandle::current_focus);
    let released_constraint = match (pointer, focused_surface) {
        (Some(pointer), Some(surface)) => {
            with_pointer_constraint(&surface, &pointer, |constraint| {
                let Some(constraint) = constraint else {
                    return false;
                };
                if !constraint.is_active() {
                    return false;
                }
                constraint.deactivate();
                true
            })
        }
        _ => false,
    };
    if released_constraint {
        if let Some(frontend) = state.wayland.as_mut() {
            frontend.update_cursor_image(CursorImageStatus::default_named());
        }
        state.scene_sync.mark_dirty();
    }

    let pointer_monitor = state
        .wayland
        .as_ref()
        .and_then(WaylandFrontend::control_output_under_pointer)
        .map(|(_, monitor_id)| monitor_id);
    let touch_monitor = position.and_then(|position| {
        state
            .wayland
            .as_ref()?
            .outputs
            .iter()
            .find(|output| output.logical_geometry.to_f64().contains(position))
            .and_then(|output| i64::try_from(output.id.0).ok())
    });
    touch_monitor
        .or(pointer_monitor)
        .or_else(|| super::window_management::focused_workspace_window(state).map(|(_, id)| id))
        .or_else(|| {
            let frontend = state.wayland.as_ref()?;
            frontend
                .ticker_output
                .or_else(|| frontend.outputs.first().map(|output| output.id))
                .and_then(|output| i64::try_from(output.0).ok())
        })
}

fn adjust_brightness_for_pointer_output(state: &RuntimeState, increase: bool) {
    let Some((connector, monitor_id)) = state
        .wayland
        .as_ref()
        .and_then(WaylandFrontend::control_output_under_pointer)
    else {
        warn!("brightness shortcut has no output under the pointer");
        return;
    };
    let Some(controls) = state.system_controls.as_ref() else {
        return;
    };
    if increase {
        controls.brightness_up(connector.to_owned(), monitor_id);
    } else {
        controls.brightness_down(connector.to_owned(), monitor_id);
    }
}

#[cfg(feature = "flutter")]
fn process_flutter_keyboard_transition(
    state: &mut RuntimeState,
    keycode: Keycode,
    key_state: KeyState,
    time: InputTime,
    source: KeyboardSource,
) -> bool {
    let secure_locked = state.secure_session_locked();
    let keyboard = state
        .frontend()
        .seat
        .get_keyboard()
        .expect("seat has no keyboard");
    // A device reset retires physical keys only.
    let consume_retired = source == KeyboardSource::MAIN && {
        let frontend = state.frontend_mut();
        retired_key_consumes_transition(
            &mut frontend.retired_keyboard_keys,
            keycode.raw(),
            key_state,
        )
    };
    let secure_route_invalid = secure_locked
        && !matches!(
            keyboard.current_focus(),
            Some(super::focus::KeyboardFocusTarget::Flutter)
        );
    super::input_method::input_key_from(
        state,
        &keyboard,
        source,
        keycode,
        key_state,
        SERIAL_COUNTER.next_serial(),
        time,
        move |_, _, _| {
            if consume_retired || secure_route_invalid {
                FilterResult::Intercept(())
            } else {
                FilterResult::Forward
            }
        },
    );
    synchronize_active_keyboard_layout(state, &keyboard);
    true
}

#[cfg(all(test, feature = "flutter"))]
mod shell_text_stroke_tests {
    use super::*;

    fn keymap(layouts: &str) -> xkb::Keymap {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        xkb::Keymap::new_from_names(
            &context,
            "evdev",
            "pc105",
            layouts,
            "",
            None,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .expect("xkeyboard-config compiles the layouts")
    }

    /// The evdev key, its Shift and the layout that type `character`.
    fn planned(keymap: &xkb::Keymap, active: u32, character: char) -> Option<(u32, bool, u32)> {
        plan_shell_text_stroke(keymap, active, character).map(|planned| {
            (
                planned.stroke.evdev_keycode,
                planned.stroke.shift,
                planned.layout,
            )
        })
    }

    #[test]
    fn a_us_keymap_types_ascii_with_the_keys_it_always_did() {
        let us = keymap("us");
        let mut covered = 0;
        for character in ' '..='~' {
            let Some(stroke) = shell_text_key_stroke(character) else {
                continue;
            };
            covered += 1;
            assert_eq!(
                planned(&us, 0, character),
                Some((stroke.evdev_keycode, stroke.shift, 0)),
                "{character:?}"
            );
        }
        assert_eq!(covered, 95);
    }

    #[test]
    fn russian_letters_type_on_their_keys_of_the_russian_layout() {
        let keymap = keymap("us,ru");
        // ЙЦУКЕН lies on the QWERTY keys from Q, A and Z on.
        for (row, first) in [("йцукенгшщзхъ", 16), ("фывапролджэ", 30), ("ячсмитьбю", 44)]
        {
            for (offset, letter) in (0..).zip(row.chars()) {
                let key = first + offset;
                let capital = letter.to_uppercase().next().unwrap();
                assert_eq!(
                    planned(&keymap, 1, letter),
                    Some((key, false, 1)),
                    "{letter}"
                );
                assert_eq!(
                    planned(&keymap, 1, capital),
                    Some((key, true, 1)),
                    "{capital}"
                );
                // While English is active the key borrows the Russian layout.
                assert_eq!(
                    planned(&keymap, 0, letter),
                    Some((key, false, 1)),
                    "{letter}"
                );
                assert_eq!(
                    planned(&keymap, 0, capital),
                    Some((key, true, 1)),
                    "{capital}"
                );
            }
        }
        assert_eq!(planned(&keymap, 0, 'ё'), Some((41, false, 1)));
        assert_eq!(planned(&keymap, 1, 'Ё'), Some((41, true, 1)));
    }

    #[test]
    fn the_active_layout_types_what_it_has_and_borrows_the_rest() {
        let keymap = keymap("us,ru");
        // Russian has the full stop and the comma on the slash key.
        assert_eq!(planned(&keymap, 1, '.'), Some((53, false, 1)));
        assert_eq!(planned(&keymap, 1, ','), Some((53, true, 1)));
        assert_eq!(planned(&keymap, 1, ' '), Some((57, false, 1)));
        assert_eq!(planned(&keymap, 1, '1'), Some((2, false, 1)));
        assert_eq!(planned(&keymap, 1, '?'), Some((8, true, 1)));
        // It has no @ and no Latin letters.
        assert_eq!(planned(&keymap, 1, '@'), Some((3, true, 0)));
        assert_eq!(planned(&keymap, 1, 'q'), Some((16, false, 0)));
        assert_eq!(planned(&keymap, 1, 'Q'), Some((16, true, 0)));
        assert_eq!(planned(&keymap, 0, ','), Some((51, false, 0)));
        assert_eq!(planned(&keymap, 0, '?'), Some((53, true, 0)));
    }

    #[test]
    fn letters_come_from_the_keymap_not_from_us_positions() {
        let german = keymap("de");
        assert_eq!(planned(&german, 0, 'z'), Some((21, false, 0)));
        assert_eq!(planned(&german, 0, 'y'), Some((44, false, 0)));
        assert_eq!(planned(&german, 0, 'Y'), Some((44, true, 0)));
    }

    #[test]
    fn a_character_no_layout_types_is_left_to_the_fallbacks() {
        assert_eq!(planned(&keymap("us"), 0, 'й'), None);
        assert_eq!(planned(&keymap("us,ru"), 1, 'ä'), None);
    }

    fn typing(layouts: &[&str]) -> Vec<String> {
        layouts.iter().map(|layout| (*layout).to_owned()).collect()
    }

    #[test]
    fn the_keymap_adds_only_typing_layouts_the_configuration_lacks() {
        let with = |layout, variant, layouts: &[&str]| {
            keymap_layouts_with_typing_layouts(layout, variant, &typing(layouts))
        };
        // No software-keyboard layouts: the configured keymap, untouched.
        assert_eq!(with("us", "", &[]), ("us".into(), "".into()));
        assert_eq!(with("us", "", &["us"]), ("us".into(), "".into()));
        assert_eq!(with("us", "", &["us", "ru"]), ("us,ru".into(), ",".into()));
        assert_eq!(
            with("us,ru", ",", &["us", "ru"]),
            ("us,ru".into(), ",".into())
        );
        // A configured variant of the layout serves.
        assert_eq!(
            with("ru,us", "phonetic,", &["us", "ru"]),
            ("ru,us".into(), "phonetic,".into())
        );
        assert_eq!(
            with("de", "nodeadkeys", &["us", "ru"]),
            ("de,us,ru".into(), "nodeadkeys,,".into())
        );
        // Never more than four layouts.
        assert_eq!(
            with("de,fr,it", ",,", &["us", "ru"]),
            ("de,fr,it,us".into(), ",,,".into())
        );
        assert_eq!(
            with("de,fr,it,es", ",,,", &["us", "ru"]),
            ("de,fr,it,es".into(), ",,,".into())
        );
    }

    #[test]
    fn a_keymap_with_typing_layouts_compiles_and_keeps_the_configured_order() {
        let (layout, variant) =
            keymap_layouts_with_typing_layouts("us", "", &typing(&["us", "ru"]));
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        let keymap = xkb::Keymap::new_from_names(
            &context,
            "evdev",
            "pc105",
            &layout,
            &variant,
            None,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .expect("compiles");
        assert_eq!(keymap.num_layouts(), 2);
        assert_eq!(keymap.layout_get_name(0), "English (US)");
        assert_eq!(keymap.layout_get_name(1), "Russian");
        // English stays active; Russian letters borrow the added layout.
        assert_eq!(planned(&keymap, 0, 'ж'), Some((39, false, 1)));
        assert_eq!(planned(&keymap, 0, 'q'), Some((16, false, 0)));
    }

    #[test]
    fn only_text_on_us_keys_of_the_active_layout_skips_the_editor() {
        let on_us_keys = |keymap: &xkb::Keymap, active, text: &str| {
            let planned = text
                .chars()
                .map(|character| (character, plan_shell_text_stroke(keymap, active, character)))
                .collect::<Vec<_>>();
            types_on_us_keys(active, &planned)
        };
        let us = keymap("us");
        assert!(on_us_keys(&us, 0, "Hello, world? 1+1=2"));
        assert!(!on_us_keys(&us, 0, "perché"));
        let us_ru = keymap("us,ru");
        assert!(on_us_keys(&us_ru, 0, "Hello, world?"));
        // A Russian letter borrows the Russian layout.
        assert!(!on_us_keys(&us_ru, 0, "привет"));
        // Russian active: its letters and the marks it moves are off the
        // US keys, digits and the space are on them.
        assert!(!on_us_keys(&us_ru, 1, "привет"));
        assert!(!on_us_keys(&us_ru, 1, ","));
        assert!(!on_us_keys(&us_ru, 1, "q"));
        assert!(on_us_keys(&us_ru, 1, "1 2"));
    }

    #[test]
    fn layout_cycling_steps_through_the_configured_layouts_only() {
        assert_eq!(next_configured_layout(0, 1, true), 0);
        assert_eq!(next_configured_layout(0, 1, false), 0);
        assert_eq!(next_configured_layout(0, 2, true), 1);
        assert_eq!(next_configured_layout(1, 2, true), 0);
        assert_eq!(next_configured_layout(0, 2, false), 1);
        assert_eq!(next_configured_layout(2, 3, true), 0);
        assert_eq!(next_configured_layout(1, 3, false), 0);
        // From a software keyboard's layout, should one be active.
        assert_eq!(next_configured_layout(2, 2, true), 0);
        assert_eq!(next_configured_layout(2, 2, false), 1);
    }

    #[test]
    fn a_group_action_into_a_typing_layout_lands_on_a_configured_one() {
        // Configured layouts stay as they are.
        assert_eq!(configured_layout_after_group_action(1, 0, 2), 1);
        assert_eq!(configured_layout_after_group_action(0, 1, 2), 0);
        // On from the last configured layout: round to the first.
        assert_eq!(configured_layout_after_group_action(2, 1, 2), 0);
        assert_eq!(configured_layout_after_group_action(1, 0, 1), 0);
        // Back from the first: XKB wraps to the keymap's last layout.
        assert_eq!(configured_layout_after_group_action(3, 0, 2), 1);
        assert_eq!(configured_layout_after_group_action(3, 0, 3), 2);
    }

    #[test]
    fn keypad_keys_are_never_chosen() {
        const KEYPAD: [u32; 18] = [
            55, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 96, 98, 117, 121,
        ];
        let keymap = keymap("us,ru");
        for character in "+-*/.,=0123456789".chars() {
            for active in [0, 1] {
                let (key, ..) = planned(&keymap, active, character).expect("typeable");
                assert!(
                    !KEYPAD.contains(&key),
                    "{character} with layout {active} on {key}"
                );
            }
        }
    }
}

#[cfg(all(test, feature = "flutter"))]
mod typing_keyboard_tests {
    use super::*;

    const KEY_ESC: u32 = 1;
    const KEY_ENTER: u32 = 28;
    const KEY_Q: u32 = 16;
    const KEY_M: u32 = 50;
    const KEY_SPACE: u32 = 57;
    const KEY_VOLUMEDOWN: u32 = 114;
    const KEY_VOLUMEUP: u32 = 115;
    const KEY_POWER: u32 = 116;
    const KEY_WAKEUP: u32 = 143;
    const KEY_PLAYPAUSE: u32 = 164;

    fn keys(codes: &[u32]) -> impl Fn(u32) -> bool + '_ {
        move |key| codes.contains(&key)
    }

    #[test]
    fn power_volume_and_media_keys_are_no_keyboard_to_type_on() {
        // pmic_pwrkey, gpio-keys and a media remote.
        assert!(!has_typing_keys(keys(&[KEY_POWER])));
        assert!(!has_typing_keys(keys(&[KEY_VOLUMEUP, KEY_VOLUMEDOWN])));
        assert!(!has_typing_keys(keys(&[KEY_POWER, KEY_WAKEUP])));
        assert!(!has_typing_keys(keys(&[
            KEY_PLAYPAUSE,
            KEY_VOLUMEUP,
            KEY_VOLUMEDOWN,
            KEY_ENTER,
        ])));
    }

    #[test]
    fn a_keyboard_needs_every_letter_the_space_bar_and_enter() {
        let full = (KEY_ESC..=KEY_SPACE).collect::<Vec<_>>();
        assert!(has_typing_keys(keys(&full)));
        for missing in [KEY_Q, KEY_M, KEY_SPACE, KEY_ENTER] {
            let partial = full
                .iter()
                .copied()
                .filter(|key| *key != missing)
                .collect::<Vec<_>>();
            assert!(!has_typing_keys(keys(&partial)), "without key {missing}");
        }
        // udev's own test, Esc to D, is not enough without the other letters.
        assert!(!has_typing_keys(keys(&(KEY_ESC..=32).collect::<Vec<_>>())));
    }

    #[test]
    fn virtual_keyboards_are_not_physical() {
        // The cover (BUS_HOST), USB, Bluetooth through uhid, I2C.
        for bus in [0x19, 0x03, 0x05, 0x18] {
            assert!(is_physical_keyboard_bus(Some(bus)), "bus {bus:#x}");
        }
        // erhai test keyboard and other uinput devices.
        assert!(!is_physical_keyboard_bus(Some(BUS_VIRTUAL)));
        // An unreadable bus counts as physical, as before this distinction.
        assert!(is_physical_keyboard_bus(None));
    }
}
