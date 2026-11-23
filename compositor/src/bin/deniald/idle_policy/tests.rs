use super::*;

fn output(id: u64) -> OutputId {
    OutputId(id)
}

fn configuration(
    lock_timeout: Option<Duration>,
    dpms_timeout: Option<Duration>,
    suspend_timeout: Option<Duration>,
) -> IdlePolicyConfiguration {
    IdlePolicyConfiguration {
        lock_timeout,
        dpms_timeout,
        suspend_timeout,
        suspend_mode: SuspendMode::SystemDefault,
        power_button_action: PowerButtonAction::Dpms,
        power_button_long_press: PowerButtonLongPress::Nothing,
        lock_after_screen_off: None,
    }
}

fn packet(flags: u8, lock_ms: u64, dpms_ms: u64, suspend_ms: u64) -> [u8; PACKET_BYTES] {
    let mut packet = [0; PACKET_BYTES];
    packet[0] = PACKET_VERSION;
    packet[1] = flags;
    packet[8..16].copy_from_slice(&lock_ms.to_le_bytes());
    packet[16..24].copy_from_slice(&dpms_ms.to_le_bytes());
    packet[24..32].copy_from_slice(&suspend_ms.to_le_bytes());
    packet
}

#[test]
fn packet_is_versioned_bounded_ordered_and_preserves_optional_actions() {
    assert_eq!(
        decode_configuration(&packet(
            LOCK_ENABLED | DPMS_ENABLED,
            60_000,
            120_000,
            180_000
        ))
        .unwrap(),
        configuration(
            Some(Duration::from_secs(60)),
            Some(Duration::from_secs(120)),
            None,
        )
    );
    assert_eq!(
        decode_configuration(&0u64.to_le_bytes()).unwrap(),
        IdlePolicyConfiguration::default()
    );
    assert_eq!(
        decode_configuration(&60_000u64.to_le_bytes()).unwrap(),
        configuration(None, Some(Duration::from_secs(60)), None)
    );
    assert!(matches!(
        decode_configuration(&[0; 7]),
        Err(IdlePolicyPacketError::InvalidSize(7))
    ));
    assert!(matches!(
        decode_configuration(&packet(0x80, 1, 1, 1)),
        Err(IdlePolicyPacketError::InvalidFlags(0x80))
    ));
    let mut selected_mode = packet(0, 1, 1, 1);
    selected_mode[2] = SuspendMode::Deep as u8;
    assert_eq!(
        decode_configuration(&selected_mode).unwrap().suspend_mode,
        SuspendMode::Deep
    );
    selected_mode[3] = PowerButtonAction::Hibernate as u8;
    assert_eq!(
        decode_configuration(&selected_mode)
            .unwrap()
            .power_button_action,
        PowerButtonAction::Hibernate
    );
    let mut suspend_mode_configuration = selected_mode;
    suspend_mode_configuration[0] = SUSPEND_MODE_CONFIGURATION_PACKET_VERSION;
    suspend_mode_configuration[3] = 0;
    assert_eq!(
        decode_configuration(&suspend_mode_configuration)
            .unwrap()
            .power_button_action,
        PowerButtonAction::Dpms
    );
    let mut legacy_configuration = selected_mode;
    legacy_configuration[0] = LEGACY_CONFIGURATION_PACKET_VERSION;
    legacy_configuration[2] = 0;
    legacy_configuration[3] = 0;
    assert_eq!(
        decode_configuration(&legacy_configuration)
            .unwrap()
            .suspend_mode,
        SuspendMode::SystemDefault
    );
    selected_mode[2] = 99;
    assert!(matches!(
        decode_configuration(&selected_mode),
        Err(IdlePolicyPacketError::InvalidSuspendMode(99))
    ));
    selected_mode[2] = SuspendMode::SystemDefault as u8;
    selected_mode[3] = 9;
    assert!(matches!(
        decode_configuration(&selected_mode),
        Err(IdlePolicyPacketError::InvalidPowerButtonAction(9))
    ));
    assert!(matches!(
        decode_configuration(&packet(0, 0, 1, 1)),
        Err(IdlePolicyPacketError::ZeroTimeout("lock"))
    ));
    // The suspend counts from the screen going dark: it may be shorter than
    // the lock and display timeouts.
    assert_eq!(
        decode_configuration(&packet(
            LOCK_ENABLED | DPMS_ENABLED | SUSPEND_ENABLED,
            2_000,
            3_000,
            1_000
        ))
        .unwrap(),
        configuration(
            Some(Duration::from_secs(2)),
            Some(Duration::from_secs(3)),
            Some(Duration::from_secs(1)),
        )
    );
    let too_large = u64::try_from(MAX_TIMEOUT.as_millis()).unwrap() + 1;
    assert!(matches!(
        decode_configuration(&packet(0, 1, 1, too_large)),
        Err(IdlePolicyPacketError::TimeoutTooLarge {
            action: "suspend",
            milliseconds,
        }) if milliseconds == too_large
    ));
}

#[test]
fn version_five_packs_the_long_press_over_the_power_button_action() {
    let mut packet = packet(0, 1, 1, 1);
    packet[3] = (PowerButtonLongPress::PowerMenu as u8) << 4 | PowerButtonAction::Suspend as u8;
    let configuration = decode_configuration(&packet).unwrap();
    assert_eq!(
        configuration.power_button_action,
        PowerButtonAction::Suspend
    );
    assert_eq!(
        configuration.power_button_long_press,
        PowerButtonLongPress::PowerMenu
    );
    packet[3] = 5 << 4;
    assert!(matches!(
        decode_configuration(&packet),
        Err(IdlePolicyPacketError::InvalidPowerButtonLongPress(5))
    ));
    // Version 4 has no long press: its high nibble is the action's.
    packet[0] = SCREEN_OFF_LOCK_PACKET_VERSION;
    packet[3] = 1 << 4;
    assert!(matches!(
        decode_configuration(&packet),
        Err(IdlePolicyPacketError::InvalidPowerButtonAction(0x10))
    ));
    packet[3] = PowerButtonAction::PowerOff as u8;
    assert_eq!(
        decode_configuration(&packet)
            .unwrap()
            .power_button_long_press,
        PowerButtonLongPress::Nothing
    );
}

