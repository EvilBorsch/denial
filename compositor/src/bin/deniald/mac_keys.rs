//! The "Like a Mac" keyboard preset: Denial translates keys per app.
//!
//! With the preset on, the physical Alt keys act as ⌘ (Command) and the
//! physical Super keys as ⌥ (Option); Ctrl stays Ctrl and Shift is kept.
//! deniald's shortcut engine sees the physical keys first, so the shell's
//! own bindings (Alt+Tab, Alt+F, Alt+Space, Ctrl+Alt+Q, …) win. Every key the
//! engine lets through comes here and reaches the focused app as follows.
//!
//! | Keys | Most apps | Terminals |
//! |---|---|---|
//! | ⌘ + letter | Ctrl + letter | Ctrl+Shift + letter (Ctrl alone is the terminal's: Ctrl+C interrupts) |
//! | ⌘ + punctuation, 0, Enter | Ctrl + key | Ctrl + key |
//! | ⌘ + 1…9 and other keys | Alt + key: Linux browsers and terminals pick tabs with Alt+digit | the same |
//! | ⌘← ⌘→ | Home, End | Ctrl+A, Ctrl+E |
//! | ⌘↑ ⌘↓ | Ctrl+Home, Ctrl+End | the same |
//! | ⌘⌫ ⌘⌦ | Shift+Home then Backspace, Shift+End then Delete | Ctrl+U, Ctrl+K |
//! | ⌥← ⌥→ ⌥↑ ⌥↓ | Ctrl + arrow: by word and paragraph | Alt+B, Alt+F; Ctrl+↑/↓ |
//! | ⌥⌫ ⌥⌦ | Ctrl+Backspace, Ctrl+Delete | Ctrl+W, Alt+D |
//! | ⌥ + other keys | Alt + key: menus' access keys | Alt + key: readline's Meta |
//!
//! Terminals get what iTerm2's "Natural Text Editing" sends: readline,
//! zsh and fish understand it. ⌘⌫ selects to the line's start and deletes
//! the selection because no shared binding deletes to a line's start: GTK,
//! Qt, Firefox, Chromium and LibreOffice all select with Shift+Home and
//! delete a selection with Backspace. At the line's start it deletes the
//! line break, as ⌘⌫ does on a Mac.
//!
//! ⌘ alone reaches no app, as on a Mac (Firefox would open its menu bar). A
//! pointer button pressed while ⌘ is held reaches the app with Ctrl: ⌘-click
//! opens a link in a new tab.
//!
//! The state machine is pure: it is fed physical key transitions and gives
//! back the transitions to feed to the seat. Physical outputs are the
//! physical key itself; synthetic ones (modifiers and substituted keys) go
//! through a keyboard source of their own, so that a synthetic Ctrl never
//! releases a physically held Ctrl. Each press remembers what it produced,
//! and its release undoes exactly that, whatever changed in between: the
//! preset, the focused app, the lock screen. When ⌘ or ⌥ is released, every
//! key still held that it translated is released too, so no app keeps a
//! modifier or repeats a bare letter.

use std::collections::HashMap;

