use super::*;

#[test]
fn v11_migrates_only_launcher_targets_preserving_user_deletions() {
    let mut file = ShortcutFile {
        version: 10,
        revision: 25,
        shortcuts: vec![
            ShortcutBinding {
                shortcut: "Super+A".into(),
                target: ShortcutTarget::DenialAction {
                    action: ShortcutAction::OpenApplications,
                },
            },
            ShortcutBinding {
                shortcut: "Super+Alt+P".into(),
                target: ShortcutTarget::SpawnSh {
                    command: "custom".into(),
                },
            },
        ],
    };
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), Some(1));
    assert_eq!(file.revision, 26);
    assert_eq!(file.shortcuts.len(), 2);
    assert_eq!(file.shortcuts[0].shortcut, "Super+A");
    assert_eq!(
        file.shortcuts[0].target,
        ShortcutTarget::PluginAction {
            id: crate::plugin_actions::LEGACY_LAUNCHER_ACTION.into(),
        }
    );
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), None);
    file.version = 10;
    file.shortcuts.clear();
    migrate_shortcut_file(&mut file).unwrap();
    assert_eq!(file.shortcuts.len(), SHORTCUT_V12_PLUGIN_ADDITIONS.len());
}

#[test]
fn v12_adds_color_tuning_only_where_the_trigger_is_free() {
    let color_tuning = ShortcutTarget::PluginAction {
        id: crate::plugin_actions::COLOR_TUNING_ACTION.into(),
    };
    let mut file = ShortcutFile {
        version: 11,
        revision: 4,
        shortcuts: Vec::new(),
    };
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), Some(1));
    assert_eq!(file.revision, 5);
    assert_eq!(file.shortcuts.len(), 1);
    assert_eq!(file.shortcuts[0].shortcut, "Super+Alt+P");
    assert_eq!(file.shortcuts[0].target, color_tuning);
    assert!(compile_shortcuts(&file).is_ok());
    // A deletion after the migration stays deleted.
    file.shortcuts.clear();
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), None);
    assert!(file.shortcuts.is_empty());

    let custom = ShortcutBinding {
        shortcut: "Super+Alt+P".into(),
        target: ShortcutTarget::SpawnSh {
            command: "custom".into(),
        },
    };
    let mut file = ShortcutFile {
        version: 11,
        revision: 4,
        shortcuts: vec![custom.clone()],
    };
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), Some(0));
    assert_eq!(file.shortcuts, vec![custom]);
    assert!(
        default_shortcut_file()
            .shortcuts
            .iter()
            .any(|binding| binding.shortcut == "Super+Alt+P" && binding.target == color_tuning)
    );
}

#[test]
fn plugin_actions_follow_catalog_for_keys_taps_and_gestures() {
    let id = "third_party.anyAction";
    let file = ShortcutFile {
        version: SHORTCUT_SCHEMA_VERSION,
        revision: 1,
        shortcuts: ["A", "Super", "FourFingerSwipeUp"]
            .into_iter()
            .map(|shortcut| ShortcutBinding {
                shortcut: shortcut.into(),
                target: ShortcutTarget::PluginAction { id: id.into() },
            })
            .collect(),
    };
    let mut engine = ShortcutEngine::from_file(&file).unwrap();
    let catalog = crate::plugin_actions::ActionCatalog::decode(5,
            r#"[{"id":"third_party.anyAction","label":"Any action","description":"","provider":"Third party"}]"#).unwrap();
    assert_eq!(engine.observe(30, true), ShortcutDisposition::Forward);
    assert_eq!(engine.observe(30, false), ShortcutDisposition::Forward);
    assert_eq!(
        engine.observe_gesture(ShortcutGesture::FourFingerSwipeUp),
        ShortcutDisposition::Forward
    );
    engine.set_plugin_actions(&catalog);
    assert_eq!(
        engine.observe(30, true),
        ShortcutDisposition::PluginAction(id.into())
    );
    assert_eq!(engine.observe(30, true), ShortcutDisposition::Consume);
    // Disabling a provider during a captured key still consumes its release.
    engine.set_plugin_actions(&crate::plugin_actions::ActionCatalog::default());
    assert_eq!(engine.observe(30, false), ShortcutDisposition::Consume);
    engine.observe(KEY_LEFT_META, true);
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::Consume
    );
    engine.set_plugin_actions(&catalog);
    engine.observe(KEY_LEFT_META, true);
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::PluginAction(id.into())
    );
    assert_eq!(
        engine.observe_gesture(ShortcutGesture::FourFingerSwipeUp),
        ShortcutDisposition::PluginAction(id.into())
    );
}

#[test]
fn an_app_holding_the_shortcuts_gets_super_but_not_the_way_out() {
    const KEY_A: u32 = 30;
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    let super_press = engine.observe(KEY_LEFT_META, true);
    assert!(!super_press.survives_shortcuts_inhibit());
    let overview = engine.observe(KEY_A, true);
    assert_eq!(overview, ShortcutDisposition::RequestOverview);
    assert!(!overview.survives_shortcuts_inhibit());
    engine.pass_through_key(KEY_A);
    let release_pointer = engine.observe(KEY_ESCAPE, true);
    assert_eq!(release_pointer, ShortcutDisposition::RequestReleasePointer);
    assert!(release_pointer.survives_shortcuts_inhibit());
    engine.observe(KEY_ESCAPE, false);
    engine.observe(KEY_LEFT_META, false);
    assert!(
        engine
            .observe(KEY_VOLUME_UP, true)
            .survives_shortcuts_inhibit()
    );
    assert!(
        ShortcutDisposition::RequestShutdown.survives_shortcuts_inhibit()
            && !ShortcutDisposition::RequestLock.survives_shortcuts_inhibit()
    );
}