#[test]
fn held_power_button_is_a_long_press_only_while_its_toggle_waits() {
    let start = Instant::now();
    let mut button = PowerButton::default();
    button.note_key("pmic", true, true, start);
    assert!(!button.take_toggle(true));
    assert!(!button.take_long_press(start + LONG_PRESS / 2));
    assert_eq!(
        button.limit_dispatch_timeout(start, Duration::from_secs(1)),
        LONG_PRESS
    );
    assert!(button.take_long_press(start + LONG_PRESS));
    button.note_key("pmic", false, true, start + LONG_PRESS * 2);
    assert!(!button.take_toggle(true), "the long press took the release");

    // A short press still toggles on release.
    button.note_key("pmic", true, true, start);
    button.note_key("pmic", false, true, start + LONG_PRESS / 2);
    assert!(!button.take_long_press(start + LONG_PRESS));
    assert!(button.take_toggle(true));

    // A press that acted at once, as on a dark screen, holds no long press.
    button.note_key("pmic", true, false, start);
    assert!(button.take_toggle(false));
    assert!(!button.take_long_press(start + LONG_PRESS));
    assert_eq!(
        button.limit_dispatch_timeout(start, Duration::from_secs(1)),
        Duration::from_secs(1)
    );

    // Volume Down makes it a screenshot, never a long press.
    button.note_key("pmic", false, false, start);
    button.note_key("pmic", true, true, start);
    assert_eq!(button.note_volume_down(true, true), VolumeDownRoute::Take);
    assert!(!button.take_long_press(start + LONG_PRESS));
}

#[test]
fn display_power_packet_is_one_known_byte() {
    assert_eq!(decode_display_power(&[1]), Ok(DisplayPowerRequest::Off));
    assert_eq!(decode_display_power(&[2]), Ok(DisplayPowerRequest::On));
    for packet in [&[][..], &[0], &[3], &[1, 0]] {
        assert_eq!(
            decode_display_power(packet),
            Err(DisplayPowerPacketError::InvalidPacket)
        );
    }
}

#[test]
fn power_button_system_actions_map_to_logind_methods() {
    assert_eq!(PowerButtonAction::Dpms.logind_method(), None);
    assert_eq!(PowerButtonAction::Suspend.logind_method(), Some("Suspend"));
    assert_eq!(
        PowerButtonAction::Hibernate.logind_method(),
        Some("Hibernate")
    );
    assert_eq!(
        PowerButtonAction::PowerOff.logind_method(),
        Some("PowerOff")
    );
}

#[test]
fn power_button_toggles_once_per_press_and_consumes_release() {
    let mut button = PowerButton::default();
    button.note_key("pmic", true, false, Instant::now());
    assert!(button.take_toggle(false));
    button.note_key("pmic", true, false, Instant::now());
    button.note_key("pmic", false, false, Instant::now());
    assert!(!button.take_toggle(false));
    button.note_key("pmic", true, false, Instant::now());
    assert!(button.take_toggle(false));
    button.remove_device("pmic");
    button.note_key("pmic", true, false, Instant::now());
    assert!(button.take_toggle(false));
}

#[test]
fn two_power_presses_in_one_dispatch_leave_power_unchanged() {
    let mut button = PowerButton::default();
    for _ in 0..2 {
        button.note_key("pmic", true, false, Instant::now());
        button.note_key("pmic", false, false, Instant::now());
    }
    assert!(!button.take_toggle(false));
}

#[test]
fn power_then_volume_down_takes_a_screenshot_instead_of_the_toggle() {
    let mut button = PowerButton::default();
    button.note_key("pmic", true, true, Instant::now());
    assert!(!button.take_toggle(true), "waits for the release");
    assert_eq!(button.note_volume_down(true, true), VolumeDownRoute::Take);
    assert!(button.take_screenshot());
    button.note_key("pmic", false, true, Instant::now());
    assert!(!button.take_toggle(true));
    assert_eq!(button.note_volume_down(false, true), VolumeDownRoute::Take);
    assert!(!button.take_screenshot());
}

#[test]
fn volume_down_then_power_takes_a_screenshot_and_no_volume_step() {
    let mut button = PowerButton::default();
    assert_eq!(
        button.note_volume_down(true, true),
        VolumeDownRoute::HoldBack
    );
    button.note_key("pmic", true, true, Instant::now());
    assert!(button.take_screenshot());
    assert!(
        !button.take_held_volume_down(),
        "the press never reaches the seat"
    );
    button.note_key("pmic", false, true, Instant::now());
    assert!(!button.take_toggle(true));
    assert_eq!(button.note_volume_down(false, true), VolumeDownRoute::Take);
}

#[test]
fn held_back_volume_down_is_delivered_when_power_does_not_follow() {
    let mut button = PowerButton::default();
    assert_eq!(
        button.note_volume_down(true, true),
        VolumeDownRoute::HoldBack
    );
    assert!(button.take_held_volume_down());
    assert_eq!(
        button.note_volume_down(false, true),
        VolumeDownRoute::Deliver
    );

    // A quick tap releases before the wait ends.
    assert_eq!(
        button.note_volume_down(true, true),
        VolumeDownRoute::HoldBack
    );
    assert_eq!(
        button.note_volume_down(false, true),
        VolumeDownRoute::DeliverHeldPress
    );
    assert!(!button.take_held_volume_down());

    // Power after the press went through: a screenshot, the keys stay volume.
    assert_eq!(
        button.note_volume_down(true, true),
        VolumeDownRoute::HoldBack
    );
    assert!(button.take_held_volume_down());
    button.note_key("pmic", true, true, Instant::now());
    assert!(button.take_screenshot());
    button.note_key("pmic", false, true, Instant::now());
    assert_eq!(
        button.note_volume_down(false, true),
        VolumeDownRoute::Deliver
    );
}

