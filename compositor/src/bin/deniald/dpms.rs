//! Display-power request collection, idle policy, and atomic KMS transitions.

use super::kms_render::output_plane_state;
use super::*;

pub(super) fn collect_output_power_requests(events: &mut RuntimeState) {
    let requests = events
        .wayland
        .as_mut()
        .map(wayland_frontend::WaylandFrontend::take_output_power_requests)
        .unwrap_or_default();
    for request in requests {
        #[cfg(feature = "flutter")]
        events
            .idle_policy
            .note_external_power_request(request.output, request.powered);
        events
            .output_power_requests
            .insert(request.output, request.powered);
    }
}

#[derive(Debug, Default)]
pub(super) struct DpmsTopologyGuard {
    parked_outputs: BTreeSet<OutputId>,
    waking_outputs: BTreeSet<OutputId>,
    wake_grace_until: Option<Instant>,
    deferred_removal: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct DeferredDpmsTopology {
    pub(super) missing_outputs: usize,
    pub(super) grace_until: Option<Instant>,
    pub(super) first_observation: bool,
}

impl DpmsTopologyGuard {
    pub(super) fn note_powered_off(&mut self, output: OutputId) {
        self.waking_outputs.remove(&output);
        self.parked_outputs.insert(output);
        if self.waking_outputs.is_empty() {
            self.wake_grace_until = None;
        }
    }

    pub(super) fn note_wake(&mut self, output: OutputId, now: Instant) {
        self.parked_outputs.remove(&output);
        self.waking_outputs.insert(output);
        self.wake_grace_until = Some(now + DPMS_WAKE_TOPOLOGY_GRACE);
    }

    pub(super) fn defer_missing_outputs(
        &mut self,
        now: Instant,
        current: impl IntoIterator<Item = OutputId>,
        observed: impl IntoIterator<Item = OutputId>,
    ) -> Option<DeferredDpmsTopology> {
        self.expire_wake_grace(now);
        let current = current.into_iter().collect::<BTreeSet<_>>();
        let observed = observed.into_iter().collect::<BTreeSet<_>>();
        let missing = current
            .iter()
            .copied()
            .filter(|output| !observed.contains(output))
            .collect::<Vec<_>>();

        if missing.is_empty() {
            // A connector can briefly report connected before another link
            // training event makes it disappear. Keep the output eligible for
            // debounce through the complete wake interval, but cancel any
            // pending removal now that the expected topology was observed.
            self.deferred_removal = false;
            return None;
        }
        if observed.iter().any(|output| !current.contains(output))
            || missing.iter().any(|output| {
                !self.parked_outputs.contains(output) && !self.waking_outputs.contains(output)
            })
        {
            self.cancel();
            return None;
        }

        let grace_until = missing
            .iter()
            .any(|output| self.waking_outputs.contains(output))
            .then_some(self.wake_grace_until)
            .flatten();
        let first_observation = !std::mem::replace(&mut self.deferred_removal, true);
        Some(DeferredDpmsTopology {
            missing_outputs: missing.len(),
            grace_until,
            first_observation,
        })
    }

    pub(super) fn service_deadline(&mut self, now: Instant) -> bool {
        if self.wake_grace_until.is_none_or(|deadline| now < deadline) {
            return false;
        }
        self.waking_outputs.clear();
        self.wake_grace_until = None;
        std::mem::take(&mut self.deferred_removal)
    }

    pub(super) fn limit_dispatch_timeout(&self, now: Instant, timeout: Duration) -> Duration {
        if !self.deferred_removal {
            return timeout;
        }
        self.wake_grace_until.map_or(timeout, |deadline| {
            timeout.min(deadline.saturating_duration_since(now))
        })
    }

    pub(super) fn cancel(&mut self) {
        *self = Self::default();
    }

