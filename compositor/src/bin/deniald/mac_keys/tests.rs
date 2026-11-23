use std::collections::HashSet;

use super::*;

const KEY_C: u32 = 46;
const KEY_V: u32 = 47;
const KEY_1: u32 = 2;
const KEY_F4: u32 = 62;
const KEY_TAB: u32 = 15;

fn ordinary() -> KeyContext {
    KeyContext::default()
}

fn terminal() -> KeyContext {
    KeyContext {
        client: ClientKind::Terminal,
        ..KeyContext::default()
    }
}

fn consumed() -> KeyContext {
    KeyContext {
        consumed: true,
        ..KeyContext::default()
    }
}

fn raw() -> KeyContext {
    KeyContext {
        raw: true,
        ..KeyContext::default()
    }
}

fn mac() -> MacKeys {
    let mut keys = MacKeys::default();
    assert!(keys.set_enabled(true).is_empty());
    keys
}

fn p(key: u32, pressed: bool) -> KeyEvent {
    KeyEvent::physical(key, pressed)
}

fn s(key: u32, pressed: bool) -> KeyEvent {
    KeyEvent::synthetic(key, pressed)
}

#[test]
fn with_the_preset_off_every_key_passes_as_it_is() {
    let mut keys = MacKeys::default();
    assert_eq!(
        keys.key(KEY_LEFTALT, true, ordinary()),
        [p(KEY_LEFTALT, true)]
    );
    assert_eq!(keys.key(KEY_C, true, ordinary()), [p(KEY_C, true)]);
    assert_eq!(keys.key(KEY_C, false, ordinary()), [p(KEY_C, false)]);
    assert_eq!(keys.key(KEY_LEFT, true, terminal()), [p(KEY_LEFT, true)]);
    assert_eq!(keys.key(KEY_LEFT, false, terminal()), [p(KEY_LEFT, false)]);
    assert_eq!(
        keys.key(KEY_LEFTALT, false, ordinary()),
        [p(KEY_LEFTALT, false)]
    );
    // Super belongs to the shortcut engine, as before.
    assert!(keys.key(KEY_LEFTMETA, true, consumed()).is_empty());
    assert_eq!(keys.key(KEY_LEFT, true, ordinary()), [p(KEY_LEFT, true)]);
    assert_eq!(keys.key(KEY_LEFT, false, ordinary()), [p(KEY_LEFT, false)]);
    assert!(keys.key(KEY_LEFTMETA, false, ordinary()).is_empty());
}

#[test]
fn command_letters_reach_apps_with_ctrl() {
    let mut keys = mac();
    assert!(keys.key(KEY_LEFTALT, true, ordinary()).is_empty());
    assert_eq!(
        keys.key(KEY_C, true, ordinary()),
        [s(KEY_LEFTCTRL, true), p(KEY_C, true)]
    );
    assert_eq!(keys.key(KEY_C, false, ordinary()), [p(KEY_C, false)]);
    assert_eq!(keys.key(KEY_V, true, ordinary()), [p(KEY_V, true)]);
    assert_eq!(keys.key(KEY_V, false, ordinary()), [p(KEY_V, false)]);
    assert_eq!(
        keys.key(KEY_LEFTALT, false, ordinary()),
        [s(KEY_LEFTCTRL, false)]
    );
}

#[test]
fn terminals_get_ctrl_shift_letters_and_plain_ctrl_punctuation() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, terminal());
    assert_eq!(
        keys.key(KEY_C, true, terminal()),
        [
            s(KEY_LEFTCTRL, true),
            s(KEY_LEFTSHIFT, true),
            p(KEY_C, true)
        ]
    );
    keys.key(KEY_C, false, terminal());
    // ⌘= zooms: terminals take Ctrl+= as other apps do.
    assert_eq!(
        keys.key(KEY_EQUAL, true, terminal()),
        [s(KEY_LEFTSHIFT, false), p(KEY_EQUAL, true)]
    );
    keys.key(KEY_EQUAL, false, terminal());
    assert_eq!(
        keys.key(KEY_LEFTALT, false, terminal()),
        [s(KEY_LEFTCTRL, false)]
    );
}