#[test]
fn power_alone_toggles_on_release_with_chords_and_volume_stays_volume() {
    let mut button = PowerButton::default();
    button.note_key("pmic", true, true, Instant::now());
    button.note_key("pmic", false, true, Instant::now());
    assert!(button.take_toggle(true));
    assert!(!button.take_screenshot());

    // Without chords, Volume Down never waits or joins Power.
    button.note_key("pmic", true, false, Instant::now());
    assert_eq!(
        button.note_volume_down(true, false),
        VolumeDownRoute::Deliver
    );
    assert!(button.take_toggle(false));
    assert!(!button.take_screenshot());
    assert_eq!(
        button.note_volume_down(false, false),
        VolumeDownRoute::Deliver
    );
}

#[test]
fn power_button_wakes_double_tap_and_external_blank_and_resets_idle() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.blank_now([(output(1), true)]);
    assert_eq!(
        policy.toggle_now([(output(1), false)], now).power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
    assert!(policy.note_activity(now).is_empty());
    assert_eq!(
        policy.toggle_now([(output(1), true)], now).power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    policy.note_external_power_request(output(1), false);
    assert_eq!(
        policy.toggle_now([(output(1), false)], now).power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
    assert_eq!(policy.last_activity, now);
}

#[test]
fn idle_inhibitor_cannot_undo_a_power_button_blank() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.toggle_now([(output(1), true)], now);
    assert!(
        policy
            .evaluate(now, true, [(output(1), false)])
            .power_requests
            .is_empty()
    );
    assert_eq!(
        policy.toggle_now([(output(1), false)], now).power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
}

#[test]
fn power_button_locks_when_blanking_but_does_not_relock_on_wake() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(Some(Duration::from_secs(300)), None, None),
        now,
    );
    let sleep = policy.toggle_now([(output(1), true)], now);
    assert!(sleep.lock);
    assert!(!sleep.suspend);
    assert!(!sleep.power_requests[0].powered);

    let wake = policy.toggle_now([(output(1), false)], now);
    assert!(!wake.lock);
    assert!(!wake.suspend);
    assert!(wake.power_requests[0].powered);
    assert!(!policy.toggle_now([], now).lock);
}

#[test]
fn power_button_does_not_lock_when_locking_is_off() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(configuration(None, None, None), now);
    let sleep = policy.toggle_now([(output(1), true)], now);
    assert!(!sleep.lock);
    assert!(!sleep.power_requests[0].powered);
}

#[test]
fn explicit_blank_uses_native_input_to_wake_without_an_idle_timeout() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    assert_eq!(
        policy.blank_now([(output(1), true), (output(2), false)]),
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    assert_eq!(
        policy.note_activity(started),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
}

#[test]
fn inactivity_triggers_lock_dpms_and_suspend_once_in_threshold_order() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(5)),
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(5)),
        ),
        started,
    );

    let lock = policy.evaluate(
        started + Duration::from_secs(5),
        false,
        [(output(1), true), (output(2), false)],
    );
    assert!(lock.lock);
    assert!(!lock.suspend);
    assert!(lock.power_requests.is_empty());

    let dpms = policy.evaluate(
        started + Duration::from_secs(10),
        false,
        [(output(1), true), (output(2), false)],
    );
    assert!(!dpms.lock);
    assert!(!dpms.suspend);
    assert_eq!(
        dpms.power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    // The compositor commits the power-off: the suspend counts from there.
    policy.note_outputs_dark(true, started + Duration::from_secs(10));
    assert_eq!(
        policy.next_deadline(),
        Some(started + Duration::from_secs(15))
    );
    assert!(
        !policy
            .evaluate(
                started + Duration::from_secs(14),
                false,
                [(output(1), false), (output(2), false)],
            )
            .suspend
    );

    let suspend = policy.evaluate(
        started + Duration::from_secs(15),
        false,
        [(output(1), false), (output(2), false)],
    );
    assert!(!suspend.lock);
    assert!(suspend.suspend);
    assert!(suspend.power_requests.is_empty());
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(20),
                false,
                [(output(1), false)],
            )
            .eq(&IdlePolicyActions::default())
    );

    assert_eq!(
        policy.note_activity(started + Duration::from_secs(21)),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(26),
                false,
                [(output(1), true)],
            )
            .lock
    );
}

#[test]
fn resume_without_input_suspends_again_after_a_fresh_interval() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(5)),
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(5)),
        ),
        started,
    );
    policy.evaluate(started + Duration::from_secs(5), false, [(output(1), true)]);
    policy.evaluate(
        started + Duration::from_secs(10),
        false,
        [(output(1), true)],
    );
    policy.note_outputs_dark(true, started + Duration::from_secs(10));
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(15),
                false,
                [(output(1), false)]
            )
            .suspend
    );
    assert_eq!(policy.next_deadline(), None);

    // An alarm wakes the system; `Instant` did not advance during sleep. The
    // screen stays dark, and the suspend counts again from the resume.
    let resumed = started + Duration::from_secs(16);
    policy.note_resume(resumed);
    assert_eq!(
        policy.next_deadline(),
        Some(resumed + Duration::from_secs(5))
    );
    let early = policy.evaluate(
        resumed + Duration::from_secs(1),
        false,
        [(output(1), false)],
    );
    assert!(!early.suspend);
    assert!(early.power_requests.is_empty());

    let again = policy.evaluate(
        resumed + Duration::from_secs(5),
        false,
        [(output(1), false)],
    );
    assert!(again.suspend);
    assert!(again.power_requests.is_empty());

    // A touch still lights the screen the idle policy blanked.
    assert_eq!(
        policy.note_activity(resumed + Duration::from_secs(20)),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
}

#[test]
fn the_suspend_counts_from_the_committed_display_power_off() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            None,
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(5)),
        ),
        started,
    );

    let first = policy.evaluate(
        started + Duration::from_secs(10),
        false,
        [(output(1), true)],
    );
    assert!(!first.suspend);
    assert_eq!(first.power_requests.len(), 1);
    // Not dark yet: nothing to count from.
    assert_eq!(policy.next_deadline(), None);
    assert!(
        !policy
            .evaluate(
                started + Duration::from_secs(10),
                false,
                [(output(1), true)],
            )
            .suspend
    );

    let committed = started + Duration::from_millis(10_200);
    policy.note_outputs_dark(true, committed);
    assert_eq!(
        policy.next_deadline(),
        Some(committed + Duration::from_secs(5))
    );
    assert!(
        !policy
            .evaluate(
                started + Duration::from_secs(15),
                false,
                [(output(1), false)],
            )
            .suspend
    );
    assert!(
        policy
            .evaluate(
                committed + Duration::from_secs(5),
                false,
                [(output(1), false)]
            )
            .suspend
    );
}

