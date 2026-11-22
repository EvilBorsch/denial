# Apps follow the tablet and desktop modes

Denial's shell is either a tablet's (the mobile profile,
`DENIAL_SHELL_PROFILE=mobile`, with the Desktop mode tile off) or a desktop's
(the Desktop mode tile on, or a desktop profile). A monitor beside the tablet
carries the desktop shell, where apps go, so it counts as desktop. Apps can
follow this: touch layouts on the tablet, desktop layouts at the desk.

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
| `org.denialwm.shell` `keyboard-attached` | `b` | a keyboard to type on is attached, such as a keyboard cover |
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