pub(super) const KEY_0: u32 = 11;
pub(super) const KEY_MINUS: u32 = 12;
pub(super) const KEY_EQUAL: u32 = 13;
pub(super) const KEY_BACKSPACE: u32 = 14;
pub(super) const KEY_LEFTBRACE: u32 = 26;
pub(super) const KEY_RIGHTBRACE: u32 = 27;
pub(super) const KEY_ENTER: u32 = 28;
pub(super) const KEY_LEFTCTRL: u32 = 29;
pub(super) const KEY_A: u32 = 30;
pub(super) const KEY_D: u32 = 32;
pub(super) const KEY_F: u32 = 33;
pub(super) const KEY_K: u32 = 37;
pub(super) const KEY_SEMICOLON: u32 = 39;
pub(super) const KEY_APOSTROPHE: u32 = 40;
pub(super) const KEY_LEFTSHIFT: u32 = 42;
pub(super) const KEY_BACKSLASH: u32 = 43;
pub(super) const KEY_B: u32 = 48;
pub(super) const KEY_COMMA: u32 = 51;
pub(super) const KEY_DOT: u32 = 52;
pub(super) const KEY_SLASH: u32 = 53;
pub(super) const KEY_RIGHTSHIFT: u32 = 54;
pub(super) const KEY_LEFTALT: u32 = 56;
pub(super) const KEY_CAPSLOCK: u32 = 58;
pub(super) const KEY_102ND: u32 = 86;
pub(super) const KEY_KPENTER: u32 = 96;
pub(super) const KEY_RIGHTCTRL: u32 = 97;
pub(super) const KEY_RIGHTALT: u32 = 100;
pub(super) const KEY_HOME: u32 = 102;
pub(super) const KEY_UP: u32 = 103;
pub(super) const KEY_LEFT: u32 = 105;
pub(super) const KEY_RIGHT: u32 = 106;
pub(super) const KEY_END: u32 = 107;
pub(super) const KEY_DOWN: u32 = 108;
pub(super) const KEY_DELETE: u32 = 111;
pub(super) const KEY_LEFTMETA: u32 = 125;
pub(super) const KEY_RIGHTMETA: u32 = 126;
const KEY_E: u32 = 18;
const KEY_U: u32 = 22;
const KEY_W: u32 = 17;

/// What the focused app is, as far as its keys go.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) enum ClientKind {
    /// The shell, a Wayland or an X11 app.
    #[default]
    Ordinary,
    /// A terminal emulator, by its app ID.
    Terminal,
}

/// App IDs (Wayland) and X11 classes of terminals, lowercase.
const TERMINAL_IDS: &[&str] = &[
    "org.gnome.console",
    "org.gnome.terminal",
    "gnome-terminal",
    "gnome-terminal-server",
    "org.gnome.ptyxis",
    "org.gnome.ptyxis.devel",
    "org.kde.konsole",
    "org.wezfurlong.wezterm",
    "com.mitchellh.ghostty",
    "com.raggesilver.blackbox",
    "com.gexperts.tilix",
    "net.kovidgoyal.kitty",
    "org.codeberg.dnkl.foot",
    "st-256color",
];

/// The last part of a reverse-DNS app ID, or a whole plain one, that names
/// a terminal. Generic words such as "console" and "terminal" are matched
/// only as whole IDs above.
const TERMINAL_NAMES: &[&str] = &[
    "kgx",
    "ptyxis",
    "foot",
    "footclient",
    "alacritty",
    "kitty",
    "wezterm",
    "wezterm-gui",
    "xterm",
    "uxterm",
    "konsole",
    "ghostty",
    "tilix",
    "terminator",
    "xfce4-terminal",
    "lxterminal",
    "mate-terminal",
    "qterminal",
    "terminology",
    "urxvt",
    "rxvt",
    "st",
    "sakura",
    "guake",
    "tilda",
    "yakuake",
    "contour",
    "rio",
];

/// Whether `app_id` (a Wayland app ID or an X11 class) is a terminal.
pub(super) fn client_kind(app_id: &str) -> ClientKind {
    let id = app_id.trim().to_ascii_lowercase();
    let last = id.rsplit('.').next().unwrap_or(&id);
    if TERMINAL_IDS.contains(&id.as_str())
        || TERMINAL_NAMES.contains(&id.as_str())
        || (id.contains('.') && TERMINAL_NAMES.contains(&last))
    {
        ClientKind::Terminal
    } else {
        ClientKind::Ordinary
    }
}

/// Where a physical key transition happens.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(super) struct KeyContext {
    /// The focused app.
    pub(super) client: ClientKind,
    /// The shell's shortcut engine took the key: a binding, or Super.
    pub(super) consumed: bool,
    /// Keys reach the app as they are: the session is locked, or the app
    /// holds Denial's shortcuts (a remote desktop, a virtual machine).
    pub(super) raw: bool,
}

/// Which keyboard source a transition goes through.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum KeySource {
    /// The physical key itself.
    Physical,
    /// A modifier or a substituted key Denial adds.
    Synthetic,
}