#[test]
fn equal_lock_and_dpms_thresholds_delay_lock_until_after_display_off() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(10)),
            None,
        ),
        started,
    );

    let display_off = policy.evaluate(
        started + Duration::from_secs(10),
        false,
        [(output(1), true)],
    );
    assert!(!display_off.lock);
    assert_eq!(
        display_off.power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    assert_eq!(
        policy.next_deadline(),
        Some(started + Duration::from_secs(15))
    );
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(14),
                false,
                [(output(1), false)],
            )
            .eq(&IdlePolicyActions::default())
    );

    let lock = policy.evaluate(
        started + Duration::from_secs(15),
        false,
        [(output(1), false)],
    );
    assert!(lock.lock);
    assert!(lock.power_requests.is_empty());
}

#[test]
fn the_suspend_does_not_wait_for_a_later_idle_lock() {
    // The sleep transition locks the session before the system sleeps.
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(60)),
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(5)),
        ),
        started,
    );
    let display_off = policy.evaluate(
        started + Duration::from_secs(10),
        false,
        [(output(1), true)],
    );
    assert_eq!(display_off.power_requests.len(), 1);
    policy.note_outputs_dark(true, started + Duration::from_secs(10));
    let suspend = policy.evaluate(
        started + Duration::from_secs(15),
        false,
        [(output(1), false)],
    );
    assert!(suspend.suspend);
    assert!(!suspend.lock);
}

#[test]
fn disabled_dpms_does_not_delay_an_equal_configured_lock_timeout() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(Some(Duration::from_secs(10)), None, None),
        started,
    );

    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(10),
                false,
                [(output(1), true)],
            )
            .lock
    );
}

#[test]
fn inhibition_resets_every_action_and_can_wake_a_blanked_output() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(5)),
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(15)),
        ),
        started,
    );
    assert!(
        !policy
            .evaluate(
                started + Duration::from_secs(10),
                false,
                [(output(7), true)],
            )
            .power_requests[0]
            .powered
    );
    assert_eq!(
        policy
            .evaluate(
                started + Duration::from_secs(11),
                true,
                [(output(7), false)],
            )
            .power_requests,
        [IdlePowerRequest {
            output: output(7),
            powered: true,
        }]
    );
    assert!(
        policy
            .evaluate(started + Duration::from_secs(50), true, [(output(7), true)],)
            .eq(&IdlePolicyActions::default())
    );
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(51),
                false,
                [(output(7), true)],
            )
            .eq(&IdlePolicyActions::default())
    );
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(56),
                false,
                [(output(7), true)],
            )
            .lock
    );
}

#[test]
fn manual_power_request_is_not_undone_by_activity() {
    let started = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(None, Some(Duration::from_secs(1)), None),
        started,
    );
    policy.evaluate(started + Duration::from_secs(1), false, [(output(3), true)]);
    policy.note_external_power_request(output(3), false);
    assert!(
        policy
            .note_activity(started + Duration::from_secs(2))
            .is_empty()
    );
}

#[test]
fn hardware_wake_is_one_way_targets_one_output_and_resets_idle() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(configuration(None, Some(Duration::from_secs(1)), None), now);
    policy.blank_now([(output(1), true), (output(2), true)]);
    policy.note_external_power_request(output(1), false);
    let request = policy.wake_output_now(output(1), now + Duration::from_secs(2));
    assert_eq!(
        request,
        IdlePowerRequest {
            output: output(1),
            powered: true
        }
    );
    assert!(policy.blanked_outputs.contains(&output(2)));
    assert_eq!(
        policy.wake_output_now(output(1), now + Duration::from_secs(2)),
        request
    );
    assert!(
        policy
            .evaluate(
                now + Duration::from_millis(2500),
                false,
                [(output(1), true), (output(2), false)]
            )
            .power_requests
            .is_empty()
    );
}

#[test]
fn screen_off_lock_delay_is_a_version_four_flag() {
    let mut delayed = packet(
        DPMS_ENABLED | SCREEN_OFF_LOCK_ENABLED,
        60_000,
        30_000,
        60_000,
    );
    delayed[4..8].copy_from_slice(&5_000u32.to_le_bytes());
    assert_eq!(
        decode_configuration(&delayed)
            .unwrap()
            .lock_after_screen_off,
        Some(Duration::from_secs(5))
    );
    let mut at_once = delayed;
    at_once[4..8].fill(0);
    assert_eq!(
        decode_configuration(&at_once)
            .unwrap()
            .lock_after_screen_off,
        Some(Duration::ZERO)
    );
    let mut stray = delayed;
    stray[1] = DPMS_ENABLED;
    assert_eq!(
        decode_configuration(&stray),
        Err(IdlePolicyPacketError::NonZeroReservedBytes)
    );
    let mut older = at_once;
    older[0] = POWER_BUTTON_CONFIGURATION_PACKET_VERSION;
    assert_eq!(
        decode_configuration(&older),
        Err(IdlePolicyPacketError::InvalidFlags(
            DPMS_ENABLED | SCREEN_OFF_LOCK_ENABLED
        ))
    );
}

#[test]
fn power_button_locks_after_the_screen_off_delay_unless_woken() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::from_secs(5)),
            ..configuration(None, None, None)
        },
        now,
    );
    let sleep = policy.toggle_now([(output(1), true)], now);
    assert!(!sleep.lock);
    assert_eq!(policy.next_deadline(), Some(now + Duration::from_secs(5)));
    // Playback holds idling off, not the lock of a screen turned off.
    assert!(
        !policy
            .evaluate(now + Duration::from_secs(4), true, [(output(1), false)])
            .lock
    );
    assert!(
        policy
            .evaluate(now + Duration::from_secs(5), true, [(output(1), false)])
            .lock
    );
    assert_eq!(policy.next_deadline(), None);

    policy.toggle_now([(output(1), false)], now);
    policy.toggle_now([(output(1), true)], now);
    policy.toggle_now([(output(1), false)], now + Duration::from_secs(1));
    assert_eq!(policy.next_deadline(), None);
    assert!(
        !policy
            .evaluate(now + Duration::from_secs(9), false, [(output(1), true)])
            .lock
    );
}

