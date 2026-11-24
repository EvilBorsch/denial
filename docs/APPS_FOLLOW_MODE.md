# Apps follow the tablet and desktop modes

Denial's shell is either a tablet's (the mobile profile,
`DENIAL_SHELL_PROFILE=mobile`, with the Desktop mode tile off) or a desktop's
(the Desktop mode tile on, or a desktop profile). A monitor beside the tablet
carries the desktop shell, where apps go, so it counts as desktop. Apps can
follow this: touch layouts on the tablet, desktop layouts at the desk.

## How the shell picks its presentation

On a single screen the presentation follows a physical keyboard: attaching
one (a keyboard cover, USB or Bluetooth) brings up the desktop, detaching the
last one the tablet, three seconds after it went (a cover whose driver
switches it off and on again must not flip it there and back). Virtual
(uinput) keyboards, such as the test tool's `erhai test keyboard`, do not
count. The Desktop mode tile, and the dashboard's button, switch by hand;
that choice holds until the next attach or detach. With a monitor beside the
tablet nothing switches on its own; a keyboard attached or detached
meanwhile decides once the monitor is gone. A switch keeps every window, and
under the lock screen the other presentation's lock screen shows at once.

What a switch keeps (eb19): while the tablet presentation holds the screen,
the desktop's window layout waits as it was left, so the desktop comes back
with the same screens in the same order, and the app in front on the tablet
is the current screen (and the other way round). A screen of the full-screen
apps layout holding two windows side by side is a Split View pair on the
tablet, with the same share, and a pair made, changed or taken apart on the
tablet is a split screen, changed or taken apart, on the desktop. Apps the
tablet paused because the user left them are on their screens again; windows
minimized on the desktop stay minimized. The last picture of the
presentation left stays in front until the windows the new one shows have
redrawn at their new sizes (half a second at most), then dissolves into it
(`deniald`: `wayland_frontend/presentation_switch.rs`; shell:
`core/presentation_switch_cover.dart`).

The shell keeps the presentation in the settings document, section
`presentation` (validated by `deniald`, read by no release before eb18,
which keep it as it is):

| Key | Default | Meaning |
|---|---|---|
| `followKeyboard` | `true` | the presentation follows a physical keyboard (Settings: Desktop layout, Follow the keyboard) |
| `mode` | absent | `"tablet"` or `"desktop"`: the presentation shown last, which the shell starts in again |
| `modeKeyboard` | absent | whether a physical keyboard was attached when `mode` was chosen |

At a start the shell shows `mode` as soon as the settings arrive. Once the
device list is there too, and while following the keyboard, a keyboard
attached or detached since `mode` was chosen (`modeKeyboard` differs, or is
absent) decides; otherwise `mode` holds, a choice by hand included. Switched
off, `mode` alone decides. Turning following on applies the keyboard at once.

`mode` and `followKeyboard` can be set through Denial's settings channel
(`settings.document.apply` on the control socket, as Settings does): a
`mode` set from outside the shell counts as a choice by hand. On the tablet:

```sh
sudo -u dmitry XDG_RUNTIME_DIR=/run/user/1000 erhai-denial-setting presentation.mode desktop
sudo -u dmitry XDG_RUNTIME_DIR=/run/user/1000 erhai-denial-setting presentation.followKeyboard false
```

## What Denial publishes

The shell tells `deniald` its presentation over the wire
(`ShellPresentation` in `protocol/denial.fbs`, only from the embedded shell).
`deniald` adds whether a keyboard to type on is attached and the user's
choice, and hands the result to `denial-portal` with the theme snapshot
(`src/portal_protocol.rs`, protocol version 3). The portal serves it through
the Settings portal, `org.freedesktop.portal.Settings` (`ReadOne`, `ReadAll`,
`SettingChanged`), in Denial's own namespace:

| Namespace / key | Type | Value |
|---|---|---|
| `org.denialwm.shell` `presentation` | `s` | `tablet` or `desktop` |
| `org.denialwm.shell` `keyboard-attached` | `b` | a physical keyboard to type on is attached, such as a keyboard cover: the keyboards the shell's presentation follows, not virtual (uinput) ones such as a test tool's |
| `org.denialwm.shell` `tablet-mode` | `b` | apps should show their touch layouts: the presentation is `tablet` and `apps.followMode` is on |

`tablet-mode` is what an app or adapter follows; `presentation` and
`keyboard-attached` are there for those that want to decide themselves.
Read once at start, then follow `SettingChanged`:

```sh
gdbus call --session --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.portal.Settings.ReadOne org.denialwm.shell tablet-mode
```

## GTK's text scale

GTK 4 (4.22 reads its settings through the portal even outside a sandbox
whenever a portal is running) and sandboxed GTK 3 apps take
`org.gnome.desktop.interface` `text-scaling-factor` from the Settings portal
and apply a change at once. While apps follow the shell and a text scale is
set for the current presentation, Denial's portal serves that key, and the
frontend prefers it over the GTK backend's (the user's GSettings value). When
Denial stops serving it, the portal reads the frontend's answer from the next
backend and signals that value, so running apps return to it.

Unsandboxed GTK 3 apps (Firefox among them) read GSettings directly and keep
the user's text scale.

A change of the GSettings value while Denial serves its own reaches apps
through the GTK backend's signal until the next mode change; nothing on the
tablet changes that value.

## Settings

In `settings.json`, section `apps` (validated by `deniald`):

| Key | Default | Meaning |
|---|---|---|
| `followMode` | `true` | apps follow the shell; off, `tablet-mode` stays false and no text scale is served, while `presentation` and `keyboard-attached` are still published |
| `tabletTextScale` | absent | GTK text scale (0.5–3) in tablet presentation; absent or `null` keeps the desktop's own |
| `desktopTextScale` | absent | the same in desktop presentation |

`apps.scale` (how much larger than the shell apps are drawn) is not switched
with the mode: it applies to a client when it connects, so running apps
would keep their old size beside new ones.

## What follows the modes on the tablet

- Firefox: touch density of its toolbars while `tablet-mode` is on (package
  `erhai-denial`: AutoConfig `/etc/firefox/erhai-denial-mode.cfg` and its
  watcher `denial-mode-watch`).
- GTK 4 and libadwaita apps: the text scale above, when one is set. Their
  adaptive layouts follow their window's width, which Denial's tablet and
  desktop layouts already change.