/// A transition to feed to the seat, as an evdev keycode.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct KeyEvent {
    pub(super) key: u32,
    pub(super) pressed: bool,
    pub(super) source: KeySource,
}

impl KeyEvent {
    const fn physical(key: u32, pressed: bool) -> Self {
        Self {
            key,
            pressed,
            source: KeySource::Physical,
        }
    }

    const fn synthetic(key: u32, pressed: bool) -> Self {
        Self {
            key,
            pressed,
            source: KeySource::Synthetic,
        }
    }
}

/// Modifiers Denial holds for an app.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct Mods(u8);

impl Mods {
    const NONE: Self = Self(0);
    const CTRL: Self = Self(1);
    const SHIFT: Self = Self(2);
    const ALT: Self = Self(4);
    /// Each modifier with the key Denial presses for it, in the order they
    /// go down.
    const KEYS: [(Self, u32); 3] = [
        (Self::CTRL, KEY_LEFTCTRL),
        (Self::SHIFT, KEY_LEFTSHIFT),
        (Self::ALT, KEY_LEFTALT),
    ];

    const fn with(self, other: Self) -> Self {
        Self(self.0 | other.0)
    }

    const fn has(self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Layer {
    Command,
    Option,
}

/// What a press produced.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Output {
    /// Nothing: a held-back ⌘ or ⌥, a key the shell took, or one already
    /// let go.
    Nothing,
    /// The physical key itself.
    Physical,
    /// Another key, pressed by Denial.
    Synthetic(u32),
}

#[derive(Clone, Copy, Debug)]
struct Route {
    output: Output,
    /// The layer that translated it. Its release lets the key go.
    layer: Option<Layer>,
}

/// One translated press: modifiers to hold, an optional key tapped first
/// with its own modifiers, and the key that stays down.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Translation {
    modifiers: Mods,
    tap: Option<(u32, Mods)>,
    key: Output,
}

impl Translation {
    const fn held(modifiers: Mods) -> Self {
        Self {
            modifiers,
            tap: None,
            key: Output::Physical,
        }
    }

    const fn substitute(modifiers: Mods, key: u32) -> Self {
        Self {
            modifiers,
            tap: None,
            key: Output::Synthetic(key),
        }
    }

    const fn after_tap(tap: u32, tap_modifiers: Mods) -> Self {
        Self {
            modifiers: Mods::NONE,
            tap: Some((tap, tap_modifiers)),
            key: Output::Physical,
        }
    }
}

const LEFT_BIT: u8 = 1;
const RIGHT_BIT: u8 = 2;

/// The translation's state. See the module documentation.
#[derive(Debug)]
pub(super) struct MacKeys {
    enabled: bool,
    /// Whether Right Alt is ⌘ too. It is AltGr in layouts that type with it.
    right_alt_is_command: bool,
    command: u8,
    option: u8,
    engaged: Mods,
    routes: HashMap<u32, Route>,
}

impl Default for MacKeys {
    fn default() -> Self {
        Self {
            enabled: false,
            right_alt_is_command: true,
            command: 0,
            option: 0,
            engaged: Mods::NONE,
            routes: HashMap::new(),
        }
    }
}

impl MacKeys {
    pub(super) fn enabled(&self) -> bool {
        self.enabled
    }

    /// Turns the preset on or off. Whatever Denial holds for an app is let
    /// go first.
    pub(super) fn set_enabled(&mut self, enabled: bool) -> Vec<KeyEvent> {
        if self.enabled == enabled {
            return Vec::new();
        }
        let released = self.flush();
        self.enabled = enabled;
        released
    }

    /// Whether Right Alt is ⌘. False while the keymap makes it AltGr.
    pub(super) fn set_right_alt_is_command(&mut self, command: bool) {
        self.right_alt_is_command = command;
    }

    /// Whether the held physical `key` reached the focused app as itself.
    pub(super) fn delivers(&self, key: u32) -> bool {
        self.routes
            .get(&key)
            .is_some_and(|route| route.output == Output::Physical)
    }