#[test]
fn idle_screen_off_starts_the_lock_delay_and_zero_locks_with_it() {
    let now = Instant::now();
    let dpms = Duration::from_secs(30);
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::from_secs(10)),
            ..configuration(None, Some(dpms), None)
        },
        now,
    );
    let off = policy.evaluate(now + dpms, false, [(output(1), true)]);
    assert!(!off.power_requests[0].powered);
    assert!(!off.lock);
    assert_eq!(
        policy.next_deadline(),
        Some(now + dpms + Duration::from_secs(10))
    );
    assert!(
        policy
            .evaluate(
                now + dpms + Duration::from_secs(10),
                false,
                [(output(1), false)]
            )
            .lock
    );

    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::ZERO),
            ..configuration(None, Some(dpms), None)
        },
        now,
    );
    assert!(policy.evaluate(now + dpms, false, [(output(1), true)]).lock);
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::ZERO),
            ..configuration(None, None, None)
        },
        now,
    );
    assert!(policy.toggle_now([(output(1), true)], now).lock);
}

fn phone_beside_desk(now: Instant) -> IdlePolicy {
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(300)),
            Some(Duration::from_secs(30)),
            Some(Duration::from_secs(600)),
        ),
        now,
    );
    assert!(!policy.set_phone_with_desk(Some(output(1)), now));
    policy
}

#[test]
fn power_button_beside_a_desk_toggles_only_the_phone_and_never_locks() {
    let now = Instant::now();
    let mut policy = phone_beside_desk(now);
    let off = policy.toggle_now([(output(1), true), (output(2), true)], now);
    assert_eq!(
        off.power_requests,
        vec![IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    assert!(!off.lock);
    // Typing at the desk does not light the phone again.
    assert!(
        policy
            .note_activity(now + Duration::from_secs(1))
            .is_empty()
    );
    let on = policy.toggle_now([(output(1), false), (output(2), true)], now);
    assert_eq!(
        on.power_requests,
        vec![IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
}

#[test]
fn phone_panel_idles_on_its_own_clock_beside_a_desk() {
    let now = Instant::now();
    let mut policy = phone_beside_desk(now);
    let later = now + Duration::from_secs(31);
    // The desk was in use the whole time; the phone was not touched.
    policy.note_activity(later - Duration::from_secs(1));
    assert_eq!(
        policy.evaluate_phone(later, false, true),
        Some(IdlePowerRequest {
            output: output(1),
            powered: false,
        })
    );
    let actions = policy.evaluate(later, false, [(output(1), true), (output(2), true)]);
    assert!(actions.power_requests.is_empty());
    assert!(!actions.lock && !actions.suspend);
    // A phone video holds its panel lit.
    let mut policy = phone_beside_desk(now);
    assert_eq!(policy.evaluate_phone(later, true, true), None);
}

#[test]
fn desk_idle_leaves_the_phone_to_its_own_clock_and_never_suspends_while_lit() {
    let now = Instant::now();
    let mut policy = phone_beside_desk(now);
    policy.note_phone_touch(now + Duration::from_secs(29));
    let actions = policy.evaluate(
        now + Duration::from_secs(31),
        false,
        [(output(1), true), (output(2), true)],
    );
    assert_eq!(
        actions.power_requests,
        vec![IdlePowerRequest {
            output: output(2),
            powered: false,
        }]
    );
    let actions = policy.evaluate(
        now + Duration::from_secs(700),
        false,
        [(output(1), true), (output(2), false)],
    );
    assert!(!actions.suspend);
}

#[test]
fn desk_leaving_a_dark_phone_locks_it() {
    let now = Instant::now();
    let mut policy = phone_beside_desk(now);
    policy.toggle_now([(output(1), true), (output(2), true)], now);
    assert!(policy.set_phone_with_desk(None, now));
    let mut policy = phone_beside_desk(now);
    assert!(!policy.set_phone_with_desk(None, now));
}

fn sleep_test_policy(started: Instant) -> IdlePolicy {
    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(
            Some(Duration::from_secs(5)),
            Some(Duration::from_secs(10)),
            Some(Duration::from_secs(5)),
        ),
        started,
    );
    policy
}

/// The display timeout as the compositor carries it out: the power-off is
/// asked for and committed at `at`.
fn idle_screen_off(policy: &mut IdlePolicy, at: Instant) {
    let dpms = policy.evaluate(at, false, [(output(1), true)]);
    assert_eq!(
        dpms.power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    policy.note_outputs_dark(true, at);
}

#[test]
fn sleep_inhibitor_lets_the_screen_lock_and_go_dark_but_holds_suspend_off() {
    let started = Instant::now();
    let mut policy = sleep_test_policy(started);
    policy.set_sleep_inhibited(true, started + Duration::from_secs(1));

    let lock = policy.evaluate(started + Duration::from_secs(5), false, [(output(1), true)]);
    assert!(lock.lock);
    idle_screen_off(&mut policy, started + Duration::from_secs(10));

    let held = policy.evaluate(
        started + Duration::from_secs(15),
        false,
        [(output(1), false)],
    );
    assert!(!held.suspend);
    assert!(held.suspend_withheld);
    // Reported once; nothing more to wait for, so the loop sleeps until the
    // inhibitor's end wakes it.
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(60),
                false,
                [(output(1), false)],
            )
            .eq(&IdlePolicyActions::default())
    );
    assert_eq!(policy.next_deadline(), None);

    // The inhibitor ends: a full suspend timeout counts from there, and the
    // dark, locked screen stays as it is.
    let released = started + Duration::from_secs(100);
    policy.set_sleep_inhibited(false, released);
    assert_eq!(
        policy.next_deadline(),
        Some(released + Duration::from_secs(5))
    );
    let early = policy.evaluate(
        released + Duration::from_secs(4),
        false,
        [(output(1), false)],
    );
    assert!(early.eq(&IdlePolicyActions::default()));
    let suspend = policy.evaluate(
        released + Duration::from_secs(5),
        false,
        [(output(1), false)],
    );
    assert!(suspend.suspend);
    assert!(!suspend.suspend_withheld);
    assert!(suspend.power_requests.is_empty());
    assert!(!suspend.lock);
}

#[test]
fn a_sleep_inhibitor_that_ended_while_the_screen_was_lit_moves_nothing() {
    let started = Instant::now();
    let mut policy = sleep_test_policy(started);
    policy.set_sleep_inhibited(true, started + Duration::from_secs(1));
    // Repeating the same state is no edge.
    policy.set_sleep_inhibited(true, started + Duration::from_secs(2));
    policy.set_sleep_inhibited(false, started + Duration::from_secs(3));
    // Repeated releases do not move the deadline again.
    policy.set_sleep_inhibited(false, started + Duration::from_secs(4));

    policy.evaluate(started + Duration::from_secs(5), false, [(output(1), true)]);
    idle_screen_off(&mut policy, started + Duration::from_secs(10));
    assert_eq!(
        policy.next_deadline(),
        Some(started + Duration::from_secs(15))
    );
    assert!(
        !policy
            .evaluate(
                started + Duration::from_secs(14),
                false,
                [(output(1), false)],
            )
            .suspend
    );
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(15),
                false,
                [(output(1), false)],
            )
            .suspend
    );
}

