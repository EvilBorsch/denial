use super::*;
use futures_lite::{StreamExt, future};
use std::fs::OpenOptions;
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::sync::atomic::{AtomicU64, Ordering};

const SUSPEND_MODE_DIRECTORY: &str = "denial";
const SLEEP_MONITOR_RECONNECT_DELAY: Duration = Duration::from_secs(2);
const LOGIND: &str = "org.freedesktop.login1";
const LOGIND_PATH: &str = "/org/freedesktop/login1";
const LOGIND_MANAGER: &str = "org.freedesktop.login1.Manager";
/// logind's `Inhibit` arguments for the lid switch: what, who, why, mode.
/// Only the lid's own handling is blocked, never `sleep`, so a suspend asked
/// for any other way still happens.
const LID_SWITCH_INHIBITOR: (&str, &str, &str, &str) = (
    "handle-lid-switch",
    "Denial",
    "Stay awake is on: closing the cover turns the screen off instead of suspending",
    "block",
);
static SUSPEND_MODE_TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub(super) fn run_session_worker(commands: Receiver<SessionCommand>) {
    while let Ok(command) = commands.recv() {
        match command {
            SessionCommand::SetSuspendMode(mode) => {
                if let Err(error) = synchronize_suspend_mode(mode) {
                    warn!(%error, "could not publish the selected suspend mode");
                }
            }
            SessionCommand::Power {
                action,
                interactive,
            } => {
                if let Err(error) = perform_power_action(action, interactive) {
                    warn!(%error, ?action, "system power action failed");
                }
            }
            SessionCommand::Stop => {
                if let Err(error) = remove_suspend_mode_marker() {
                    warn!(%error, "could not remove the suspend mode marker");
                }
                return;
            }
        }
    }
}

pub(super) fn run_sleep_monitor(shared: Arc<SleepMonitorShared>) {
    future::block_on(async {
        while !shared.stopping() {
            if let Err(error) = monitor_sleep_transitions(&shared).await
                && !shared.stopping()
            {
                warn!(%error, "logind sleep monitoring is unavailable; retrying");
            }
            shared.release_delay_inhibitor();
            shared.release_power_key_inhibitor();
            // The lid switch inhibitor stays: logind keeps an inhibitor's
            // pipe across its own restart, and letting go while the cover is
            // closed would have logind suspend at once. The next connection
            // takes it only if it is not held.
            //
            // Without logind nobody holds an inhibitor; the next connection
            // reads them again.
            shared.set_blocks(LogindBlocks::default());
            future::race(shared.stopped(), async {
                async_io::Timer::after(SLEEP_MONITOR_RECONNECT_DELAY).await;
            })
            .await;
        }
    });
}

/// What wakes the logind monitor.
enum ManagerEvent {
    Sleep(Option<zbus::Message>),
    Properties(Option<zbus::Message>),
    /// The compositor changed whether it wants the lid switch.
    LidSwitch,
    Stop,
}