    /// Forgets everything after the seat dropped every key (a device reset).
    pub(super) fn reset(&mut self) {
        let enabled = self.enabled;
        let right_alt_is_command = self.right_alt_is_command;
        *self = Self {
            enabled,
            right_alt_is_command,
            ..Self::default()
        };
    }

    /// Lets go of every key and modifier Denial holds for an app. Physical
    /// keys it passed on as they are stay down until released.
    pub(super) fn flush(&mut self) -> Vec<KeyEvent> {
        let mut out = Vec::new();
        self.release_layer(None, &mut out);
        out
    }

    /// A physical key went down or up.
    pub(super) fn key(&mut self, key: u32, pressed: bool, context: KeyContext) -> Vec<KeyEvent> {
        let mut out = Vec::new();
        if pressed {
            self.press(key, context, &mut out);
        } else {
            self.release(key, &mut out);
        }
        out
    }

    /// A pointer button went down. While ⌘ is held the app gets Ctrl with
    /// it, as ⌘-click on a Mac.
    pub(super) fn pointer_button(&mut self, raw: bool) -> Vec<KeyEvent> {
        let mut out = Vec::new();
        if self.enabled && !raw && self.held_back(Layer::Command) {
            self.engage(self.engaged.with(Mods::CTRL), &mut out);
        }
        out
    }

    fn layer_bit(&self, key: u32) -> Option<(Layer, u8)> {
        match key {
            KEY_LEFTALT => Some((Layer::Command, LEFT_BIT)),
            KEY_RIGHTALT if self.right_alt_is_command => Some((Layer::Command, RIGHT_BIT)),
            KEY_LEFTMETA => Some((Layer::Option, LEFT_BIT)),
            KEY_RIGHTMETA => Some((Layer::Option, RIGHT_BIT)),
            _ => None,
        }
    }

    fn layer_keys(&mut self, layer: Layer) -> &mut u8 {
        match layer {
            Layer::Command => &mut self.command,
            Layer::Option => &mut self.option,
        }
    }

    fn press(&mut self, key: u32, context: KeyContext, out: &mut Vec<KeyEvent>) {
        if self.routes.contains_key(&key) {
            // A second press without a release: the first one stands.
            return;
        }
        let layer = self.layer_bit(key);
        if let Some((layer, bit)) = layer {
            *self.layer_keys(layer) |= bit;
        }
        let modifier = layer.is_none() && is_modifier(key);
        if context.consumed {
            if layer.is_none() && !modifier {
                // A shell shortcut runs: the app sees no translated
                // modifier while it does.
                self.engage(Mods::NONE, out);
            }
            self.remember(key, Output::Nothing, None);
            return;
        }
        if !self.enabled || modifier {
            out.push(KeyEvent::physical(key, true));
            self.remember(key, Output::Physical, None);
            return;
        }
        if layer.is_some() {
            // ⌘ is held back. ⌥ (Super) gets here only when an app takes
            // the keys as they are; the shortcut engine keeps it otherwise.
            if context.raw {
                out.push(KeyEvent::physical(key, true));
                self.remember(key, Output::Physical, None);
            } else {
                self.remember(key, Output::Nothing, None);
            }
            return;
        }
        if context.raw {
            // A held-back ⌘ is Alt to an app that takes the keys as they are.
            let (modifiers, layer) = if self.held_back(Layer::Command) {
                (Mods::ALT, Some(Layer::Command))
            } else {
                (Mods::NONE, None)
            };
            self.engage(modifiers, out);
            out.push(KeyEvent::physical(key, true));
            self.remember(key, Output::Physical, layer);
            return;
        }
        let translated = if self.held_back(Layer::Command) {
            Some((
                Layer::Command,
                command_translation(key, context.client, self.held_back(Layer::Option)),
            ))
        } else if self.held_back(Layer::Option) {
            Some((Layer::Option, option_translation(key, context.client)))
        } else {
            None
        };
        let Some((layer, translation)) = translated else {
            self.engage(Mods::NONE, out);
            out.push(KeyEvent::physical(key, true));
            self.remember(key, Output::Physical, None);
            return;
        };
        if let Some((tap, modifiers)) = translation.tap {
            // A key Denial already holds for another press goes up first.
            self.let_go_of_synthetic(tap, out);
            self.engage(modifiers, out);
            out.push(KeyEvent::synthetic(tap, true));
            out.push(KeyEvent::synthetic(tap, false));
        }
        self.engage(translation.modifiers, out);
        match translation.key {
            Output::Synthetic(substitute) => {
                if !self.holds_synthetic(substitute) {
                    out.push(KeyEvent::synthetic(substitute, true));
                }
            }
            Output::Physical | Output::Nothing => out.push(KeyEvent::physical(key, true)),
        }
        self.remember(key, translation.key, Some(layer));
    }