#[test]
fn reset_width_roundtrips_binds_without_defaults_and_does_not_repeat() {
    let action: ShortcutAction = serde_json::from_str("\"resetWindowWidth\"").unwrap();
    assert_eq!(action, ShortcutAction::ResetWindowWidth);
    assert_eq!(
        serde_json::to_string(&action).unwrap(),
        "\"resetWindowWidth\""
    );
    assert!(ShortcutAction::ALL.contains(&action));
    let target = ShortcutTarget::DenialAction { action };
    let defaults = default_shortcut_file();
    assert!(
        !defaults
            .shortcuts
            .iter()
            .any(|binding| binding.target == target)
    );
    let mut file = defaults;
    file.shortcuts.push(ShortcutBinding {
        shortcut: "Super+R".into(),
        target,
    });
    let mut engine = ShortcutEngine::from_file(&file).unwrap();
    engine.observe(KEY_LEFT_META, true);
    assert_eq!(
        engine.observe(19, true),
        ShortcutDisposition::RequestResize(KeyboardResize::ResetWidth)
    );
    assert_eq!(engine.observe(19, false), ShortcutDisposition::Consume);
    assert!(!ShortcutDisposition::RequestResize(KeyboardResize::ResetWidth).repeats_with_timer());
    let encoded = serde_json::to_string(&file).unwrap();
    let mut decoded: ShortcutFile = serde_json::from_str(&encoded).unwrap();
    assert_eq!(migrate_shortcut_file(&mut decoded).unwrap(), None);
    assert_eq!(decoded.shortcuts, file.shortcuts);
}

#[test]
fn resize_defaults_repeat_and_capture_releases() {
    for (keycode, shift, action) in [
        (12, false, KeyboardResize::ShrinkWidth),
        (13, false, KeyboardResize::GrowWidth),
        (12, true, KeyboardResize::ShrinkHeight),
        (13, true, KeyboardResize::GrowHeight),
    ] {
        let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
        engine.observe(KEY_LEFT_META, true);
        if shift {
            engine.observe(KEY_LEFT_SHIFT, true);
        }
        let expected = ShortcutDisposition::RequestResize(action);
        assert_eq!(engine.observe(keycode, true), expected);
        assert_eq!(engine.observe(keycode, true), expected);
        assert!(expected.repeats_with_timer());
        assert_eq!(engine.observe(keycode, false), ShortcutDisposition::Consume);
    }
    assert!(!ShortcutDisposition::RequestResize(KeyboardResize::ResetHeight).repeats_with_timer());
}

#[test]
fn v10_migration_preserves_custom_bindings_and_runs_only_once() {
    let custom = ShortcutBinding {
        shortcut: "Super+Minus".to_owned(),
        target: ShortcutTarget::SpawnSh {
            command: "custom".to_owned(),
        },
    };
    let mut file = ShortcutFile {
        version: 9,
        revision: 12,
        shortcuts: vec![custom.clone()],
    };
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), Some(4));
    assert_eq!(file.revision, 13);
    assert_eq!(file.shortcuts[0], custom);
    assert_eq!(file.shortcuts.len(), 5);
    assert!(compile_shortcuts(&file).is_ok());
    file.shortcuts.pop();
    assert_eq!(migrate_shortcut_file(&mut file).unwrap(), None);
    assert_eq!(file.shortcuts.len(), 4);
}

#[test]
fn level_shortcuts_repeat_while_the_key_remains_pressed() {
    for (keycode, expected) in [
        (KEY_VOLUME_UP, ShortcutDisposition::RequestVolumeUp),
        (KEY_VOLUME_DOWN, ShortcutDisposition::RequestVolumeDown),
        (KEY_BRIGHTNESS_UP, ShortcutDisposition::RequestBrightnessUp),
        (
            KEY_BRIGHTNESS_DOWN,
            ShortcutDisposition::RequestBrightnessDown,
        ),
    ] {
        let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();

        assert_eq!(engine.observe(keycode, true), expected.clone());
        let repeated = engine.observe(keycode, true);
        assert_eq!(repeated, expected);
        assert!(repeated.repeats_system_control());
        assert_eq!(engine.observe(keycode, false), ShortcutDisposition::Consume);
    }
}

#[test]
fn ctrl_alt_function_keys_request_vt_switch_and_capture_their_lifecycle() {
    for vt in 1..=12 {
        let keycode = match vt {
            1..=10 => KEY_F1 + vt - 1,
            11 => KEY_F11,
            12 => KEY_F12,
            _ => unreachable!(),
        };
        let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();

        assert_eq!(
            engine.observe(KEY_LEFT_CTRL, true),
            ShortcutDisposition::Forward
        );
        assert_eq!(
            engine.observe(KEY_RIGHT_ALT, true),
            ShortcutDisposition::Forward
        );
        assert_eq!(
            engine.observe(keycode, true),
            ShortcutDisposition::RequestVtSwitch(vt as i32)
        );
        assert_eq!(engine.observe(keycode, true), ShortcutDisposition::Consume);
        assert_eq!(engine.observe(keycode, false), ShortcutDisposition::Consume);
    }
}

