# Shortcut presets: standard keys and "Like a Mac"

Settings → Shortcuts → **Like a Mac** («Как на Mac») chooses which keys the
shell uses. It is stored as `shortcuts.preset` in
`~/.config/denial/settings.json`: `"standard"` (also when absent) or `"mac"`.

## What every preset brings

A preset's shortcuts are derived when `deniald` loads them; they are never
written to `~/.config/denial/shortcuts.json`. Settings lists them under
**Built-in shortcuts** and edits them through the shortcut file:

- a binding of the same keys in the file replaces the preset's;
- deleting a preset's shortcut adds a binding of its keys to **Send to the
  app** (`deniald.sendToApp`), so the keys reach the app; deleting that
  binding brings the preset's shortcut back;
- moving one to other keys does both.

| Keys | Standard | Like a Mac |
|---|---|---|
| Alt+Tab, Alt+Shift+Tab | App switcher | App switcher |
| Alt+`, Alt+Shift+` | Windows of the selected app | the same |
| Super+S | Search | Search |
| Alt+F | (app) | Search |
| Alt+Space, Alt+Shift+Space | keyboard layout (from the shortcut file) | keyboard layout |
| Alt+Shift+3 | (app) | Screenshot of the whole screen |
| Alt+Shift+4 | (app) | Screenshot of a region |
| Ctrl+Alt+Q | (app) | Lock the screen |
| Ctrl+Alt+F | (app) | Full screen |
| Alt+M | (app) | Minimize the window |
| Alt+H | (app) | Hide the app (minimize all its windows) |
| Ctrl+← / Ctrl+→ | (app) | Previous / next screen (focus left / right) |
| Ctrl+↑ / Ctrl+↓ | (app) | Overview / the app's windows |

Search in the standard keys is Super+S because Super+F is full screen and
Super+Space the keyboard layout; Windows uses Win+S the same way. Find in an
app is Ctrl+F in both presets.

The app switcher: hold Alt, Tab steps the apps (all windows of an app are
one), Shift+Tab steps back, ` and Shift+` step the selected app's windows,
←/→ step too, Escape closes it, and releasing Alt switches. A quick Alt+Tab
switches without showing it. It is the desktop presentation's; in the tablet
presentation the keys go to the app. Super+Tab stays the window switcher, and
Shift now steps it back as well.

## Like a Mac: keys for apps

With the preset on, the physical Alt keys are ⌘ and the physical Super keys
⌥; Ctrl stays Ctrl and Shift is kept. Shortcuts see the physical keys first
and win. Every other key reaches the focused app translated
(`compositor/src/bin/deniald/mac_keys.rs`):

| Keys | Most apps | Terminals |
|---|---|---|
| ⌘ + letter | Ctrl + letter | Ctrl+Shift + letter |
| ⌘ + punctuation, 0, Enter | Ctrl + key | Ctrl + key |
| ⌘ + 1…9 and other keys | Alt + key | Alt + key |
| ⌘← ⌘→ | Home, End | Ctrl+A, Ctrl+E |
| ⌘↑ ⌘↓ | Ctrl+Home, Ctrl+End | the same |
| ⌘⌫ ⌘⌦ | Shift+Home then Backspace, Shift+End then Delete | Ctrl+U, Ctrl+K |
| ⌥← ⌥→ ⌥↑ ⌥↓ | Ctrl + arrow | Alt+B, Alt+F; Ctrl+↑/↓ |
| ⌥⌫ ⌥⌦ | Ctrl+Backspace, Ctrl+Delete | Ctrl+W, Alt+D |
| ⌥ + other keys | Alt + key | Alt + key |
| ⌘ alone | nothing | nothing |
| ⌘ + click | Ctrl + click | Ctrl + click |

- ⌘ + digit stays Alt: Firefox, Chromium and terminals on Linux pick tabs
  with Alt+1…9, where macOS uses ⌘.
- ⌘⌫ selects to the line's start and deletes the selection: GTK, Qt,
  Firefox, Chromium and LibreOffice have no shared "delete to line start"
  key, but all of them select with Shift+Home. At a line's start it deletes
  the line break, as on a Mac.
- Terminals get what iTerm2's "Natural Text Editing" sends, which readline,
  zsh and fish understand. A window is a terminal by its Wayland app ID or
  X11 class: GNOME Console (kgx), GNOME Terminal, Ptyxis, foot, Alacritty,
  kitty, WezTerm, xterm, Konsole, Ghostty, Tilix, Terminator and others,
  reverse-DNS IDs included.
- ⌥ with the arrows, Backspace and Delete edits text even where Shortcuts
  binds Super to them (Super+←/→ move between screens in the standard keys;
  in the Mac keys that is Ctrl+←/→). Super's other shortcuts stay, and
  Super with a letter no shortcut uses reaches the app as Alt with it.
- Not translated: the lock screen, an app holding Denial's shortcuts (a
  remote desktop or a virtual machine, after the user allowed it), and the
  on-screen keyboard. Right Alt stays AltGr where the keyboard layout types
  with it.
- The shell's own fields get the translated keys like any app: Alt+C and
  Alt+V copy and paste there too.

## Older releases

Nothing a preset brings is in the shortcut file, which keeps schema version
12. Its new actions are `deniald`'s own plugin actions (`deniald.appSwitcher`,
`deniald.appWindowSwitcher`, `deniald.search`, `deniald.hideApplication`,
`deniald.captureScreen`, `deniald.appWindows`, `deniald.sendToApp`): an
older `deniald` (eb17, eb16.tp1) reads a file that names them and treats
them as actions of a plugin that is not installed, leaving those keys to the
app. `shortcuts.preset` is a section of the settings file no older release
reads. After a rollback everything is the standard keys of that release,
the files load unchanged, and coming back restores the preset and every
edit.