    fn release(&mut self, key: u32, out: &mut Vec<KeyEvent>) {
        let layer = self.layer_bit(key);
        if let Some((layer, bit)) = layer {
            *self.layer_keys(layer) &= !bit;
        }
        match self.routes.remove(&key).map(|route| route.output) {
            // A key pressed before Denial knew it: the seat knows whether
            // it is down.
            None | Some(Output::Physical) => out.push(KeyEvent::physical(key, false)),
            Some(Output::Synthetic(substitute)) => {
                if !self.holds_synthetic(substitute) {
                    out.push(KeyEvent::synthetic(substitute, false));
                }
            }
            Some(Output::Nothing) => {}
        }
        if let Some((layer, _)) = layer
            && *self.layer_keys(layer) == 0
        {
            self.release_layer(Some(layer), out);
        }
    }

    /// Whether a held ⌘ or ⌥ key is held back from apps: then the layer
    /// translates.
    fn held_back(&self, layer: Layer) -> bool {
        self.routes.iter().any(|(&key, route)| {
            route.output == Output::Nothing
                && self.layer_bit(key).is_some_and(|(held, _)| held == layer)
        })
    }

    /// Whether a press still holds `substitute` down for an app.
    fn holds_synthetic(&self, substitute: u32) -> bool {
        self.routes
            .values()
            .any(|route| route.output == Output::Synthetic(substitute))
    }

    /// Releases `substitute` if a press holds it, and forgets that it did.
    fn let_go_of_synthetic(&mut self, substitute: u32, out: &mut Vec<KeyEvent>) {
        let mut found = false;
        for route in self.routes.values_mut() {
            if route.output == Output::Synthetic(substitute) {
                route.output = Output::Nothing;
                found = true;
            }
        }
        if found {
            out.push(KeyEvent::synthetic(substitute, false));
        }
    }

    /// Lets go of the keys `layer` translated, or of every translated key,
    /// and of the modifiers Denial holds.
    fn release_layer(&mut self, layer: Option<Layer>, out: &mut Vec<KeyEvent>) {
        let mut held = self
            .routes
            .iter()
            .filter(|(_, route)| {
                route.layer.is_some() && (layer.is_none() || route.layer == layer)
                    || (layer.is_none() && matches!(route.output, Output::Synthetic(_)))
            })
            .map(|(&key, _)| key)
            .collect::<Vec<_>>();
        held.sort_unstable();
        for key in held {
            let route = self.routes.get_mut(&key).expect("a held key has a route");
            let output = std::mem::replace(&mut route.output, Output::Nothing);
            match output {
                Output::Physical => out.push(KeyEvent::physical(key, false)),
                Output::Synthetic(substitute) => {
                    if !self.holds_synthetic(substitute) {
                        out.push(KeyEvent::synthetic(substitute, false));
                    }
                }
                Output::Nothing => {}
            }
        }
        self.engage(Mods::NONE, out);
    }

    fn remember(&mut self, key: u32, output: Output, layer: Option<Layer>) {
        self.routes.insert(key, Route { output, layer });
    }

    /// Holds exactly `wanted` for the app: releases first, then presses.
    fn engage(&mut self, wanted: Mods, out: &mut Vec<KeyEvent>) {
        for (modifier, key) in Mods::KEYS {
            if self.engaged.has(modifier) && !wanted.has(modifier) {
                out.push(KeyEvent::synthetic(key, false));
            }
        }
        for (modifier, key) in Mods::KEYS {
            if !self.engaged.has(modifier) && wanted.has(modifier) {
                out.push(KeyEvent::synthetic(key, true));
            }
        }
        self.engaged = wanted;
    }
}