#[test]
fn vt_switch_requires_exactly_ctrl_and_alt() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();

    assert_eq!(
        engine.observe(KEY_LEFT_CTRL, true),
        ShortcutDisposition::Forward
    );
    assert_eq!(engine.observe(KEY_F1, true), ShortcutDisposition::Forward);
    assert_eq!(engine.observe(KEY_F1, false), ShortcutDisposition::Forward);
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, true),
        ShortcutDisposition::Forward
    );
    assert_eq!(
        engine.observe(KEY_LEFT_SHIFT, true),
        ShortcutDisposition::Forward
    );
    assert_eq!(engine.observe(KEY_F1, true), ShortcutDisposition::Forward);
}

#[test]
fn v4_migration_relocates_the_legacy_maximize_binding_for_navigation() {
    let mut file = ShortcutFile {
        version: 3,
        revision: 1,
        shortcuts: vec![ShortcutBinding {
            shortcut: "Super+Up".to_owned(),
            target: ShortcutTarget::DenialAction {
                action: ShortcutAction::ToggleMaximize,
            },
        }],
    };

    assert_eq!(
        migrate_shortcut_file(&mut file).unwrap(),
        Some(
            1 + SHORTCUT_V4_ADDITIONS.len()
                + SHORTCUT_V5_ADDITIONS.len()
                + SHORTCUT_V6_ADDITIONS.len()
                + SHORTCUT_V9_ADDITIONS.len()
                + SHORTCUT_V10_ADDITIONS.len()
                + SHORTCUT_V12_PLUGIN_ADDITIONS.len()
        )
    );
    assert_eq!(file.version, SHORTCUT_SCHEMA_VERSION);
    let action_for = |shortcut: &str| {
        file.shortcuts
            .iter()
            .find(|binding| binding.shortcut == shortcut)
            .and_then(|binding| match binding.target {
                ShortcutTarget::DenialAction { action } => Some(action),
                _ => None,
            })
    };
    assert_eq!(action_for("Super+W"), Some(ShortcutAction::ToggleMaximize));
    assert_eq!(action_for("Super+Up"), Some(ShortcutAction::FocusUp));
    assert_eq!(
        action_for("Super+Ctrl+Right"),
        Some(ShortcutAction::SwapRight)
    );
}

#[test]
fn v5_migration_adds_workspace_defaults_without_overwriting_user_bindings() {
    let mut file = ShortcutFile {
        version: 4,
        revision: 7,
        shortcuts: vec![ShortcutBinding {
            shortcut: "Super+1".to_owned(),
            target: ShortcutTarget::SpawnSh {
                command: "custom-command".to_owned(),
            },
        }],
    };

    assert!(migrate_shortcut_file(&mut file).unwrap().is_some());
    assert_eq!(file.version, SHORTCUT_SCHEMA_VERSION);
    assert!(file.shortcuts.iter().any(|binding| {
        binding.shortcut == "Super+1"
            && matches!(
                &binding.target,
                ShortcutTarget::SpawnSh { command } if command == "custom-command"
            )
    }));
    assert!(
        !file
            .shortcuts
            .iter()
            .any(|binding| binding.shortcut == "Super+S")
    );
}

#[test]
fn v7_migration_removes_the_retired_workspace_overview_action() {
    let mut document = serde_json::json!({
        "version": 6,
        "revision": 12,
        "shortcuts": [
            {
                "shortcut": "Super+S",
                "target": {
                    "type": "denialAction",
                    "action": "openWorkspaces"
                }
            },
            {
                "shortcut": "Super+Alt+Right",
                "target": {
                    "type": "denialAction",
                    "action": "nextWorkspace"
                }
            }
        ]
    });

    assert_eq!(remove_retired_shortcut_actions(&mut document), 1);
    let mut file = serde_json::from_value::<ShortcutFile>(document).unwrap();
    assert_eq!(
        migrate_shortcut_file(&mut file).unwrap(),
        Some(2 + SHORTCUT_V10_ADDITIONS.len() + SHORTCUT_V12_PLUGIN_ADDITIONS.len())
    );
    assert_eq!(file.version, SHORTCUT_SCHEMA_VERSION);
    assert_eq!(file.revision, 13);
    assert_eq!(
        file.shortcuts.len(),
        3 + SHORTCUT_V10_ADDITIONS.len() + SHORTCUT_V12_PLUGIN_ADDITIONS.len()
    );
    assert_eq!(file.shortcuts[0].shortcut, "Super+Alt+Right");
}