#[test]
fn activity_under_a_sleep_inhibitor_restarts_the_interval_and_the_report() {
    let started = Instant::now();
    let mut policy = sleep_test_policy(started);
    policy.set_sleep_inhibited(true, started);
    policy.evaluate(started + Duration::from_secs(5), false, [(output(1), true)]);
    idle_screen_off(&mut policy, started + Duration::from_secs(10));
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(15),
                false,
                [(output(1), false)],
            )
            .suspend_withheld
    );

    let touched = started + Duration::from_secs(20);
    assert_eq!(
        policy.note_activity(touched),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
    policy.note_outputs_dark(false, touched);
    assert!(
        policy
            .evaluate(touched + Duration::from_secs(5), false, [(output(1), true)])
            .lock
    );
    idle_screen_off(&mut policy, touched + Duration::from_secs(10));
    let held = policy.evaluate(
        touched + Duration::from_secs(15),
        false,
        [(output(1), false)],
    );
    assert!(held.suspend_withheld);
    assert!(!held.suspend);
}

#[test]
fn end_of_a_sleep_inhibitor_asks_again_for_a_refused_suspend() {
    let started = Instant::now();
    let mut policy = sleep_test_policy(started);
    policy.evaluate(started + Duration::from_secs(5), false, [(output(1), true)]);
    idle_screen_off(&mut policy, started + Duration::from_secs(10));
    // logind refused this one: an inhibitor appeared just before it.
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(15),
                false,
                [(output(1), false)],
            )
            .suspend
    );
    policy.set_sleep_inhibited(true, started + Duration::from_secs(16));
    assert_eq!(policy.next_deadline(), None);
    policy.set_sleep_inhibited(false, started + Duration::from_secs(30));
    assert!(
        !policy
            .evaluate(
                started + Duration::from_secs(34),
                false,
                [(output(1), false)],
            )
            .suspend
    );
    assert!(
        policy
            .evaluate(
                started + Duration::from_secs(35),
                false,
                [(output(1), false)],
            )
            .suspend
    );
}

#[test]
fn idle_inhibitor_over_a_sleep_inhibitor_holds_everything_until_both_end() {
    let started = Instant::now();
    let mut policy = sleep_test_policy(started);
    policy.set_sleep_inhibited(true, started);
    // logind's block on idle reaches the policy as an inhibition, as a
    // visible Wayland inhibitor does.
    for second in [5, 10, 15, 100] {
        assert!(
            policy
                .evaluate(
                    started + Duration::from_secs(second),
                    true,
                    [(output(1), true)],
                )
                .eq(&IdlePolicyActions::default())
        );
    }
    assert_eq!(policy.next_deadline(), None);

    // The idle block ends first: lock and display power-off count again, a
    // suspend still waits for the sleep block.
    let idle_released = started + Duration::from_secs(200);
    policy.evaluate(idle_released, false, [(output(1), true)]);
    assert_eq!(
        policy.next_deadline(),
        Some(idle_released + Duration::from_secs(5))
    );
    policy.evaluate(
        idle_released + Duration::from_secs(5),
        false,
        [(output(1), true)],
    );
    idle_screen_off(&mut policy, idle_released + Duration::from_secs(10));
    let held = policy.evaluate(
        idle_released + Duration::from_secs(15),
        false,
        [(output(1), false)],
    );
    assert!(!held.suspend);
    assert!(held.suspend_withheld);

    let sleep_released = idle_released + Duration::from_secs(20);
    policy.set_sleep_inhibited(false, sleep_released);
    assert!(
        policy
            .evaluate(
                sleep_released + Duration::from_secs(5),
                false,
                [(output(1), false)],
            )
            .suspend
    );
}

/// The phone's policy as the mobile shell configures it on the tablet: the
/// screen goes dark after 30 s and locks with it, and the system suspends
/// after 5 min.
fn phone_policy(now: Instant) -> IdlePolicy {
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::ZERO),
            ..configuration(
                None,
                Some(Duration::from_secs(30)),
                Some(Duration::from_secs(300)),
            )
        },
        now,
    );
    policy
}

#[test]
fn stay_awake_keeps_the_screen_on_and_unlocked_through_inactivity() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    assert!(policy.set_stay_awake(true, now).is_empty());
    assert!(policy.stay_awake());
    // Nothing is due: the compositor sleeps until input or a setting.
    assert_eq!(policy.next_deadline(), None);
    for idle in [30, 31, 300, 3600] {
        let actions = policy.evaluate(now + Duration::from_secs(idle), false, [(output(1), true)]);
        assert_eq!(actions, IdlePolicyActions::default(), "after {idle} s");
    }

    // Off again: a full interval counts from that moment.
    let off = now + Duration::from_secs(3600);
    assert!(policy.set_stay_awake(false, off).is_empty());
    assert_eq!(policy.next_deadline(), Some(off + Duration::from_secs(30)));
    let dark = policy.evaluate(off + Duration::from_secs(30), false, [(output(1), true)]);
    assert!(!dark.power_requests[0].powered);
    assert!(dark.lock);
}