/// Keys that pass as they are with ⌘ or ⌥ held: they combine with the
/// translation instead.
fn is_modifier(key: u32) -> bool {
    matches!(
        key,
        KEY_LEFTCTRL | KEY_RIGHTCTRL | KEY_LEFTSHIFT | KEY_RIGHTSHIFT | KEY_CAPSLOCK | KEY_RIGHTALT
    )
}

fn is_letter(key: u32) -> bool {
    matches!(key, 16..=25 | 30..=38 | 44..=50)
}

/// Keys that go with Ctrl under ⌘ besides letters: punctuation (` is the
/// app switcher's), 0 for the zoom reset, and Enter.
fn is_command_key(key: u32) -> bool {
    matches!(
        key,
        KEY_MINUS
            | KEY_EQUAL
            | KEY_LEFTBRACE
            | KEY_RIGHTBRACE
            | KEY_SEMICOLON
            | KEY_APOSTROPHE
            | KEY_BACKSLASH
            | KEY_COMMA
            | KEY_DOT
            | KEY_SLASH
            | KEY_102ND
            | KEY_0
            | KEY_ENTER
            | KEY_KPENTER
    )
}

fn command_translation(key: u32, client: ClientKind, option: bool) -> Translation {
    let terminal = client == ClientKind::Terminal;
    let with_option = |modifiers: Mods| {
        if option {
            modifiers.with(Mods::ALT)
        } else {
            modifiers
        }
    };
    match key {
        KEY_LEFT if terminal => Translation::substitute(Mods::CTRL, KEY_A),
        KEY_RIGHT if terminal => Translation::substitute(Mods::CTRL, KEY_E),
        KEY_BACKSPACE if terminal => Translation::substitute(Mods::CTRL, KEY_U),
        KEY_DELETE if terminal => Translation::substitute(Mods::CTRL, KEY_K),
        KEY_LEFT => Translation::substitute(Mods::NONE, KEY_HOME),
        KEY_RIGHT => Translation::substitute(Mods::NONE, KEY_END),
        KEY_UP => Translation::substitute(Mods::CTRL, KEY_HOME),
        KEY_DOWN => Translation::substitute(Mods::CTRL, KEY_END),
        KEY_BACKSPACE => Translation::after_tap(KEY_HOME, Mods::SHIFT),
        KEY_DELETE => Translation::after_tap(KEY_END, Mods::SHIFT),
        _ if is_letter(key) && terminal => {
            Translation::held(with_option(Mods::CTRL.with(Mods::SHIFT)))
        }
        _ if is_letter(key) || is_command_key(key) => Translation::held(with_option(Mods::CTRL)),
        _ => Translation::held(Mods::ALT),
    }
}

fn option_translation(key: u32, client: ClientKind) -> Translation {
    let terminal = client == ClientKind::Terminal;
    match key {
        KEY_LEFT if terminal => Translation::substitute(Mods::ALT, KEY_B),
        KEY_RIGHT if terminal => Translation::substitute(Mods::ALT, KEY_F),
        KEY_BACKSPACE if terminal => Translation::substitute(Mods::CTRL, KEY_W),
        KEY_DELETE if terminal => Translation::substitute(Mods::ALT, KEY_D),
        KEY_LEFT | KEY_RIGHT | KEY_UP | KEY_DOWN | KEY_BACKSPACE | KEY_DELETE => {
            Translation::held(Mods::CTRL)
        }
        _ => Translation::held(Mods::ALT),
    }
}

/// Super with these keys edits text in the Mac preset (⌥ + arrow, ⌫, ⌦),
/// whatever Shortcuts binds to them.
pub(super) fn option_edits_text(key: u32) -> bool {
    matches!(
        key,
        KEY_LEFT | KEY_RIGHT | KEY_UP | KEY_DOWN | KEY_BACKSPACE | KEY_DELETE
    )
}

#[cfg(test)]
#[path = "mac_keys/tests.rs"]
mod tests;