#[test]
fn v6_migration_adds_workspace_swipes_without_overwriting_user_bindings() {
    let mut file = ShortcutFile {
        version: 5,
        revision: 11,
        shortcuts: vec![ShortcutBinding {
            shortcut: "FourFingerSwipeRight".to_owned(),
            target: ShortcutTarget::SpawnSh {
                command: "custom-command".to_owned(),
            },
        }],
    };

    assert_eq!(
        migrate_shortcut_file(&mut file).unwrap(),
        Some(3 + SHORTCUT_V10_ADDITIONS.len() + SHORTCUT_V12_PLUGIN_ADDITIONS.len())
    );
    assert_eq!(file.version, SHORTCUT_SCHEMA_VERSION);
    assert_eq!(file.revision, 12);
    assert!(file.shortcuts.iter().any(|binding| {
        binding.shortcut == "FourFingerSwipeRight"
            && matches!(
                &binding.target,
                ShortcutTarget::SpawnSh { command } if command == "custom-command"
            )
    }));
    assert!(file.shortcuts.iter().any(|binding| {
        binding.shortcut == "FourFingerSwipeLeft"
            && matches!(
                &binding.target,
                ShortcutTarget::DenialAction {
                    action: ShortcutAction::NextWorkspace
                }
            )
    }));
}

#[test]
fn v8_migration_inverts_only_the_saved_default_workspace_swipes() {
    let mut file = ShortcutFile {
        version: 7,
        revision: 14,
        shortcuts: vec![
            ShortcutBinding {
                shortcut: "FourFingerSwipeRight".to_owned(),
                target: ShortcutTarget::SpawnSh {
                    command: "custom-command".to_owned(),
                },
            },
            ShortcutBinding {
                shortcut: "FourFingerSwipeLeft".to_owned(),
                target: ShortcutTarget::DenialAction {
                    action: ShortcutAction::PreviousWorkspace,
                },
            },
        ],
    };

    assert_eq!(
        migrate_shortcut_file(&mut file).unwrap(),
        Some(3 + SHORTCUT_V10_ADDITIONS.len() + SHORTCUT_V12_PLUGIN_ADDITIONS.len())
    );
    assert_eq!(file.version, SHORTCUT_SCHEMA_VERSION);
    assert_eq!(file.revision, 15);
    assert!(matches!(
        &file.shortcuts[0].target,
        ShortcutTarget::SpawnSh { command } if command == "custom-command"
    ));
    assert_eq!(
        file.shortcuts[1].target,
        ShortcutTarget::DenialAction {
            action: ShortcutAction::NextWorkspace
        }
    );
}

#[test]
fn four_finger_swipe_defaults_follow_requested_workspace_direction() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();

    assert_eq!(
        engine.observe_gesture(ShortcutGesture::FourFingerSwipeRight),
        ShortcutDisposition::RequestPreviousWorkspace
    );
    assert_eq!(
        engine.observe_gesture(ShortcutGesture::FourFingerSwipeLeft),
        ShortcutDisposition::RequestNextWorkspace
    );
    assert_eq!(
        engine.observe_gesture(ShortcutGesture::FourFingerSwipeDown),
        ShortcutDisposition::RequestPreviousWorkspace
    );
    assert_eq!(
        engine.observe_gesture(ShortcutGesture::FourFingerSwipeUp),
        ShortcutDisposition::RequestNextWorkspace
    );
}

#[test]
fn declined_contextual_workspace_shortcut_forwards_its_release() {
    let file = default_shortcut_file();
    let mut engine = ShortcutEngine::from_file(&file).unwrap();
    assert_eq!(
        engine.observe(KEY_LEFT_META, true),
        ShortcutDisposition::Consume
    );
    assert_eq!(
        engine.observe(2, true),
        ShortcutDisposition::RequestSwitchWorkspace(1)
    );
    engine.pass_through_key(2);
    assert_eq!(engine.observe(2, false), ShortcutDisposition::Forward);
}

#[test]
fn super_pointer_axis_suppresses_the_modifier_tap_action() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();

    assert_eq!(
        engine.observe(KEY_LEFT_META, true),
        ShortcutDisposition::Consume
    );
    engine.note_pointer_axis();
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::Consume
    );
}
#[test]
fn cancelling_a_virtual_modifier_hold_does_not_invoke_its_tap_action() {
    let mut file = default_shortcut_file();
    file.shortcuts = vec![ShortcutBinding {
        shortcut: "Super".into(),
        target: ShortcutTarget::DenialAction {
            action: ShortcutAction::OpenOverview,
        },
    }];
    let mut engine = ShortcutEngine::from_file(&file).unwrap();
    engine.observe(KEY_LEFT_META, true);
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::RequestOverview
    );
    engine.observe(KEY_LEFT_META, true);
    engine.cancel_modifier_tap();
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::Consume
    );
}

const KEY_C: u32 = 46;
const KEY_F: u32 = 33;
const KEY_H: u32 = 35;
const KEY_Q: u32 = 16;
const KEY_S: u32 = 31;
const KEY_3: u32 = 4;

fn app_step(step: AppSwitcherStep) -> ShortcutDisposition {
    ShortcutDisposition::RequestAppSwitcher(step)
}