async fn monitor_sleep_transitions(shared: &Arc<SleepMonitorShared>) -> Result<(), String> {
    let connection = crate::bus::system()
        .await
        .map_err(|error| format!("could not connect to the system bus: {error}"))?;
    let manager = zbus::Proxy::new(&connection, LOGIND, LOGIND_PATH, LOGIND_MANAGER)
        .await
        .map_err(|error| format!("could not open the logind manager: {error}"))?;
    let properties = zbus::Proxy::new(
        &connection,
        LOGIND,
        LOGIND_PATH,
        "org.freedesktop.DBus.Properties",
    )
    .await
    .map_err(|error| format!("could not open the logind manager properties: {error}"))?;
    if let Err(error) = acquire_power_key_inhibitor(&manager, shared).await {
        warn!(%error, "could not acquire the logind power-key inhibitor");
    }
    synchronize_lid_switch_inhibitor(&manager, shared).await;
    let mut signals = manager
        .receive_signal("PrepareForSleep")
        .await
        .map_err(|error| format!("could not subscribe to PrepareForSleep: {error}"))?;
    if let Err(error) = acquire_sleep_delay(&manager, shared).await {
        warn!(%error, "could not acquire the logind sleep delay inhibitor");
    }
    // logind announces every change of its block inhibitors as a change of
    // BlockInhibited. Subscribe before the first read, so that no change
    // falls between the two. Sleep preparation works without either.
    let mut changes = match properties.receive_signal("PropertiesChanged").await {
        Ok(changes) => {
            refresh_blocks(&properties, shared).await;
            Some(changes)
        }
        Err(error) => {
            warn!(%error, "could not follow logind's block inhibitors");
            None
        }
    };

    loop {
        if shared.stopping() {
            return Ok(());
        }
        let event = future::race(
            future::race(
                future::race(async { ManagerEvent::Sleep(signals.next().await) }, async {
                    match changes.as_mut() {
                        Some(changes) => ManagerEvent::Properties(changes.next().await),
                        None => future::pending().await,
                    }
                }),
                async {
                    shared.lid_switch_wake.wait().await;
                    ManagerEvent::LidSwitch
                },
            ),
            async {
                shared.stopped().await;
                ManagerEvent::Stop
            },
        )
        .await;
        let message = match event {
            ManagerEvent::Stop => return Ok(()),
            ManagerEvent::LidSwitch => {
                synchronize_lid_switch_inhibitor(&manager, shared).await;
                continue;
            }
            ManagerEvent::Properties(change) => {
                let change =
                    change.ok_or_else(|| "logind property change stream ended".to_owned())?;
                if changes_block_inhibitors(&change) {
                    refresh_blocks(&properties, shared).await;
                }
                continue;
            }
            ManagerEvent::Sleep(message) => message,
        };
        let message = message.ok_or_else(|| "PrepareForSleep stream ended".to_owned())?;
        let preparing = message
            .body()
            .deserialize::<bool>()
            .map_err(|error| format!("could not decode PrepareForSleep: {error}"))?;
        if preparing {
            shared.publish(SleepTransition::Preparing);
            info!("logind requested sleep preparation");
        } else {
            // Arm the next cycle before publishing resume. The compositor may
            // finish processing this event immediately and must not release
            // the newly acquired inhibitor as if it belonged to the old one.
            if let Err(error) = acquire_sleep_delay(&manager, shared).await {
                warn!(%error, "could not reacquire the logind sleep delay inhibitor");
            }
            shared.publish(SleepTransition::Resumed);
            info!("logind completed the sleep transition");
        }
    }
}

/// Whether a PropertiesChanged signal of logind's object concerns its block
/// inhibitors.
fn changes_block_inhibitors(message: &zbus::Message) -> bool {
    let Ok((interface, changed, invalidated)) = message.body().deserialize::<(
        String,
        std::collections::HashMap<String, zbus::zvariant::OwnedValue>,
        Vec<String>,
    )>() else {
        return false;
    };
    interface == LOGIND_MANAGER
        && changed
            .keys()
            .map(String::as_str)
            .chain(invalidated.iter().map(String::as_str))
            .any(names_block_inhibitors)
}

fn names_block_inhibitors(property: &str) -> bool {
    matches!(property, "BlockInhibited" | "BlockWeakInhibited")
}

/// Publishes logind's block inhibitors as they are now. A failed read keeps
/// what was known.
async fn refresh_blocks(properties: &zbus::Proxy<'_>, shared: &SleepMonitorShared) {
    match read_blocks(properties).await {
        Ok(blocks) => shared.set_blocks(blocks),
        Err(error) => warn!(%error, "could not read logind's block inhibitors"),
    }
}

/// Reads logind's block inhibitors afresh. BlockWeakInhibited is newer than
/// BlockInhibited (systemd 257); without it, there are no weak blocks.
async fn read_blocks(properties: &zbus::Proxy<'_>) -> Result<LogindBlocks, String> {
    let strong = read_inhibited(properties, "BlockInhibited")
        .await
        .map_err(|error| format!("could not read logind BlockInhibited: {error}"))?;
    let weak = read_inhibited(properties, "BlockWeakInhibited")
        .await
        .unwrap_or_default();
    Ok(LogindBlocks::parse(&strong).union(LogindBlocks::parse(&weak)))
}