#[test]
fn command_alone_reaches_no_app() {
    let mut keys = mac();
    assert!(keys.key(KEY_LEFTALT, true, ordinary()).is_empty());
    assert!(keys.key(KEY_LEFTALT, false, ordinary()).is_empty());
    assert!(keys.key(KEY_RIGHTALT, true, ordinary()).is_empty());
    assert!(keys.key(KEY_RIGHTALT, false, ordinary()).is_empty());
}

#[test]
fn releasing_command_before_the_letter_leaves_nothing_held() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    keys.key(KEY_C, true, ordinary());
    // The letter goes up with ⌘, so the app neither keeps Ctrl nor repeats
    // a bare "c".
    assert_eq!(
        keys.key(KEY_LEFTALT, false, ordinary()),
        [p(KEY_C, false), s(KEY_LEFTCTRL, false)]
    );
    assert!(keys.key(KEY_C, false, ordinary()).is_empty());
    // The next press is a plain letter.
    assert_eq!(keys.key(KEY_C, true, ordinary()), [p(KEY_C, true)]);
}

#[test]
fn command_arrows_move_to_the_line_and_text_ends() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    assert_eq!(keys.key(KEY_LEFT, true, ordinary()), [s(KEY_HOME, true)]);
    assert_eq!(keys.key(KEY_LEFT, false, ordinary()), [s(KEY_HOME, false)]);
    assert_eq!(keys.key(KEY_RIGHT, true, ordinary()), [s(KEY_END, true)]);
    keys.key(KEY_RIGHT, false, ordinary());
    assert_eq!(
        keys.key(KEY_UP, true, ordinary()),
        [s(KEY_LEFTCTRL, true), s(KEY_HOME, true)]
    );
    keys.key(KEY_UP, false, ordinary());
    assert_eq!(keys.key(KEY_DOWN, true, ordinary()), [s(KEY_END, true)]);
    keys.key(KEY_DOWN, false, ordinary());
    assert_eq!(
        keys.key(KEY_LEFTALT, false, ordinary()),
        [s(KEY_LEFTCTRL, false)]
    );
}

#[test]
fn shift_is_kept_to_select() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    assert_eq!(
        keys.key(KEY_LEFTSHIFT, true, ordinary()),
        [p(KEY_LEFTSHIFT, true)]
    );
    // Shift+Home: selects to the line's start.
    assert_eq!(keys.key(KEY_LEFT, true, ordinary()), [s(KEY_HOME, true)]);
    keys.key(KEY_LEFT, false, ordinary());
    // Ctrl+Shift+Z: redo.
    assert_eq!(
        keys.key(44, true, ordinary()),
        [s(KEY_LEFTCTRL, true), p(44, true)]
    );
}

#[test]
fn command_backspace_deletes_to_the_line_start() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    assert_eq!(
        keys.key(KEY_BACKSPACE, true, ordinary()),
        [
            s(KEY_LEFTSHIFT, true),
            s(KEY_HOME, true),
            s(KEY_HOME, false),
            s(KEY_LEFTSHIFT, false),
            p(KEY_BACKSPACE, true),
        ]
    );
    assert_eq!(
        keys.key(KEY_BACKSPACE, false, ordinary()),
        [p(KEY_BACKSPACE, false)]
    );
    assert_eq!(
        keys.key(KEY_DELETE, true, ordinary()),
        [
            s(KEY_LEFTSHIFT, true),
            s(KEY_END, true),
            s(KEY_END, false),
            s(KEY_LEFTSHIFT, false),
            p(KEY_DELETE, true),
        ]
    );
}