#[test]
fn alt_tab_steps_apps_while_alt_is_held_and_switches_on_release() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, true),
        ShortcutDisposition::Forward
    );
    assert_eq!(
        engine.observe(KEY_TAB, true),
        app_step(AppSwitcherStep::Next)
    );
    assert!(engine.app_switcher_held());
    assert_eq!(engine.observe(KEY_TAB, false), ShortcutDisposition::Consume);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        app_step(AppSwitcherStep::Next)
    );
    engine.observe(KEY_TAB, false);
    // Shift steps back, and ` steps the selected app's windows.
    assert_eq!(
        engine.observe(KEY_LEFT_SHIFT, true),
        ShortcutDisposition::Forward
    );
    assert_eq!(
        engine.observe(KEY_TAB, true),
        app_step(AppSwitcherStep::Previous)
    );
    engine.observe(KEY_TAB, false);
    assert_eq!(
        engine.observe(KEY_GRAVE, true),
        app_step(AppSwitcherStep::WindowPrevious)
    );
    engine.observe(KEY_GRAVE, false);
    engine.observe(KEY_LEFT_SHIFT, false);
    assert_eq!(
        engine.observe(KEY_GRAVE, true),
        app_step(AppSwitcherStep::WindowNext)
    );
    assert_eq!(
        engine.observe(KEY_GRAVE, false),
        ShortcutDisposition::Consume
    );
    // The arrows step too, as on a Mac.
    assert_eq!(
        engine.observe(KEY_LEFT, true),
        app_step(AppSwitcherStep::Previous)
    );
    assert_eq!(
        engine.observe(KEY_LEFT, false),
        ShortcutDisposition::Consume
    );
    // Other keys do nothing while the switcher is up.
    assert_eq!(engine.observe(KEY_C, true), ShortcutDisposition::Consume);
    assert_eq!(engine.observe(KEY_C, false), ShortcutDisposition::Consume);
    // Alt goes up: switch. Its release still reaches the app.
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, false),
        ShortcutDisposition::RequestAppSwitcherEnd { forward: true }
    );
    assert!(!engine.app_switcher_held());
    // Afterwards the keys are the app's again.
    assert_eq!(engine.observe(KEY_C, true), ShortcutDisposition::Forward);
}

#[test]
fn alt_shift_tab_and_alt_grave_open_the_switcher_on_their_own_step() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    engine.observe(KEY_LEFT_ALT, true);
    engine.observe(KEY_LEFT_SHIFT, true);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        app_step(AppSwitcherStep::Previous)
    );
    engine.observe(KEY_TAB, false);
    engine.observe(KEY_LEFT_SHIFT, false);
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, false),
        ShortcutDisposition::RequestAppSwitcherEnd { forward: true }
    );

    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(
        engine.observe(KEY_GRAVE, true),
        app_step(AppSwitcherStep::WindowNext)
    );
    engine.observe(KEY_GRAVE, false);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        app_step(AppSwitcherStep::Next)
    );
    engine.observe(KEY_TAB, false);
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, false),
        ShortcutDisposition::RequestAppSwitcherEnd { forward: true }
    );
}

#[test]
fn escape_closes_the_app_switcher_without_switching() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    engine.observe(KEY_LEFT_ALT, true);
    engine.observe(KEY_TAB, true);
    engine.observe(KEY_TAB, false);
    assert_eq!(
        engine.observe(KEY_ESCAPE, true),
        ShortcutDisposition::RequestAppSwitcherCancel
    );
    assert!(!engine.app_switcher_held());
    assert_eq!(
        engine.observe(KEY_ESCAPE, false),
        ShortcutDisposition::Consume
    );
    // Alt goes up as an ordinary key: there is nothing to switch to.
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, false),
        ShortcutDisposition::Forward
    );
}

#[test]
fn a_declined_alt_tab_leaves_no_switcher_held() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        app_step(AppSwitcherStep::Next)
    );
    // The tablet presentation, or an app holding the shortcuts, takes it.
    engine.pass_through_key(KEY_TAB);
    assert!(!engine.app_switcher_held());
    assert_eq!(engine.observe(KEY_TAB, false), ShortcutDisposition::Forward);
    assert_eq!(engine.observe(KEY_C, true), ShortcutDisposition::Forward);
    assert_eq!(
        engine.observe(KEY_LEFT_ALT, false),
        ShortcutDisposition::Forward
    );
}

#[test]
fn super_tab_stays_the_window_switcher_and_shift_steps_it_back() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    engine.observe(KEY_LEFT_META, true);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        ShortcutDisposition::RequestWindowSwitcherNext
    );
    engine.observe(KEY_TAB, false);
    engine.observe(KEY_LEFT_SHIFT, true);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        ShortcutDisposition::RequestWindowSwitcherPrevious
    );
    engine.observe(KEY_TAB, false);
    engine.observe(KEY_LEFT_SHIFT, false);
    assert!(!engine.app_switcher_held());
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::RequestWindowSwitcherEnd { forward: false }
    );
}