    fn expire_wake_grace(&mut self, now: Instant) {
        if self
            .wake_grace_until
            .is_some_and(|deadline| now >= deadline)
        {
            self.waking_outputs.clear();
            self.wake_grace_until = None;
            self.deferred_removal = false;
        }
    }
}

/// KEY_WAKEUP, such as a touch controller's double tap, is a key press that
/// also lights the built-in panel, even beside a desk where other keys leave
/// it dark. It never turns a lit panel off and never unlocks.
#[cfg(feature = "flutter")]
pub(super) fn synchronize_wake_key(scanouts: &[Scanout], events: &mut RuntimeState) {
    if !std::mem::take(&mut events.wake_key_pressed) {
        return;
    }
    let panel = scanouts
        .iter()
        .find(|scanout| output_policy::is_internal_panel(&scanout.output.name))
        .filter(|scanout| {
            let output = scanout.output.id;
            let powered = events
                .output_power_requests
                .get(&output)
                .copied()
                .unwrap_or(scanout.powered);
            !powered || events.fingerprint.exclusive_for(output)
        });
    events.note_user_activity();
    let Some(panel) = panel else {
        return;
    };
    events.fingerprint.independent_wake();
    let request = events
        .idle_policy
        .wake_output_now(panel.output.id, Instant::now());
    events.queue_idle_power_requests([request]);
    info!(output = %panel.output.name, "wake key requested display wake");
}

/// The closed cover turns the screen off, so that the suspend timeout counts
/// from the closing, as after the power button. logind locks the session as
/// configured (or Denial holds the lid under Stay awake: then the screen
/// stays on). Beside another display, as logind's HandleLidSwitchDocked, the
/// display policy alone leaves the panel under the cover dark. Opening the
/// cover lights the screen, also when only logind reports it after a resume.
#[cfg(feature = "flutter")]
pub(super) fn synchronize_cover(scanouts: &[Scanout], events: &mut RuntimeState) {
    match events.cover.update(events.lid.closed()) {
        None => {}
        Some(lid_switch::CoverChange::Closed) => {
            let docked = scanouts
                .iter()
                .any(|scanout| !output_policy::is_internal_panel(&scanout.output.name));
            if events.idle_policy.stay_awake() || docked {
                return;
            }
            let outputs = button_outputs(scanouts, events);
            let requests = events.idle_policy.blank_now(outputs);
            if !requests.is_empty() {
                info!("the cover closed: turned the screen off");
            }
            events.queue_idle_power_requests(requests);
        }
        Some(lid_switch::CoverChange::Opened) => events.note_user_activity(),
    }
}

#[cfg(feature = "flutter")]
/// Tells the idle policy whether a desk shares the session with the phone,
/// and locks if the phone's panel is left dark and alone.
#[cfg(feature = "flutter")]
fn synchronize_phone_with_desk(events: &mut RuntimeState, now: Instant) {
    let phone = events
        .wayland
        .as_ref()
        .and_then(wayland_frontend::WaylandFrontend::phone_beside_desk);
    if !events.idle_policy.set_phone_with_desk(phone, now) {
        return;
    }
    if let Some(authentication) = events.authentication.as_ref() {
        if authentication.lock_automatically() {
            synchronize_authentication_boundary(events);
            info!("locked the session: the desk left and the phone is dark");
        }
    } else {
        warn!("could not lock after the desk left: authentication is unavailable");
    }
}

pub(super) fn synchronize_power_button(scanouts: &[Scanout], events: &mut RuntimeState) {
    if events.power_button.take_screenshot() {
        events.screenshot_requested = true;
    }
    #[cfg(feature = "flutter")]
    synchronize_phone_with_desk(events, Instant::now());
    let phone = events.idle_policy.phone_output();
    // In the mobile shell a lit screen goes dark on release, so Volume Down
    // can still make the press a screenshot. A dark screen wakes at once.
    let mobile = events
        .wayland
        .as_ref()
        .is_some_and(|frontend| frontend.mobile_shell());
    let lit = power_button_screen_lit(phone, scanouts, events);
    if events.power_button.take_t3_voice_toggle() && lit && !events.secure_session_locked() {
        if let Some(controls) = events.system_controls.as_ref() {
            controls.adjust_audio(0.05);
        }
        if !events
            .plugin_actions
            .queue(crate::plugin_actions::T3_VOICE_TOGGLE_ACTION.to_owned(), None)
        {
            warn!("the shell has no T3 Code voice action registered");
        } else {
            info!("volume down double-press requested T3 Code voice toggle");
        }
    }
    // Holding the button opens the mobile shell's power menu; on the desktop
    // it does what the user chose, nothing unless asked.
    let long_press = if mobile {
        idle_policy::PowerButtonLongPress::PowerMenu
    } else {
        events.idle_policy.power_button_long_press()
    };
    let has_long_press = long_press != idle_policy::PowerButtonLongPress::Nothing;
    if has_long_press && events.power_button.take_long_press(Instant::now()) {
        if let Some(action) = long_press.system_action() {
            if events
                .system_controls
                .as_ref()
                .is_some_and(|controls| controls.power_button_action(action))
            {
                info!(
                    ?action,
                    "power button long press requested system power action"
                );
            } else {
                warn!(?action, "could not request power-button long-press action");
            }
        } else {
            events.power_menu_requested = true;
            info!("power button long press requested the power menu");
        }
        return;
    }
    // A lit screen acts on release while a long press can still come.
    if !events
        .power_button
        .take_toggle(lit && (mobile || has_long_press))
    {
        return;
    }
    let action = events.idle_policy.power_button_action();
    // Stay awake keeps the screen on: the press neither suspends nor powers
    // off, whatever the button is set to do, and leaves a lit screen lit.
    let stay_awake = events.idle_policy.stay_awake();
    if lit && action != idle_policy::PowerButtonAction::Dpms && !stay_awake {
        let sleep_inhibited = action == idle_policy::PowerButtonAction::Suspend
            && events
                .system_controls
                .as_ref()
                .is_some_and(|controls| controls.logind_blocks().sleep);
        if sleep_inhibited {
            info!(
                "power button suspend is held off by a logind sleep inhibitor; turning the screen off instead"
            );
        } else {
            if events
                .system_controls
                .as_ref()
                .is_some_and(|controls| controls.power_button_action(action))
            {
                info!(?action, "power button requested system power action");
            } else {
                warn!(?action, "could not request power-button system action");
            }
            return;
        }
    }
    if toggle_screen(scanouts, events) {
        info!("power button requested compositor-owned display power toggle");
    } else if stay_awake {
        info!("power button left the screen on: Stay awake is on");
    }
}

/// Whether the screen the power button turns off is lit. An output lit only
/// to draw the always-on clock counts as dark. Beside a desk the button
/// belongs to the phone's panel alone.
fn power_button_screen_lit(
    phone: Option<OutputId>,
    scanouts: &[Scanout],
    events: &RuntimeState,
) -> bool {
    scanouts
        .iter()
        .filter(|scanout| phone.is_none_or(|phone| scanout.output.id == phone))
        .any(|scanout| {
            events
                .output_power_requests
                .get(&scanout.output.id)
                .copied()
                .unwrap_or(scanout.powered)
                && !events.ambient_display.refreshing(scanout.output.id)
        })
}

/// The outputs and whether each is lit, as the power button sees them.
/// Queued requests are the effective state until the atomic KMS gate runs,
/// and an output lit only to draw the always-on clock counts as dark.
fn button_outputs(scanouts: &[Scanout], events: &RuntimeState) -> Vec<(OutputId, bool)> {
    scanouts
        .iter()
        .map(|scanout| {
            let output = scanout.output.id;
            (
                output,
                events
                    .output_power_requests
                    .get(&output)
                    .copied()
                    .unwrap_or(scanout.powered)
                    && !events.ambient_display.refreshing(output),
            )
        })
        .collect()
}

/// Turns the screen off or on as the power button does. Returns whether it
/// did anything: under Stay awake a lit screen stays as it is.
fn toggle_screen(scanouts: &[Scanout], events: &mut RuntimeState) -> bool {
    let outputs = button_outputs(scanouts, events);
    let actions = events.idle_policy.toggle_now(outputs, Instant::now());
    apply_screen_actions(events, actions)
}

/// Turns a lit screen off as the shell asks: its Screen off tile, a double
/// tap. The power button's press, locking alike, except under Stay awake,
/// where it darkens the screen without locking. Returns whether the screen
/// was lit.
#[cfg(feature = "flutter")]
fn turn_screen_off(scanouts: &[Scanout], events: &mut RuntimeState) -> bool {
    let outputs = button_outputs(scanouts, events);
    let actions = events.idle_policy.screen_off_now(outputs, Instant::now());
    apply_screen_actions(events, actions)
}

fn apply_screen_actions(
    events: &mut RuntimeState,
    actions: idle_policy::IdlePolicyActions,
) -> bool {
    if actions.power_requests.is_empty() && !actions.lock {
        return false;
    }
    events.fingerprint.independent_wake();
    if actions.lock {
        if let Some(authentication) = events.authentication.as_ref() {
            // Close the security gate before queuing DPMS off. Waking only
            // restores display power; authentication remains locked.
            if authentication.lock_automatically() {
                synchronize_authentication_boundary(events);
                info!("locked the session before display off");
            }
        } else {
            warn!("could not lock on power button: authentication is unavailable");
        }
    }
    events.queue_idle_power_requests(actions.power_requests);
    true
}

#[cfg(feature = "flutter")]
pub(super) fn synchronize_idle_dpms(scanouts: &[Scanout], events: &mut RuntimeState, now: Instant) {
    // Presentation and the always-on clock own bounded wakes and restore
    // the prior power state.
    if events.fingerprint.active() || events.ambient_display.refresh_under_way() {
        return;
    }
    synchronize_phone_with_desk(events, now);
    // logind's block inhibitors: one on idle holds every inactivity action
    // off, as a visible Wayland inhibitor does; one on sleep holds only the
    // automatic suspend.
    let logind = events
        .system_controls
        .as_ref()
        .map(system_controls::SystemControls::logind_blocks)
        .unwrap_or_default();
    events
        .frontend_mut()
        .set_session_idle_inhibited(logind.idle);
    events.idle_policy.set_sleep_inhibited(logind.sleep, now);
    if let Some(phone) = events.idle_policy.phone_output() {
        let inhibited = events.frontend_mut().phone_idle_inhibited() || logind.idle;
        let powered = scanouts
            .iter()
            .any(|scanout| scanout.output.id == phone && scanout.powered);
        if let Some(request) = events.idle_policy.evaluate_phone(now, inhibited, powered) {
            events.queue_idle_power_requests([request]);
            info!("turned the phone's idle panel off beside the desk");
        }
    }
    let inhibited = events.frontend_mut().idle_inhibited() || logind.idle;
    let idle_policy::IdlePolicyActions {
        power_requests,
        lock,
        suspend,
        suspend_withheld,
    } = events.idle_policy.evaluate(
        now,
        inhibited,
        scanouts
            .iter()
            .map(|scanout| (scanout.output.id, scanout.powered)),
    );
    events.queue_idle_power_requests(power_requests);
    if lock {
        if let Some(authentication) = events.authentication.as_ref() {
            if authentication.lock_automatically() {
                info!("locked the session after inactivity");
            }
        } else {
            warn!("could not lock the session after inactivity: authentication is unavailable");
        }
    }
    if suspend_withheld {
        info!("a logind sleep inhibitor holds the automatic suspend off");
    }
    if suspend {
        if events
            .system_controls
            .as_ref()
            .is_some_and(system_controls::SystemControls::suspend)
        {
            info!("requested system suspend after inactivity");
        } else {
            warn!("could not request system suspend after inactivity");
        }
    }
}

#[cfg(feature = "flutter")]
pub(super) fn synchronize_idle_dpms_configuration(
    runtime: &mut flutter_runtime::FlutterRuntime,
    events: &mut RuntimeState,
) {
    let Some(configuration) = runtime.take_idle_policy() else {
        return;
    };
    if events
        .system_controls
        .as_ref()
        .is_none_or(|controls| !controls.set_suspend_mode(configuration.suspend_mode))
    {
        warn!("could not synchronize the selected suspend mode");
    }
    let requests = events.idle_policy.configure(configuration, Instant::now());
    events.queue_idle_power_requests(requests);
    info!(
        lock_timeout_seconds = configuration.lock_timeout.map(|timeout| timeout.as_secs()),
        dpms_timeout_seconds = configuration.dpms_timeout.map(|timeout| timeout.as_secs()),
        suspend_timeout_seconds = configuration
            .suspend_timeout
            .map(|timeout| timeout.as_secs()),
        suspend_mode = configuration
            .suspend_mode
            .kernel_value()
            .unwrap_or("system-default"),
        power_button_action = ?configuration.power_button_action,
        "configured automatic inactivity policy"
    );
}

#[cfg(feature = "flutter")]
pub(super) fn synchronize_requested_display_power(
    runtime: &mut flutter_runtime::FlutterRuntime,
    scanouts: &[Scanout],
    events: &mut RuntimeState,
) {
    match runtime.take_display_power_request() {
        None => {}
        Some(idle_policy::DisplayPowerRequest::Off) => {
            // The Screen off tile and a double tap to sleep are the power
            // button pressed on a lit screen: beside a desk they turn off the
            // phone's panel alone. Under Stay awake they still darken it,
            // without locking.
            synchronize_phone_with_desk(events, Instant::now());
            if turn_screen_off(scanouts, events) {
                info!("shell turned the screen off as the power button does");
            }
        }
        Some(idle_policy::DisplayPowerRequest::On) => {
            // The idle timer starts again, so the screen stays on for the
            // usual timeout; clients are not told of user activity.
            let requests = events.idle_policy.note_activity(Instant::now());
            events.queue_idle_power_requests(requests);
            info!("requested compositor-owned display power-on");
        }
    }
}

#[cfg(feature = "flutter")]
pub(super) fn apply_output_power_requests(
    runtime: &mut flutter_runtime::FlutterRuntime,
    scheduler: &mut output_scheduler::OutputScheduler,
    swapchain: &mut RenderSwapchains,
    scanouts: &mut [Scanout],
    events: &mut RuntimeState,
) -> Result<bool, Box<dyn Error>> {
    let requests = std::mem::take(&mut events.output_power_requests);
    let mut deferred = BTreeMap::new();
    let mut power_off = Vec::new();
    let mut power_on = Vec::new();
    let mut power_changed = false;

    for (output, powered) in requests {
        let Some(scanout_index) = scanouts
            .iter()
            .position(|scanout| scanout.output.id == output)
        else {
            events
                .idle_policy
                .note_power_failure(output, Instant::now());
            events.frontend_mut().fail_output_power(output);
            continue;
        };
        let current = scanouts[scanout_index].powered;
        if current == powered {
            if powered {
                scheduler.cancel_power_off(output, scanouts);
            }
            if !powered || !scheduler.power_on_pending(output) {
                let announce = !events.ambient_display.refreshing(output);
                events
                    .frontend_mut()
                    .output_power_applied(output, powered, announce);
            }
            continue;
        }

        if powered {
            power_on.push((output, scanout_index));
        } else {
            power_off.push((output, scanout_index));
        }
    }

    // Stop every affected pipeline before disabling any CRTC. This is real
    // DRM DPMS: `clear()` turns off the connector, CRTC, and planes. Like
    // Niri, wake does not recommit this parked framebuffer. The output is
    // re-enabled only after Flutter produces a fresh frame below.
    let mut waiting_for_power_off = false;
    for &(output, _) in &power_off {
        waiting_for_power_off |= scheduler.begin_power_off(runtime, output, scanouts)?;
    }
    if waiting_for_power_off {
        deferred.extend(power_off.iter().map(|(output, _)| (*output, false)));
    } else if !power_off.is_empty() {
        let mut targets = Vec::with_capacity(power_off.len());
        for &(output, scanout_index) in &power_off {
            let framebuffer_index = scheduler
                .scanning_framebuffer_index(output, scanouts)
                .ok_or("DPMS power-off output has no scheduler framebuffer")?;
            targets.push((output, scanout_index, framebuffer_index));
        }

        let mut cleared = Vec::with_capacity(targets.len());
        let mut failure = None;
        for &(output, scanout_index, framebuffer_index) in &targets {
            match scanouts[scanout_index].surface.clear() {
                Ok(()) => cleared.push((output, scanout_index, framebuffer_index)),
                Err(error) => {
                    failure = Some((scanout_index, error.to_string()));
                    break;
                }
            }
        }

        if let Some((failed_index, error)) = failure {
            let mut rollback_failures = Vec::new();
            for &(output, scanout_index, framebuffer_index) in &cleared {
                let pool = swapchain
                    .outputs()
                    .and_then(|outputs| outputs.for_output(output))
                    .ok_or("DPMS rollback output has no physical buffer pool")?;
                let framebuffer = pool
                    .buffers
                    .get(framebuffer_index)
                    .ok_or("DPMS rollback framebuffer exceeds its output pool")?
                    .framebuffer();
                let state = output_plane_state(&scanouts[scanout_index], framebuffer, pool.size);
                let restore = scanouts[scanout_index]
                    .surface
                    .test_state([state.clone()], true)
                    .and_then(|()| scanouts[scanout_index].surface.commit([state], false));
                if let Err(rollback_error) = restore {
                    rollback_failures.push(format!(
                        "{}: {rollback_error}",
                        scanouts[scanout_index].output.name
                    ));
                }
            }
            for &(output, _) in &power_off {
                scheduler.cancel_power_off(output, scanouts);
                events
                    .idle_policy
                    .note_power_failure(output, Instant::now());
                events.frontend_mut().fail_output_power(output);
            }
            warn!(
                output = scanouts[failed_index].output.name,
                %error,
                restored_outputs = cleared.len(),
                requested_outputs = power_off.len(),
                "aborted compositor-owned display power-off batch"
            );
            if !rollback_failures.is_empty() {
                events.kms_presentation_recovery_requested = true;
                warn!(
                    failures = rollback_failures.join("; "),
                    "DPMS power-off rollback needs in-session KMS recovery"
                );
            }
        } else {
            for &(output, scanout_index, _) in &targets {
                scheduler.power_off(runtime, output, scanouts)?;
                scanouts[scanout_index].powered = false;
                events.dpms_topology.note_powered_off(output);
                power_changed = true;
                events.output_control_dirty = true;
                events.pending.remove(&scanouts[scanout_index].output.crtc);
                info!(
                    output = scanouts[scanout_index].output.name,
                    "powered off KMS output through DRM DPMS"
                );
                let announce = !events.ambient_display.refreshing(output);
                events
                    .frontend_mut()
                    .output_power_applied(output, false, announce);
            }
            // Active touch contacts cannot deliver TouchUp once screen_off_touch
            // suppresses the powered-off panel. Cancel them before blanking so
            // neither Flutter nor Wayland clients retain an orphan pointer across
            // sleep/wake cycles.
            wayland_frontend::reset_touch_input_devices(events);
        }
    }

    if !power_on.is_empty() {
        // Resume Flutter to build the lock UI, but KMS remains off until a
        // frame tagged after its layout acknowledgement passes the wake gate.
        runtime.prepare_locked_wake()?;
        for &(output, scanout_index) in &power_on {
            let framebuffer_index = scheduler
                .stable_framebuffer_index(output)
                .ok_or("DPMS wake output has no parked framebuffer")?;
            scheduler.power_on(
                runtime,
                scanout_index,
                framebuffer_index,
                scanouts,
                swapchain
                    .outputs()
                    .ok_or("DPMS wake has no physical output pools")?,
            )?;
            scanouts[scanout_index].powered = true;
            events.dpms_topology.note_wake(output, Instant::now());
            events.topology_dirty = true;
            power_changed = true;
            events.output_control_dirty = true;
            info!(
                output = scanouts[scanout_index].output.name,
                "queued a fresh frame to power on the KMS output"
            );
        }
    }

    runtime.set_outputs_visible(scanouts.iter().any(|scanout| scanout.powered))?;
    events.output_power_requests = deferred;
    // The suspend timeout counts from here once every output is off,
    // whatever turned them off.
    let dark = !scanouts
        .iter()
        .any(|scanout| scanout.powered && !events.ambient_display.refreshing(scanout.output.id));
    events.idle_policy.note_outputs_dark(dark, Instant::now());
    Ok(power_changed)
}

#[cfg(test)]
#[path = "dpms/tests.rs"]
mod tests;