#[test]
fn terminals_edit_lines_as_readline_does() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, terminal());
    assert_eq!(
        keys.key(KEY_LEFT, true, terminal()),
        [s(KEY_LEFTCTRL, true), s(KEY_A, true)]
    );
    assert_eq!(keys.key(KEY_LEFT, false, terminal()), [s(KEY_A, false)]);
    assert_eq!(keys.key(KEY_RIGHT, true, terminal()), [s(KEY_E, true)]);
    keys.key(KEY_RIGHT, false, terminal());
    assert_eq!(keys.key(KEY_BACKSPACE, true, terminal()), [s(KEY_U, true)]);
    keys.key(KEY_BACKSPACE, false, terminal());
    assert_eq!(keys.key(KEY_DELETE, true, terminal()), [s(KEY_K, true)]);
    keys.key(KEY_DELETE, false, terminal());
    keys.key(KEY_LEFTALT, false, terminal());

    keys.key(
        KEY_LEFTMETA,
        true,
        KeyContext {
            consumed: true,
            ..terminal()
        },
    );
    assert_eq!(
        keys.key(KEY_LEFT, true, terminal()),
        [s(KEY_LEFTALT, true), s(KEY_B, true)]
    );
    keys.key(KEY_LEFT, false, terminal());
    assert_eq!(keys.key(KEY_RIGHT, true, terminal()), [s(KEY_F, true)]);
    keys.key(KEY_RIGHT, false, terminal());
    assert_eq!(
        keys.key(KEY_BACKSPACE, true, terminal()),
        [s(KEY_LEFTALT, false), s(KEY_LEFTCTRL, true), s(KEY_W, true)]
    );
    keys.key(KEY_BACKSPACE, false, terminal());
    assert_eq!(
        keys.key(KEY_DELETE, true, terminal()),
        [s(KEY_LEFTCTRL, false), s(KEY_LEFTALT, true), s(KEY_D, true)]
    );
    keys.key(KEY_DELETE, false, terminal());
    assert_eq!(
        keys.key(KEY_LEFTMETA, false, terminal()),
        [s(KEY_LEFTALT, false)]
    );
}

#[test]
fn option_moves_by_word_and_types_alt_for_menus() {
    let mut keys = mac();
    // Super is the shortcut engine's: it tells the translation it is held.
    assert!(keys.key(KEY_LEFTMETA, true, consumed()).is_empty());
    assert_eq!(
        keys.key(KEY_LEFT, true, ordinary()),
        [s(KEY_LEFTCTRL, true), p(KEY_LEFT, true)]
    );
    keys.key(KEY_LEFT, false, ordinary());
    assert_eq!(
        keys.key(KEY_BACKSPACE, true, ordinary()),
        [p(KEY_BACKSPACE, true)]
    );
    keys.key(KEY_BACKSPACE, false, ordinary());
    assert_eq!(
        keys.key(KEY_F, true, ordinary()),
        [s(KEY_LEFTCTRL, false), s(KEY_LEFTALT, true), p(KEY_F, true)]
    );
    keys.key(KEY_F, false, ordinary());
    assert_eq!(
        keys.key(KEY_LEFTMETA, false, ordinary()),
        [s(KEY_LEFTALT, false)]
    );
}

#[test]
fn command_digits_and_other_keys_stay_alt() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    // Alt+1 picks the first tab in Firefox, Chromium and terminals.
    assert_eq!(
        keys.key(KEY_1, true, ordinary()),
        [s(KEY_LEFTALT, true), p(KEY_1, true)]
    );
    keys.key(KEY_1, false, ordinary());
    // ⌘0 resets the zoom: Ctrl+0.
    assert_eq!(
        keys.key(KEY_0, true, ordinary()),
        [s(KEY_LEFTALT, false), s(KEY_LEFTCTRL, true), p(KEY_0, true)]
    );
    keys.key(KEY_0, false, ordinary());
    assert_eq!(
        keys.key(KEY_F4, true, ordinary()),
        [
            s(KEY_LEFTCTRL, false),
            s(KEY_LEFTALT, true),
            p(KEY_F4, true)
        ]
    );
}