#[test]
fn the_standard_keys_search_on_super_s_and_leave_alt_letters_to_apps() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    assert_eq!(engine.preset(), ShortcutPreset::Standard);
    engine.observe(KEY_LEFT_META, true);
    assert_eq!(
        engine.observe(KEY_S, true),
        ShortcutDisposition::RequestSearch
    );
    engine.observe(KEY_S, false);
    assert_eq!(
        engine.observe(KEY_LEFT, true),
        ShortcutDisposition::RequestFocus(LayoutDirection::Left)
    );
    engine.observe(KEY_LEFT, false);
    engine.observe(KEY_LEFT_META, false);
    engine.observe(KEY_LEFT_ALT, true);
    for key in [KEY_F, KEY_H, KEY_C] {
        assert_eq!(engine.observe(key, true), ShortcutDisposition::Forward);
        assert_eq!(engine.observe(key, false), ShortcutDisposition::Forward);
    }
    // Alt+Space keeps switching the layout, as the file binds it.
    assert_eq!(
        engine.observe(KEY_SPACE, true),
        ShortcutDisposition::RequestNextKeyboardLayout
    );
}

#[test]
fn the_mac_preset_puts_the_shells_keys_on_alt() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    engine.set_preset(ShortcutPreset::Mac);
    engine.observe(KEY_LEFT_ALT, true);
    for (key, disposition) in [
        (KEY_F, ShortcutDisposition::RequestSearch),
        (KEY_H, ShortcutDisposition::RequestHideApplication),
        (50, ShortcutDisposition::RequestMinimize),
        (KEY_SPACE, ShortcutDisposition::RequestNextKeyboardLayout),
    ] {
        assert_eq!(engine.observe(key, true), disposition, "{key}");
        assert_eq!(engine.observe(key, false), ShortcutDisposition::Consume);
    }
    // Command+C is the app's: the translation makes it Ctrl+C.
    assert_eq!(engine.observe(KEY_C, true), ShortcutDisposition::Forward);
    engine.observe(KEY_C, false);
    engine.observe(KEY_LEFT_SHIFT, true);
    assert_eq!(
        engine.observe(KEY_3, true),
        ShortcutDisposition::RequestCaptureScreen
    );
    engine.observe(KEY_3, false);
    engine.observe(KEY_LEFT_SHIFT, false);
    engine.observe(KEY_LEFT_CTRL, true);
    assert_eq!(
        engine.observe(KEY_Q, true),
        ShortcutDisposition::RequestLock
    );
    engine.observe(KEY_Q, false);
    assert_eq!(
        engine.observe(KEY_F, true),
        ShortcutDisposition::RequestToggleFullscreen
    );
    engine.observe(KEY_F, false);
    engine.observe(KEY_LEFT_ALT, false);
    // Ctrl+arrows move between screens and open the views, as on a Mac.
    assert_eq!(
        engine.observe(KEY_RIGHT, true),
        ShortcutDisposition::RequestFocus(LayoutDirection::Right)
    );
    engine.observe(KEY_RIGHT, false);
    assert_eq!(
        engine.observe(KEY_UP, true),
        ShortcutDisposition::RequestOverview
    );
    engine.observe(KEY_UP, false);
    assert_eq!(
        engine.observe(KEY_DOWN, true),
        ShortcutDisposition::RequestAppWindows
    );
    engine.observe(KEY_DOWN, false);
    engine.observe(KEY_LEFT_CTRL, false);
    // Back to the standard keys: Alt letters are the apps' again.
    engine.set_preset(ShortcutPreset::Standard);
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(engine.observe(KEY_F, true), ShortcutDisposition::Forward);
}

#[test]
fn option_edits_text_in_the_mac_preset_whatever_super_binds() {
    let mut engine = ShortcutEngine::from_file(&default_shortcut_file()).unwrap();
    engine.set_preset(ShortcutPreset::Mac);
    engine.observe(KEY_LEFT_META, true);
    // Super+Left is "focus left" in the file; Option+Left moves by a word.
    assert_eq!(engine.observe(KEY_LEFT, true), ShortcutDisposition::Forward);
    assert_eq!(
        engine.observe(KEY_LEFT, false),
        ShortcutDisposition::Forward
    );
    engine.observe(KEY_LEFT_SHIFT, true);
    assert_eq!(engine.observe(KEY_UP, true), ShortcutDisposition::Forward);
    engine.observe(KEY_UP, false);
    engine.observe(KEY_LEFT_SHIFT, false);
    assert_eq!(
        engine.observe(KEY_BACKSPACE, true),
        ShortcutDisposition::Forward
    );
    engine.observe(KEY_BACKSPACE, false);
    // Super's other shortcuts stay: Super+A, Super+Ctrl+arrows.
    assert_eq!(
        engine.observe(30, true),
        ShortcutDisposition::RequestOverview
    );
    engine.observe(30, false);
    engine.observe(KEY_LEFT_CTRL, true);
    assert_eq!(
        engine.observe(KEY_LEFT, true),
        ShortcutDisposition::RequestSwap(LayoutDirection::Left)
    );
    engine.observe(KEY_LEFT, false);
    engine.observe(KEY_LEFT_CTRL, false);
    // A Super chord does not open the launcher on release.
    assert_eq!(
        engine.observe(KEY_LEFT_META, false),
        ShortcutDisposition::Consume
    );
}