#[test]
fn stay_awake_lights_a_screen_that_went_dark_and_drops_its_pending_lock() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::from_secs(10)),
            ..configuration(None, Some(Duration::from_secs(30)), None)
        },
        now,
    );
    let dark = policy.evaluate(now + Duration::from_secs(30), false, [(output(1), true)]);
    assert!(!dark.power_requests[0].powered);
    assert!(!dark.lock);

    let on = now + Duration::from_secs(31);
    assert_eq!(
        policy.set_stay_awake(true, on),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
    // The screen-off delay passes: nothing locks.
    assert!(
        !policy
            .evaluate(now + Duration::from_secs(45), false, [(output(1), true)])
            .lock
    );
    // Repeating the setting changes nothing.
    assert!(policy.set_stay_awake(true, on).is_empty());
}

#[test]
fn the_power_button_turns_the_screen_off_and_locks_without_stay_awake() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    let press = policy.toggle_now([(output(1), true)], now);
    assert!(press.lock);
    assert!(!press.suspend);
    assert_eq!(
        press.power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
}

#[test]
fn under_stay_awake_the_power_button_leaves_a_lit_screen_on() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    policy.set_stay_awake(true, now);
    let press = policy.toggle_now([(output(1), true)], now);
    assert_eq!(press, IdlePolicyActions::default());
    // Beside a desk too, for the phone's lit panel.
    let mut policy = phone_beside_desk(now);
    policy.set_stay_awake(true, now);
    assert_eq!(
        policy.toggle_now([(output(1), true), (output(2), true)], now),
        IdlePolicyActions::default()
    );
}

#[test]
fn the_screen_off_request_turns_the_screen_off_and_locks_without_stay_awake() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    let request = policy.screen_off_now([(output(1), true)], now);
    assert!(request.lock);
    assert!(!request.suspend);
    assert!(!request.power_requests[0].powered);

    // With a screen-off delay it locks after the delay, as the button does.
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::from_secs(5)),
            ..configuration(None, None, None)
        },
        now,
    );
    assert!(!policy.screen_off_now([(output(1), true)], now).lock);
    assert!(
        policy
            .evaluate(now + Duration::from_secs(5), false, [(output(1), false)])
            .lock
    );
}

#[test]
fn under_stay_awake_the_screen_off_request_darkens_without_locking() {
    let now = Instant::now();
    let mut policy = IdlePolicy::default();
    policy.configure(
        IdlePolicyConfiguration {
            lock_after_screen_off: Some(Duration::from_secs(5)),
            ..configuration(
                Some(Duration::from_secs(60)),
                Some(Duration::from_secs(30)),
                Some(Duration::from_secs(300)),
            )
        },
        now,
    );
    policy.set_stay_awake(true, now);
    let request = policy.screen_off_now([(output(1), true)], now);
    assert!(!request.lock);
    assert!(!request.suspend);
    assert_eq!(
        request.power_requests,
        [IdlePowerRequest {
            output: output(1),
            powered: false,
        }]
    );
    // No screen-off lock, idle lock or suspend follows, and playback does
    // not light the screen the user turned off.
    assert_eq!(policy.next_deadline(), None);
    for idle in [5, 60, 300, 3600] {
        let later = now + Duration::from_secs(idle);
        assert_eq!(
            policy.evaluate(later, false, [(output(1), false)]),
            IdlePolicyActions::default()
        );
        assert_eq!(
            policy.evaluate(later, true, [(output(1), false)]),
            IdlePolicyActions::default()
        );
    }
    // The power button lights it again, without the lock screen.
    let wake = policy.toggle_now([(output(1), false)], now + Duration::from_secs(3600));
    assert!(!wake.lock);
    assert!(wake.power_requests[0].powered);
}

#[test]
fn under_stay_awake_input_lights_the_screen_the_shell_turned_off() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    policy.set_stay_awake(true, now);
    policy.screen_off_now([(output(1), true)], now);
    assert_eq!(
        policy.note_activity(now + Duration::from_secs(1)),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
}

#[test]
fn the_screen_off_request_leaves_a_dark_screen_dark() {
    let now = Instant::now();
    for stay_awake in [false, true] {
        let mut policy = phone_policy(now);
        policy.set_stay_awake(stay_awake, now);
        assert_eq!(
            policy.screen_off_now([(output(1), false)], now),
            IdlePolicyActions::default()
        );
        assert_eq!(policy.screen_off_now([], now), IdlePolicyActions::default());
    }
}

#[test]
fn the_screen_off_request_beside_a_desk_darkens_only_the_phone() {
    let now = Instant::now();
    for stay_awake in [false, true] {
        let mut policy = phone_beside_desk(now);
        policy.set_stay_awake(stay_awake, now);
        let off = policy.screen_off_now([(output(1), true), (output(2), true)], now);
        assert_eq!(
            off.power_requests,
            [IdlePowerRequest {
                output: output(1),
                powered: false,
            }]
        );
        assert!(!off.lock);
        // The phone is dark already: the lit desk does not count.
        assert_eq!(
            policy.screen_off_now([(output(1), false), (output(2), true)], now),
            IdlePolicyActions::default()
        );
    }
}
#[test]
fn every_way_the_screen_goes_dark_starts_the_suspend_timeout() {
    let now = Instant::now();
    // The display timeout: 30 s, then 5 min.
    let mut policy = phone_policy(now);
    let idle = policy.evaluate(now + Duration::from_secs(30), false, [(output(1), true)]);
    assert!(!idle.power_requests[0].powered);
    policy.note_outputs_dark(true, now + Duration::from_secs(30));
    assert_eq!(policy.next_deadline(), Some(now + Duration::from_secs(330)));
    assert!(
        policy
            .evaluate(now + Duration::from_secs(330), false, [(output(1), false)])
            .suspend
    );

    // Ten seconds after the last touch: the power button, the shell's Screen
    // off, the cover (blank_now), a client such as wlopm.
    let dark = now + Duration::from_secs(10);
    for path in ["power button", "Screen off", "cover", "client"] {
        let mut policy = phone_policy(now);
        let requests = match path {
            "power button" => policy.toggle_now([(output(1), true)], dark).power_requests,
            "Screen off" => {
                policy
                    .screen_off_now([(output(1), true)], dark)
                    .power_requests
            }
            "cover" => policy.blank_now([(output(1), true)]),
            _ => Vec::new(),
        };
        assert!(requests.iter().all(|request| !request.powered), "{path}");
        policy.note_outputs_dark(true, dark);
        assert!(
            !policy
                .evaluate(dark + Duration::from_secs(299), false, [(output(1), false)])
                .suspend,
            "{path}"
        );
        assert!(
            policy
                .evaluate(dark + Duration::from_secs(300), false, [(output(1), false)])
                .suspend,
            "{path}"
        );
    }
}