#[test]
fn a_shell_shortcut_hides_the_translated_modifier() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    keys.key(KEY_C, true, ordinary());
    keys.key(KEY_C, false, ordinary());
    // Alt+Tab: the app switcher. The app does not see Ctrl meanwhile.
    assert_eq!(
        keys.key(KEY_TAB, true, consumed()),
        [s(KEY_LEFTCTRL, false)]
    );
    assert!(keys.key(KEY_TAB, false, consumed()).is_empty());
    assert!(keys.key(KEY_LEFTALT, false, ordinary()).is_empty());
}

#[test]
fn apps_that_take_raw_keys_get_them_as_they_are() {
    let mut keys = mac();
    assert_eq!(keys.key(KEY_LEFTALT, true, raw()), [p(KEY_LEFTALT, true)]);
    assert_eq!(keys.key(KEY_C, true, raw()), [p(KEY_C, true)]);
    keys.key(KEY_C, false, raw());
    assert_eq!(keys.key(KEY_LEFTALT, false, raw()), [p(KEY_LEFTALT, false)]);
    assert_eq!(keys.key(KEY_LEFTMETA, true, raw()), [p(KEY_LEFTMETA, true)]);
    assert_eq!(
        keys.key(KEY_LEFTMETA, false, raw()),
        [p(KEY_LEFTMETA, false)]
    );

    // ⌘ pressed before the app took the keys is Alt to it.
    assert!(keys.key(KEY_LEFTALT, true, ordinary()).is_empty());
    assert_eq!(
        keys.key(KEY_C, true, raw()),
        [s(KEY_LEFTALT, true), p(KEY_C, true)]
    );
    assert_eq!(
        keys.key(KEY_LEFTALT, false, raw()),
        [p(KEY_C, false), s(KEY_LEFTALT, false)]
    );
    assert!(keys.key(KEY_C, false, raw()).is_empty());
}

#[test]
fn turning_the_preset_off_lets_go_of_what_denial_holds() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    keys.key(KEY_LEFT, true, ordinary());
    keys.key(KEY_C, true, ordinary());
    assert_eq!(
        keys.set_enabled(false),
        [p(KEY_C, false), s(KEY_HOME, false), s(KEY_LEFTCTRL, false)]
    );
    assert!(keys.key(KEY_C, false, ordinary()).is_empty());
    assert!(keys.key(KEY_LEFT, false, ordinary()).is_empty());
    assert!(keys.key(KEY_LEFTALT, false, ordinary()).is_empty());
    assert_eq!(keys.key(KEY_C, true, ordinary()), [p(KEY_C, true)]);
}

#[test]
fn right_alt_types_when_the_layout_makes_it_altgr() {
    let mut keys = mac();
    keys.set_right_alt_is_command(false);
    assert_eq!(
        keys.key(KEY_RIGHTALT, true, ordinary()),
        [p(KEY_RIGHTALT, true)]
    );
    assert_eq!(keys.key(KEY_C, true, ordinary()), [p(KEY_C, true)]);
    keys.key(KEY_C, false, ordinary());
    assert_eq!(
        keys.key(KEY_RIGHTALT, false, ordinary()),
        [p(KEY_RIGHTALT, false)]
    );
}

#[test]
fn command_click_holds_ctrl_until_command_goes_up() {
    let mut keys = mac();
    assert!(keys.pointer_button(false).is_empty());
    keys.key(KEY_LEFTALT, true, ordinary());
    assert_eq!(keys.pointer_button(false), [s(KEY_LEFTCTRL, true)]);
    assert!(keys.pointer_button(false).is_empty());
    assert!(keys.pointer_button(true).is_empty());
    assert_eq!(
        keys.key(KEY_LEFTALT, false, ordinary()),
        [s(KEY_LEFTCTRL, false)]
    );
}

#[test]
fn only_keys_that_reached_the_app_are_delivered() {
    let mut keys = mac();
    keys.key(KEY_LEFTALT, true, ordinary());
    assert!(!keys.delivers(KEY_LEFTALT));
    keys.key(KEY_LEFTCTRL, true, ordinary());
    assert!(keys.delivers(KEY_LEFTCTRL));
    let mut keys = MacKeys::default();
    keys.key(KEY_LEFTALT, true, ordinary());
    assert!(keys.delivers(KEY_LEFTALT));
}