#[test]
fn the_files_bindings_replace_or_switch_off_the_presets() {
    let mut file = default_shortcut_file();
    file.shortcuts.push(ShortcutBinding {
        shortcut: "Alt+Tab".into(),
        target: ShortcutTarget::DenialAction {
            action: ShortcutAction::CloseWindow,
        },
    });
    file.shortcuts.push(ShortcutBinding {
        shortcut: "Alt+H".into(),
        target: BuiltinAction::SendToApp.target(),
    });
    let mut engine = ShortcutEngine::from_file_with_preset(&file, ShortcutPreset::Mac).unwrap();
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(
        engine.observe(KEY_TAB, true),
        ShortcutDisposition::RequestClose
    );
    engine.observe(KEY_TAB, false);
    assert!(!engine.app_switcher_held());
    assert_eq!(engine.observe(KEY_H, true), ShortcutDisposition::Forward);
    assert_eq!(engine.observe(KEY_H, false), ShortcutDisposition::Forward);
    // A binding of an action that is gone still keeps the preset's off.
    let mut file = default_shortcut_file();
    file.shortcuts.push(ShortcutBinding {
        shortcut: "Alt+F".into(),
        target: ShortcutTarget::PluginAction {
            id: "gone.plugin".into(),
        },
    });
    let mut engine = ShortcutEngine::from_file_with_preset(&file, ShortcutPreset::Mac).unwrap();
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(engine.observe(KEY_F, true), ShortcutDisposition::Forward);
}

struct TemporaryDirectory(PathBuf);