#[test]
fn lighting_the_screen_stops_the_suspend_timeout_and_input_restarts_it() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    policy.toggle_now([(output(1), true)], now);
    policy.note_outputs_dark(true, now);

    // A touch lights the screen: nothing counts while it is lit.
    let touched = now + Duration::from_secs(100);
    assert_eq!(
        policy.note_activity(touched),
        [IdlePowerRequest {
            output: output(1),
            powered: true,
        }]
    );
    policy.note_outputs_dark(false, touched);
    assert!(
        !policy
            .evaluate(now + Duration::from_secs(300), false, [(output(1), true)])
            .suspend
    );

    // The button turns it off again: a full timeout from then.
    let pressed = now + Duration::from_secs(400);
    policy.toggle_now([(output(1), true)], pressed);
    policy.note_outputs_dark(true, pressed);
    assert!(
        !policy
            .evaluate(
                pressed + Duration::from_secs(199),
                false,
                [(output(1), false)]
            )
            .suspend
    );
    // Input that leaves the screen dark (a client keeps it off) starts the
    // timeout again.
    policy.note_external_power_request(output(1), false);
    let typed = pressed + Duration::from_secs(200);
    assert!(policy.note_activity(typed).is_empty());
    assert!(
        !policy
            .evaluate(
                pressed + Duration::from_secs(300),
                false,
                [(output(1), false)]
            )
            .suspend
    );
    assert!(
        policy
            .evaluate(
                typed + Duration::from_secs(300),
                false,
                [(output(1), false)]
            )
            .suspend
    );
}

#[test]
fn the_suspend_timeout_is_independent_of_the_display_timeout() {
    // The tablet's owner: the screen off after 30 min, sleep 5 min after it.
    let now = Instant::now();
    let owner = || {
        let mut policy = IdlePolicy::default();
        policy.configure(
            IdlePolicyConfiguration {
                lock_after_screen_off: Some(Duration::ZERO),
                ..configuration(
                    None,
                    Some(Duration::from_secs(1800)),
                    Some(Duration::from_secs(300)),
                )
            },
            now,
        );
        policy
    };
    let mut policy = owner();
    let off = policy.evaluate(now + Duration::from_secs(1800), false, [(output(1), true)]);
    assert!(!off.power_requests[0].powered);
    assert!(off.lock);
    assert!(!off.suspend);
    policy.note_outputs_dark(true, now + Duration::from_secs(1800));
    assert_eq!(
        policy.next_deadline(),
        Some(now + Duration::from_secs(2100))
    );
    assert!(
        policy
            .evaluate(now + Duration::from_secs(2100), false, [(output(1), false)])
            .suspend
    );

    // After the power button: 5 min, not 30.
    let mut policy = owner();
    let pressed = now + Duration::from_secs(60);
    assert!(policy.toggle_now([(output(1), true)], pressed).lock);
    policy.note_outputs_dark(true, pressed);
    assert!(
        policy
            .evaluate(
                pressed + Duration::from_secs(300),
                false,
                [(output(1), false)]
            )
            .suspend
    );
}

#[test]
fn nothing_suspends_under_stay_awake_or_with_suspend_off() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    policy.set_stay_awake(true, now);
    // The Screen off tile still darkens the screen.
    assert!(
        !policy
            .screen_off_now([(output(1), true)], now)
            .power_requests
            .is_empty()
    );
    policy.note_outputs_dark(true, now);
    assert_eq!(policy.next_deadline(), None);
    assert!(
        !policy
            .evaluate(now + Duration::from_secs(3600), false, [(output(1), false)])
            .suspend
    );

    let mut policy = IdlePolicy::default();
    policy.configure(
        configuration(None, Some(Duration::from_secs(30)), None),
        now,
    );
    policy.toggle_now([(output(1), true)], now);
    policy.note_outputs_dark(true, now);
    assert!(
        !policy
            .evaluate(now + Duration::from_secs(7200), false, [(output(1), false)])
            .suspend
    );
    assert_eq!(policy.next_deadline(), None);
}

#[test]
fn a_visible_idle_inhibitor_holds_the_suspend_off_and_its_end_starts_it_again() {
    let now = Instant::now();
    let mut policy = phone_policy(now);
    // The power button during playback: the screen stays dark.
    policy.toggle_now([(output(1), true)], now);
    policy.note_outputs_dark(true, now);
    for second in [100, 300, 600] {
        assert_eq!(
            policy.evaluate(
                now + Duration::from_secs(second),
                true,
                [(output(1), false)]
            ),
            IdlePolicyActions::default()
        );
    }
    assert_eq!(policy.next_deadline(), None);

    // Playback ends: a full timeout from then.
    let ended = now + Duration::from_secs(600);
    assert!(!policy.evaluate(ended, false, [(output(1), false)]).suspend);
    assert!(
        !policy
            .evaluate(
                ended + Duration::from_secs(299),
                false,
                [(output(1), false)]
            )
            .suspend
    );
    assert!(
        policy
            .evaluate(
                ended + Duration::from_secs(300),
                false,
                [(output(1), false)]
            )
            .suspend
    );
}