async fn read_inhibited(properties: &zbus::Proxy<'_>, name: &str) -> Result<String, String> {
    let value: zbus::zvariant::OwnedValue = properties
        .call("Get", &(LOGIND_MANAGER, name))
        .await
        .map_err(|error| error.to_string())?;
    String::try_from(value).map_err(|error| error.to_string())
}

async fn acquire_sleep_delay(
    manager: &zbus::Proxy<'_>,
    shared: &SleepMonitorShared,
) -> Result<(), String> {
    let inhibitor: zbus::zvariant::OwnedFd = manager
        .call(
            "Inhibit",
            &(
                "sleep",
                "Denial",
                "Secure the compositor session before system sleep",
                "delay",
            ),
        )
        .await
        .map_err(|error| format!("logind Inhibit failed: {error}"))?;
    shared.install_delay_inhibitor(inhibitor.into());
    Ok(())
}

async fn acquire_power_key_inhibitor(
    manager: &zbus::Proxy<'_>,
    shared: &SleepMonitorShared,
) -> Result<(), String> {
    let inhibitor: zbus::zvariant::OwnedFd = manager
        .call(
            "Inhibit",
            &(
                "handle-power-key",
                "Denial",
                "Handle the physical power button through Denial settings",
                "block",
            ),
        )
        .await
        .map_err(|error| format!("logind power-key Inhibit failed: {error}"))?;
    shared.install_power_key_inhibitor(inhibitor.into());
    Ok(())
}

/// Takes logind's lid switch handling if the compositor wants it and it is
/// not held. Letting go needs no logind call and happened already, on the
/// compositor's side. A refused or failed `Inhibit` is tried again on the
/// next change of the setting or the next connection to logind.
async fn synchronize_lid_switch_inhibitor(manager: &zbus::Proxy<'_>, shared: &SleepMonitorShared) {
    if !shared.lid_switch_wanted() || shared.lid_switch_held() {
        return;
    }
    let inhibitor = manager
        .call::<_, _, zbus::zvariant::OwnedFd>("Inhibit", &LID_SWITCH_INHIBITOR)
        .await;
    match inhibitor {
        Ok(inhibitor) => {
            if shared.install_lid_switch_inhibitor(inhibitor.into()) {
                info!("holding logind's lid switch: closing the cover no longer suspends");
            }
        }
        Err(error) => warn!(%error, "logind lid-switch Inhibit failed"),
    }
}

fn synchronize_suspend_mode(mode: crate::idle_policy::SuspendMode) -> Result<(), String> {
    let path = suspend_mode_path()?;
    synchronize_suspend_mode_at(&path, mode)
}

fn remove_suspend_mode_marker() -> Result<(), String> {
    let path = suspend_mode_path()?;
    remove_suspend_mode_marker_at(&path)
}

fn suspend_mode_path() -> Result<PathBuf, String> {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| "XDG_RUNTIME_DIR is required for suspend mode selection".to_owned())?;
    if !runtime.is_absolute() {
        return Err("XDG_RUNTIME_DIR must be absolute for suspend mode selection".to_owned());
    }
    let session = std::env::var("XDG_SESSION_ID")
        .map_err(|_| "XDG_SESSION_ID is required for suspend mode selection".to_owned())?;
    if session.is_empty()
        || !session
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
    {
        return Err("XDG_SESSION_ID is invalid for suspend mode selection".to_owned());
    }
    Ok(runtime
        .join(SUSPEND_MODE_DIRECTORY)
        .join(format!("suspend-mode-{session}")))
}