#[test]
fn terminals_are_known_by_their_app_ids() {
    for app_id in [
        "org.gnome.Console",
        "kgx",
        "org.gnome.Terminal",
        "gnome-terminal-server",
        "org.gnome.Ptyxis",
        "foot",
        "footclient",
        "Alacritty",
        "kitty",
        "org.wezfurlong.wezterm",
        "XTerm",
        "org.kde.konsole",
        "com.mitchellh.ghostty",
    ] {
        assert_eq!(client_kind(app_id), ClientKind::Terminal, "{app_id}");
    }
    for app_id in [
        "",
        "firefox",
        "org.gnome.Nautilus",
        "org.gnome.TextEditor",
        "org.denialwm.Console",
        "terminal",
        "org.example.Terminal",
        "code",
    ] {
        assert_eq!(client_kind(app_id), ClientKind::Ordinary, "{app_id}");
    }
}

/// A seat that holds keys per source, as Smithay's does: a key is down for
/// an app while any source holds it.
#[derive(Default)]
struct Seat {
    physical: HashSet<u32>,
    synthetic: HashSet<u32>,
}

impl Seat {
    fn apply(&mut self, events: &[KeyEvent]) {
        for event in events {
            let held = match event.source {
                KeySource::Physical => &mut self.physical,
                KeySource::Synthetic => &mut self.synthetic,
            };
            if event.pressed {
                assert!(held.insert(event.key), "{event:?} pressed twice");
            } else {
                // Physical releases of keys the seat never saw down are
                // absorbed there, as unknown releases are by Smithay.
                let was_held = held.remove(&event.key);
                assert!(
                    was_held || event.source == KeySource::Physical,
                    "{event:?} released but not held"
                );
            }
        }
    }
}

#[test]
fn no_key_stays_held_whatever_the_order() {
    let keys = [
        KEY_LEFTALT,
        KEY_RIGHTALT,
        KEY_LEFTMETA,
        KEY_LEFTSHIFT,
        KEY_LEFTCTRL,
        KEY_C,
        KEY_V,
        KEY_1,
        KEY_LEFT,
        KEY_UP,
        KEY_BACKSPACE,
        KEY_DELETE,
        KEY_TAB,
    ];
    let mut state = 0x2545_f491_4f6c_dd1d_u64;
    let mut next = move |bound: usize| {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        (state % bound as u64) as usize
    };
    for _ in 0..400 {
        let mut translation = MacKeys::default();
        let mut seat = Seat::default();
        let mut down = Vec::<u32>::new();
        for _ in 0..40 {
            if next(9) == 0 {
                seat.apply(&translation.set_enabled(next(2) == 0));
            }
            if next(11) == 0 {
                seat.apply(&translation.pointer_button(next(2) == 0));
            }
            let key = keys[next(keys.len())];
            let context = KeyContext {
                client: if next(2) == 0 {
                    ClientKind::Ordinary
                } else {
                    ClientKind::Terminal
                },
                // Super is always the engine's; Tab is sometimes a shortcut.
                consumed: key == KEY_LEFTMETA || (key == KEY_TAB && next(2) == 0),
                raw: next(6) == 0,
            };
            if let Some(index) = down.iter().position(|&held| held == key) {
                down.remove(index);
                seat.apply(&translation.key(key, false, context));
            } else {
                down.push(key);
                seat.apply(&translation.key(key, true, context));
            }
        }
        while let Some(key) = down.pop() {
            seat.apply(&translation.key(key, false, ordinary()));
        }
        assert!(
            seat.physical.is_empty(),
            "physical keys held: {:?}",
            seat.physical
        );
        assert!(
            seat.synthetic.is_empty(),
            "synthetic keys held: {:?}",
            seat.synthetic
        );
    }
}