impl TemporaryDirectory {
    fn new(label: &str) -> Self {
        let sequence = SHORTCUT_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "denial-shortcuts-{label}-{}-{sequence}",
            std::process::id()
        ));
        fs::create_dir(&path).expect("create temporary directory");
        Self(path)
    }

    fn shortcuts_path(&self) -> PathBuf {
        self.0.join("denial/shortcuts.json")
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn commit(manager: &mut ShortcutManager, prepared: Result<PreparedShortcutUpdate, ShortcutError>) {
    let mut prepared = prepared.unwrap();
    prepared.take_engine();
    manager.commit(prepared).unwrap();
}

#[test]
fn preset_shortcuts_are_edited_through_the_file() {
    let temporary = TemporaryDirectory::new("preset");
    let mut manager = ShortcutManager::load_path(temporary.shortcuts_path()).unwrap();
    manager.set_preset(ShortcutPreset::Mac);
    let preset = manager.preset_shortcuts();
    assert!(preset.iter().any(|binding| binding.shortcut == "Alt+H"));
    // The file's own Alt+Space stands; the preset does not list it again.
    assert!(!preset.iter().any(|binding| binding.shortcut == "Alt+Space"));

    // Its keys are taken: a new shortcut there conflicts.
    let hide = ShortcutBinding {
        shortcut: "Alt+H".into(),
        target: ShortcutTarget::DenialAction {
            action: ShortcutAction::CloseWindow,
        },
    };
    assert!(matches!(
        manager.validate_shortcut(&hide, None),
        ShortcutValidation::Conflict { .. }
    ));
    assert!(matches!(
        manager.validate_shortcut(&hide, Some("Alt+H")),
        ShortcutValidation::Valid { .. }
    ));

    // Deleting a preset's shortcut gives its keys to the app.
    let revision = manager.revision();
    let prepared = manager.prepare_remove(revision, "alt+h");
    commit(&mut manager, prepared);
    assert!(manager.file().shortcuts.contains(&ShortcutBinding {
        shortcut: "Alt+H".into(),
        target: BuiltinAction::SendToApp.target(),
    }));
    assert!(
        !manager
            .preset_shortcuts()
            .iter()
            .any(|binding| binding.shortcut == "Alt+H")
    );
    let mut engine = manager.engine();
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(engine.observe(KEY_H, true), ShortcutDisposition::Forward);

    // Deleting that brings the preset's back.
    let revision = manager.revision();
    let prepared = manager.prepare_remove(revision, "Alt+H");
    commit(&mut manager, prepared);
    assert!(
        manager
            .preset_shortcuts()
            .iter()
            .any(|binding| binding.shortcut == "Alt+H")
    );

    // Moving one to other keys frees its own.
    let revision = manager.revision();
    let prepared = manager.prepare_update(
        revision,
        "Alt+F",
        ShortcutBinding {
            shortcut: "Alt+Shift+F".into(),
            target: BuiltinAction::Search.target(),
        },
    );
    commit(&mut manager, prepared);
    let mut engine = manager.engine();
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(engine.observe(KEY_F, true), ShortcutDisposition::Forward);
    engine.observe(KEY_F, false);
    engine.observe(KEY_LEFT_SHIFT, true);
    assert_eq!(
        engine.observe(KEY_F, true),
        ShortcutDisposition::RequestSearch
    );

    // Editing only the action keeps the keys.
    let revision = manager.revision();
    let prepared = manager.prepare_update(
        revision,
        "Alt+M",
        ShortcutBinding {
            shortcut: "Alt+M".into(),
            target: ShortcutTarget::DenialAction {
                action: ShortcutAction::MinimizeAllWindows,
            },
        },
    );
    commit(&mut manager, prepared);
    assert!(!manager.file().shortcuts.iter().any(|binding| {
        binding.shortcut == "Alt+M" && binding.target == BuiltinAction::SendToApp.target()
    }));
    let mut engine = manager.engine();
    engine.observe(KEY_LEFT_ALT, true);
    assert_eq!(
        engine.observe(50, true),
        ShortcutDisposition::RequestMinimizeAll
    );

    // Keys neither the file nor the preset has are missing.
    let revision = manager.revision();
    assert!(matches!(
        manager.prepare_remove(revision, "Alt+J"),
        Err(ShortcutError::Missing(_))
    ));
}

/// What `deniald` up to eb17 (and eb16.tp1) accepts in the shortcut file:
/// version 12, keys it can parse, and targets of its types. Its actions are
/// these; any other `denialAction` makes it set the whole file aside.
const OLDER_RELEASE_ACTIONS: &[&str] = &[
    "shutdown",
    "openApplications",
    "openDashboard",
    "openOverview",
    "toggleVerticalMaximize",
    "resizeGrowWidth",
    "resizeShrinkWidth",
    "resizeGrowHeight",
    "resizeShrinkHeight",
    "resetWindowHeight",
    "resetWindowWidth",
    "windowSwitcher",
    "openClipboard",
    "captureRegion",
    "closeWindow",
    "minimizeWindow",
    "minimizeAllWindows",
    "toggleMaximize",
    "toggleFullscreen",
    "toggleWindowAlwaysOnTop",
    "releasePointer",
    "lockScreen",
    "volumeUp",
    "volumeDown",
    "volumeMute",
    "brightnessUp",
    "brightnessDown",
    "nextKeyboardLayout",
    "previousKeyboardLayout",
    "openSettings",
    "focusLeft",
    "focusRight",
    "focusUp",
    "focusDown",
    "swapLeft",
    "swapRight",
    "swapUp",
    "swapDown",
    "previousWorkspace",
    "nextWorkspace",
    "moveToPreviousWorkspace",
    "moveToNextWorkspace",
    "switchWorkspace1",
    "switchWorkspace2",
    "switchWorkspace3",
    "switchWorkspace4",
    "switchWorkspace5",
    "switchWorkspace6",
    "switchWorkspace7",
    "switchWorkspace8",
    "switchWorkspace9",
    "moveToWorkspace1",
    "moveToWorkspace2",
    "moveToWorkspace3",
    "moveToWorkspace4",
    "moveToWorkspace5",
    "moveToWorkspace6",
    "moveToWorkspace7",
    "moveToWorkspace8",
    "moveToWorkspace9",
];

fn older_deniald_accepts(bytes: &[u8]) -> bool {
    let file: serde_json::Value = serde_json::from_slice(bytes).unwrap();
    file["version"] == 12
        && file["shortcuts"].as_array().unwrap().iter().all(|binding| {
            let target = &binding["target"];
            let target_ok = match target["type"].as_str() {
                Some("denialAction") => {
                    OLDER_RELEASE_ACTIONS.contains(&target["action"].as_str().unwrap_or_default())
                }
                Some("pluginAction") => {
                    crate::plugin_actions::valid_id(target["id"].as_str().unwrap_or_default())
                }
                Some("spawn" | "spawnSh") => true,
                _ => false,
            };
            // eb16.tp1 parses every gesture but ThreeFingerSwipeDown.
            target_ok && binding["shortcut"] != "ThreeFingerSwipeDown"
        })
}

#[test]
fn an_older_release_still_reads_the_shortcut_file() {
    let temporary = TemporaryDirectory::new("rollback");
    let path = temporary.shortcuts_path();
    let mut manager = ShortcutManager::load_path(path.clone()).unwrap();
    manager.set_preset(ShortcutPreset::Mac);
    // The preset alone writes nothing: its shortcuts are not in the file.
    assert!(older_deniald_accepts(&fs::read(&path).unwrap()));
    assert!(!fs::read_to_string(&path).unwrap().contains("deniald."));

    // Edits of the preset's shortcuts, and new actions bound by hand, are
    // plugin actions an older release does not have: it leaves those keys
    // to the app and keeps every other shortcut.
    let revision = manager.revision();
    let prepared = manager.prepare_remove(revision, "Alt+H");
    commit(&mut manager, prepared);
    let revision = manager.revision();
    let prepared = manager.prepare_add(
        revision,
        ShortcutBinding {
            shortcut: "Super+Shift+F".into(),
            target: BuiltinAction::Search.target(),
        },
    );
    commit(&mut manager, prepared);
    let bytes = fs::read(&path).unwrap();
    assert!(older_deniald_accepts(&bytes));
    let file: ShortcutFile = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(file.version, 12);
    assert!(
        file.shortcuts
            .iter()
            .any(|binding| binding.shortcut == "Super+Shift+F")
    );
    // An older engine, which has no built-in actions, finds no action for
    // them: as with a plugin that is not installed, the keys reach the app.
    let mut older = ShortcutEngine::from_file(&file).unwrap();
    older.available_plugin_actions.clear();
    for builtin in BuiltinAction::ALL {
        assert!(crate::plugin_actions::valid_id(builtin.id()));
        assert!(!older.available_plugin_actions.contains(builtin.id()));
    }
}

#[test]
fn the_actions_older_releases_know_are_these() {
    let names = ShortcutAction::ALL
        .iter()
        .map(|action| serde_json::to_value(action).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(names.len(), OLDER_RELEASE_ACTIONS.len());
    for name in OLDER_RELEASE_ACTIONS {
        assert!(names.contains(&serde_json::Value::from(*name)), "{name}");
    }
}