fn synchronize_suspend_mode_at(
    path: &Path,
    mode: crate::idle_policy::SuspendMode,
) -> Result<(), String> {
    let Some(value) = mode.kernel_value() else {
        return remove_suspend_mode_marker_at(path);
    };
    let parent = path
        .parent()
        .ok_or_else(|| "suspend mode marker has no parent directory".to_owned())?;
    match fs::symlink_metadata(parent) {
        Ok(metadata) if metadata.file_type().is_dir() => {}
        Ok(_) => {
            return Err(format!(
                "suspend mode marker parent {} is not a directory",
                parent.display()
            ));
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            fs::create_dir(parent).map_err(|error| {
                format!(
                    "could not create suspend mode marker directory {}: {error}",
                    parent.display()
                )
            })?
        }
        Err(error) => {
            return Err(format!(
                "could not inspect suspend mode marker directory {}: {error}",
                parent.display()
            ));
        }
    }
    fs::set_permissions(parent, fs::Permissions::from_mode(0o700)).map_err(|error| {
        format!(
            "could not secure suspend mode marker directory {}: {error}",
            parent.display()
        )
    })?;
    if fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_dir()) {
        return Err(format!(
            "suspend mode marker {} is a directory",
            path.display()
        ));
    }
    let sequence = SUSPEND_MODE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let temporary = parent.join(format!(
        ".suspend-mode-{}-{sequence}.tmp",
        std::process::id()
    ));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary)
        .map_err(|error| {
            format!(
                "could not create temporary suspend mode marker {}: {error}",
                temporary.display()
            )
        })?;
    let result = (|| -> io::Result<()> {
        writeln!(file, "{value}")?;
        file.sync_data()?;
        fs::rename(&temporary, path)
    })();
    if let Err(error) = result {
        let _ = fs::remove_file(&temporary);
        return Err(format!(
            "could not commit suspend mode marker {}: {error}",
            path.display()
        ));
    }
    Ok(())
}

fn remove_suspend_mode_marker_at(path: &Path) -> Result<(), String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_dir() => Err(format!(
            "suspend mode marker {} is a directory",
            path.display()
        )),
        Ok(_) => fs::remove_file(path).map_err(|error| {
            format!(
                "could not remove suspend mode marker {}: {error}",
                path.display()
            )
        }),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!(
            "could not inspect suspend mode marker {}: {error}",
            path.display()
        )),
    }
}

fn perform_power_action(
    action: crate::idle_policy::PowerButtonAction,
    interactive: bool,
) -> Result<(), String> {
    let method = action
        .logind_method()
        .ok_or_else(|| "DPMS is not a logind power action".to_owned())?;
    let connection = zbus::blocking::Connection::system()
        .map_err(|error| format!("could not connect to the system bus: {error}"))?;
    let manager = zbus::blocking::Proxy::new(
        &connection,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )
    .map_err(|error| format!("could not open the logind manager: {error}"))?;
    let _: () = manager
        .call(method, &interactive)
        .map_err(|error| format!("logind {method} failed: {error}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_lid_switch_inhibitor_blocks_only_the_lid_handling() {
        let (what, who, _, mode) = LID_SWITCH_INHIBITOR;
        assert_eq!(what, "handle-lid-switch");
        assert_eq!(who, "Denial");
        assert_eq!(mode, "block");
        // A suspend from the power menu or the idle timeout is not held off,
        // and Denial's own idle policy does not count it as a block.
        assert_eq!(LogindBlocks::parse(what), LogindBlocks::default());
    }

    #[test]
    fn only_block_inhibitor_properties_wake_a_reread() {
        assert!(names_block_inhibitors("BlockInhibited"));
        assert!(names_block_inhibitors("BlockWeakInhibited"));
        // Denial's own sleep delay comes and goes with every suspend.
        assert!(!names_block_inhibitors("DelayInhibited"));
        assert!(!names_block_inhibitors("IdleHint"));
    }

    #[test]
    fn explicit_suspend_mode_is_published_and_system_default_removes_it() {
        let root = std::env::temp_dir().join(format!(
            "denial-suspend-mode-{}-{}",
            std::process::id(),
            SUSPEND_MODE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        let marker = root.join("denial/suspend-mode-test");

        synchronize_suspend_mode_at(&marker, crate::idle_policy::SuspendMode::Deep).unwrap();
        assert_eq!(fs::read_to_string(&marker).unwrap(), "deep\n");
        assert_eq!(
            fs::metadata(marker.parent().unwrap())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );

        synchronize_suspend_mode_at(&marker, crate::idle_policy::SuspendMode::SystemDefault)
            .unwrap();
        assert!(!marker.exists());
        fs::remove_dir_all(root).unwrap();
    }
}
