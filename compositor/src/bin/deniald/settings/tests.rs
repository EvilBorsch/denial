use super::*;
use std::os::unix::fs::symlink;

struct TemporaryDirectory(PathBuf);

impl TemporaryDirectory {
    fn new(label: &str) -> Self {
        let sequence = SETTINGS_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("denial-{label}-{}-{sequence}", std::process::id()));
        fs::create_dir(&path).expect("create temporary directory");
        Self(path)
    }

    fn settings_path(&self) -> PathBuf {
        self.0.join("denial/settings.json")
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn shell_document(value: Value) -> String {
    let mut document = value
        .as_object()
        .cloned()
        .expect("test shell document must be an object");
    if let Some(appearance) = document
        .get_mut("appearance")
        .and_then(Value::as_object_mut)
    {
        appearance
            .entry("allowClientCursorSurfaces")
            .or_insert(Value::Bool(true));
        appearance
            .entry("cursorSize")
            .or_insert(Value::from(DEFAULT_CURSOR_SIZE));
    }
    let layout = document
        .entry("layout")
        .or_insert_with(|| Value::Object(Map::new()))
        .as_object_mut()
        .expect("test shell layout must be an object");
    layout
        .entry("scrollingLayoutPreserveSwapSizes")
        .or_insert(Value::Bool(true));
    layout
        .entry("windowLayout")
        .or_insert_with(|| Value::String("stacking".to_owned()));
    layout
        .entry("scrollingLayoutWheelSpeed")
        .or_insert(Value::from(DEFAULT_SCROLLING_LAYOUT_WHEEL_SPEED));
    layout
        .entry("scrollingLayoutWheelUpDirection")
        .or_insert_with(|| Value::String("left".to_owned()));
    layout
        .entry("workspacesEnabled")
        .or_insert(Value::Bool(false));
    layout
        .entry("workspaceCount")
        .or_insert(Value::from(DEFAULT_WORKSPACE_COUNT));
    layout
        .entry("workspaceSwitchingOrientation")
        .or_insert_with(|| Value::String("horizontal".to_owned()));
    document.insert("version".to_owned(), Value::from(SETTINGS_SCHEMA_VERSION));
    serde_json::to_string(&document).expect("test shell document serializes")
}

#[test]
fn migrates_idle_timeouts_from_minutes_to_seconds() {
    let temporary = TemporaryDirectory::new("settings-idle-seconds");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(
        &path,
        br#"{"version":29,"power":{"idleDpmsEnabled":true,"idleDpmsTimeoutMinutes":2,"idleLockTimeoutMinutes":16}}"#,
    )
    .unwrap();

    let manager = SettingsManager::load_path(path).unwrap();
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    let power = document["power"].as_object().unwrap();
    assert_eq!(power["idleDpmsTimeoutSeconds"], 120);
    assert_eq!(power["idleLockTimeoutSeconds"], 960);
    assert_eq!(power["idleDpmsEnabled"], true);
    assert!(!power.contains_key("idleDpmsTimeoutMinutes"));
    assert!(!power.contains_key("idleLockTimeoutMinutes"));
    assert!(!power.contains_key("idleSuspendTimeoutSeconds"));
}

#[test]
fn migrates_existing_shell_document_without_losing_sections() {
    let temporary = TemporaryDirectory::new("settings-migrate");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, br#"{"version":7,"appearance":{"windowRadius":31}}"#).unwrap();

    let manager = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(manager.revision(), 1);
    assert_eq!(manager.keyboard(), &KeyboardSettings::default());
    assert_eq!(manager.mouse(), &MouseSettings::default());
    assert_eq!(manager.touchpad(), &TouchpadSettings::default());
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    assert_eq!(document["version"], SETTINGS_SCHEMA_VERSION);
    assert_eq!(document["appearance"]["windowRadius"], 31);
    assert_eq!(
        document["appearance"]["colorSchemePreference"],
        "preferDark"
    );
    assert_eq!(document["appearance"]["allowClientCursorSurfaces"], true);
    assert_eq!(document["appearance"]["cursorSize"], DEFAULT_CURSOR_SIZE);
    assert_eq!(document["layout"]["windowLayout"], "stacking");
    assert_eq!(document["layout"]["scrollingLayoutPreserveSwapSizes"], true);
    assert_eq!(
        document["layout"]["scrollingLayoutWheelSpeed"],
        DEFAULT_SCROLLING_LAYOUT_WHEEL_SPEED
    );
    assert_eq!(
        document["layout"]["scrollingLayoutWheelUpDirection"],
        "left"
    );
    assert_eq!(document["layout"]["workspacesEnabled"], true);
    assert_eq!(document["layout"]["workspaceCount"], 4);
    assert_eq!(
        document["layout"]["workspaceSwitchingOrientation"],
        "horizontal"
    );
    assert_eq!(manager.workspace_settings(), WorkspaceSettings::default());
    assert_eq!(manager.window_layout_kind(), WindowLayoutKind::Stacking);
    assert!(manager.allow_client_cursor_surfaces());
    assert_eq!(
        manager.theme_snapshot(),
        DesktopThemeSnapshot::new(manager.revision(), DesktopColorSchemePreference::PreferDark,)
    );
    assert!(document.get("keyboard").is_some());
    assert!(document.get("mouse").is_some());
    assert!(document.get("touchpad").is_some());
    assert_eq!(
        document["applicationEnvironment"],
        serde_json::json!({"default": {}, "applications": {}})
    );
    assert_eq!(
        fs::metadata(path).unwrap().permissions().mode() & 0o777,
        0o600
    );
}

#[test]
fn malformed_document_is_never_overwritten_during_startup() {
    let temporary = TemporaryDirectory::new("settings-malformed");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    let malformed = b"{ this is not settings JSON\n";
    fs::write(&path, malformed).unwrap();

    let manager = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(manager.keyboard(), &KeyboardSettings::default());
    assert_eq!(manager.mouse(), &MouseSettings::default());
    assert_eq!(manager.touchpad(), &TouchpadSettings::default());
    assert_eq!(fs::read(path).unwrap(), malformed);
}

#[test]
fn shell_update_preserves_native_keyboard_and_checks_revision() {
    let temporary = TemporaryDirectory::new("settings-shell-update");
    let mut manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    let configured = KeyboardSettings {
        layouts: vec![KeyboardLayout {
            layout: "de".to_owned(),
            variant: "nodeadkeys".to_owned(),
        }],
        options: vec!["compose:menu".to_owned()],
        repeat_delay_ms: 450,
        repeat_rate_hz: 30,
    };
    let update = manager
        .prepare_keyboard_update(manager.revision(), configured.clone())
        .unwrap();
    manager.commit(update).unwrap();
    let configured_mouse = MouseSettings {
        speed: 0.35,
        acceleration_enabled: false,
        natural_scroll_enabled: true,
    };
    let update = manager
        .prepare_mouse_update(manager.revision(), configured_mouse.clone())
        .unwrap();
    manager.commit(update).unwrap();
    let old_revision = manager.revision();
    let shell_update = shell_document(serde_json::json!({
        "appearance": {
            "colorSchemePreference": "preferLight",
            "allowClientCursorSurfaces": false,
            "cursorSize": 48
        },
        "applicationEnvironment": {
            "default": {"MOZ_ENABLE_WAYLAND": "1", "DISPLAY": null},
            "applications": {
                "org.mozilla.firefox.desktop": {"MOZ_ENABLE_WAYLAND": "0"}
            }
        },
        "revision": 999,
        "keyboard": {"layouts": []},
        "mouse": {"speed": -0.8},
        "touchpad": {"tapToClickEnabled": false},
        "power": {"idleDpmsEnabled": false}
    }));
    let update = manager
        .prepare_shell_update(old_revision, &shell_update)
        .unwrap();
    manager.commit(update).unwrap();
    assert_eq!(manager.keyboard(), &configured);
    assert_eq!(manager.mouse(), &configured_mouse);
    assert_eq!(manager.revision(), old_revision + 1);
    assert_eq!(manager.cursor_size(), 48);
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    assert_eq!(
        document["applicationEnvironment"]["default"]["MOZ_ENABLE_WAYLAND"],
        "1"
    );
    assert_eq!(
        document["applicationEnvironment"]["default"]["DISPLAY"],
        Value::Null
    );
    assert_eq!(
        document["applicationEnvironment"]["applications"]["org.mozilla.firefox.desktop"]["MOZ_ENABLE_WAYLAND"],
        "0"
    );
    assert_eq!(
        manager.theme_snapshot().configured_preference,
        DesktopColorSchemePreference::PreferLight
    );
    assert!(!manager.allow_client_cursor_surfaces());
    let stale_update = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "preferDark"}
    }));
    assert!(matches!(
        manager.prepare_shell_update(old_revision, &stale_update),
        Err(SettingsError::Revision { .. })
    ));
}

#[test]
fn apps_scale_defaults_to_the_screen_and_rejects_out_of_range_values() {
    let temporary = TemporaryDirectory::new("settings-apps-scale");
    let mut manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    assert_eq!(manager.apps_scale(), 1.0);
    let with_scale = |scale: f64| {
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "apps": {"scale": scale}
        }))
    };
    for scale in [0.5, 3.5] {
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &with_scale(scale)),
            Err(SettingsError::Document(message)) if message.starts_with("apps.scale")
        ));
    }
    let document = with_scale(2.0);
    let update = manager
        .prepare_shell_update(manager.revision(), &document)
        .unwrap();
    manager.commit(update).unwrap();
    assert_eq!(manager.apps_scale(), 2.0);
}

#[test]
fn stay_awake_is_off_until_the_power_section_turns_it_on() {
    let temporary = TemporaryDirectory::new("settings-stay-awake");
    let mut manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    assert!(!manager.stay_awake());
    let with_power = |power: Value| {
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "power": power
        }))
    };
    for (power, expected) in [
        (
            serde_json::json!({"idleSuspendEnabled": true, "stayAwake": true}),
            true,
        ),
        (
            serde_json::json!({"idleSuspendEnabled": true, "stayAwake": false}),
            false,
        ),
        (serde_json::json!({"idleSuspendEnabled": true}), false),
    ] {
        let update = manager
            .prepare_shell_update(manager.revision(), &with_power(power))
            .unwrap();
        manager.commit(update).unwrap();
        assert_eq!(manager.stay_awake(), expected);
    }
}

#[test]
fn shell_update_rejects_missing_or_unknown_color_scheme() {
    let temporary = TemporaryDirectory::new("settings-color-scheme");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    for document in [
        shell_document(serde_json::json!({})),
        shell_document(serde_json::json!({"appearance": {}})),
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "automatic"}
        })),
    ] {
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &document),
            Err(SettingsError::Document(_))
        ));
    }
}

#[test]
fn window_layout_is_validated_and_persisted() {
    let temporary = TemporaryDirectory::new("settings-window-layout");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let update = manager
        .prepare_shell_update(
            manager.revision(),
            &shell_document(serde_json::json!({
                "appearance": {"colorSchemePreference": "preferDark"},
                "layout": {"windowLayout": "dwindle"}
            })),
        )
        .unwrap();
    manager.commit(update).unwrap();

    assert_eq!(manager.window_layout_kind(), WindowLayoutKind::Dwindle);
    assert_eq!(
        SettingsManager::load_path(path)
            .unwrap()
            .window_layout_kind(),
        WindowLayoutKind::Dwindle
    );

    let update = manager
        .prepare_shell_update(
            manager.revision(),
            &shell_document(serde_json::json!({
                "appearance": {"colorSchemePreference": "preferDark"},
                "layout": {"windowLayout": "scrolling"}
            })),
        )
        .unwrap();
    manager.commit(update).unwrap();
    assert_eq!(manager.window_layout_kind(), WindowLayoutKind::Scrolling);

    for window_layout in [Value::String("columns".to_owned()), Value::Bool(true)] {
        let document = shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "layout": {"windowLayout": window_layout}
        }));
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &document),
            Err(SettingsError::Document(_))
        ));
    }
}

#[test]
fn scrolling_layout_wheel_settings_are_validated_and_persisted() {
    let temporary = TemporaryDirectory::new("settings-scrolling-layout-wheel");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let update = manager
        .prepare_shell_update(
            manager.revision(),
            &shell_document(serde_json::json!({
                "appearance": {"colorSchemePreference": "preferDark"},
                "layout": {
                    "scrollingLayoutWheelSpeed": 2.25,
                    "scrollingLayoutWheelUpDirection": "right"
                }
            })),
        )
        .unwrap();
    manager.commit(update).unwrap();

    let configured = ScrollingLayoutWheelSettings {
        speed: 2.25,
        up_direction: ScrollingLayoutWheelUpDirection::Right,
    };
    assert_eq!(manager.scrolling_layout_wheel_settings(), configured);
    assert_eq!(
        SettingsManager::load_path(path)
            .unwrap()
            .scrolling_layout_wheel_settings(),
        configured
    );

    for speed in [0.249, 4.001] {
        let document = shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "layout": {"scrollingLayoutWheelSpeed": speed}
        }));
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &document),
            Err(SettingsError::Document(_))
        ));
    }
    let invalid_direction = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "preferDark"},
        "layout": {"scrollingLayoutWheelUpDirection": "up"}
    }));
    assert!(matches!(
        manager.prepare_shell_update(manager.revision(), &invalid_direction),
        Err(SettingsError::Document(_))
    ));
}

#[test]
fn touchpad_update_is_persistent_and_revisioned() {
    let temporary = TemporaryDirectory::new("settings-touchpad-update");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let configured = TouchpadSettings {
        tap_to_click_enabled: false,
        natural_scroll_enabled: true,
        scroll_speed_factor: 2.5,
        scrolling_layout_swipe_speed_factor: 1.75,
        speed: -0.4,
        acceleration_enabled: false,
        click_method: TouchpadClickMethod::ButtonAreas,
    };
    let old_revision = manager.revision();
    let update = manager
        .prepare_touchpad_update(old_revision, configured.clone())
        .unwrap();
    manager.commit(update).unwrap();

    assert_eq!(manager.revision(), old_revision + 1);
    assert_eq!(manager.touchpad(), &configured);
    let reloaded = SettingsManager::load_path(path).unwrap();
    assert_eq!(reloaded.revision(), old_revision + 1);
    assert_eq!(reloaded.touchpad(), &configured);
}

#[test]
fn display_color_is_saved_and_kept_from_shell_updates() {
    use super::super::color_grade::Grade;
    use super::super::output_color::{HdrMode, SignalPrimaries};
    let temporary = TemporaryDirectory::new("settings-color-update");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(manager.color(), &ColorSettings::default());
    let hdr = HdrMode {
        white: 150.0,
        primaries: SignalPrimaries::Srgb,
    };
    let color = manager
        .color()
        .clone()
        .with(ColorChange::Correction(false))
        .with(ColorChange::DesktopLut(Some("/luts/deep.cube".into())))
        .with(ColorChange::AppLut(
            "chromium".to_owned(),
            Some("/luts/warm.cube".into()),
        ))
        .with(ColorChange::Hdr("DP-4".to_owned(), Some(hdr)))
        .with(ColorChange::DesktopGrade(Some(Grade {
            exposure: 0.5,
            lift: [0.0, 0.0, 0.05],
            ..Grade::default()
        })))
        .with(ColorChange::AppGrade(
            "chromium".to_owned(),
            Some(Grade {
                saturation: 0.3,
                ..Grade::default()
            }),
        ));
    let update = manager
        .prepare_color_update(manager.revision(), color.clone())
        .unwrap();
    manager.commit(update).unwrap();
    let shell_update = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "preferDark"},
        "color": {"correction": true}
    }));
    let update = manager
        .prepare_shell_update(manager.revision(), &shell_update)
        .unwrap();
    manager.commit(update).unwrap();
    assert_eq!(manager.color(), &color);

    let reloaded = SettingsManager::load_path(path).unwrap();
    assert_eq!(reloaded.color(), &color);
    assert_eq!(reloaded.color().hdr["DP-4"], hdr);
    let cleared = color
        .with(ColorChange::DesktopLut(None))
        .with(ColorChange::Hdr("DP-4".to_owned(), None))
        .with(ColorChange::AppGrade("chromium".to_owned(), None));
    assert_eq!(cleared.desktop_lut, None);
    assert!(cleared.app_grades.is_empty());
    assert!(cleared.hdr.is_empty());
}

#[test]
fn rejects_relative_luts_and_out_of_range_color() {
    use super::super::output_color::HdrMode;
    let temporary = TemporaryDirectory::new("settings-color-validate");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    let relative = ColorSettings::default().with(ColorChange::DesktopLut(Some("deep.cube".into())));
    assert!(
        manager
            .prepare_color_update(manager.revision(), relative)
            .is_err()
    );
    let bright = ColorSettings::default().with(ColorChange::Hdr(
        "DP-4".to_owned(),
        Some(HdrMode {
            white: 5000.0,
            primaries: Default::default(),
        }),
    ));
    assert!(
        manager
            .prepare_color_update(manager.revision(), bright)
            .is_err()
    );
    let wild = ColorSettings::default().with(ColorChange::DesktopGrade(Some(
        super::super::color_grade::Grade {
            exposure: 40.0,
            ..Default::default()
        },
    )));
    assert!(
        manager
            .prepare_color_update(manager.revision(), wild)
            .is_err()
    );
}

#[test]
fn rejects_touchpad_scroll_speed_outside_supported_range() {
    let temporary = TemporaryDirectory::new("settings-touchpad-scroll-speed");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    for scroll_speed_factor in [0.049, 5.001, f64::NAN] {
        let configured = TouchpadSettings {
            scroll_speed_factor,
            ..TouchpadSettings::default()
        };
        assert!(matches!(
            manager.prepare_touchpad_update(manager.revision(), configured),
            Err(SettingsError::Touchpad(_))
        ));
    }
}

#[test]
fn rejects_touchpad_speed_outside_supported_range() {
    let temporary = TemporaryDirectory::new("settings-touchpad-speed");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    for speed in [-1.001, 1.001, f64::NAN] {
        let configured = TouchpadSettings {
            speed,
            ..TouchpadSettings::default()
        };
        assert!(matches!(
            manager.prepare_touchpad_update(manager.revision(), configured),
            Err(SettingsError::Touchpad(_))
        ));
    }
}

/// Loads a complete document with `touchpad` as its touchpad section and
/// returns the loaded settings, the saved section, and whether the file was
/// rewritten.
fn migrated_touchpad(touchpad: Value) -> (TouchpadSettings, Value, bool) {
    let temporary = TemporaryDirectory::new("settings-touchpad-fields");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    // deniald completes and writes a bare document once.
    fs::write(&path, format!(r#"{{"version":{SETTINGS_SCHEMA_VERSION}}}"#)).unwrap();
    SettingsManager::load_path(path.clone()).unwrap();
    let mut complete: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    complete["touchpad"] = touchpad;
    let written = serde_json::to_vec(&complete).unwrap();
    fs::write(&path, &written).unwrap();
    let manager = SettingsManager::load_path(path.clone()).unwrap();
    let bytes = fs::read(&path).unwrap();
    let saved: Value = serde_json::from_slice(&bytes).unwrap();
    (
        manager.touchpad().clone(),
        saved["touchpad"].clone(),
        bytes != written,
    )
}

#[test]
fn touchpad_section_from_before_pointer_settings_gets_their_defaults() {
    let (touchpad, saved, rewritten) = migrated_touchpad(serde_json::json!({
        "tapToClickEnabled": false,
        "naturalScrollEnabled": true,
        "scrollSpeedFactor": 2.0,
        "scrollingLayoutSwipeSpeedFactor": 1.5
    }));
    let expected = TouchpadSettings {
        tap_to_click_enabled: false,
        natural_scroll_enabled: true,
        scroll_speed_factor: 2.0,
        scrolling_layout_swipe_speed_factor: 1.5,
        ..TouchpadSettings::default()
    };
    assert_eq!(touchpad, expected);
    assert!(rewritten);
    assert_eq!(saved, serde_json::to_value(&expected).unwrap());
    assert_eq!(saved["speed"], 0.0);
    assert_eq!(saved["accelerationEnabled"], true);
    assert_eq!(saved["clickMethod"], "clickfinger");
}

#[test]
fn touchpad_click_methods_have_document_names() {
    for (name, method) in [
        ("clickfinger", TouchpadClickMethod::Clickfinger),
        ("buttonAreas", TouchpadClickMethod::ButtonAreas),
    ] {
        let touchpad: TouchpadSettings =
            serde_json::from_value(serde_json::json!({ "clickMethod": name })).unwrap();
        assert_eq!(touchpad.click_method, method);
        assert_eq!(serde_json::to_value(method).unwrap(), name);
    }
    assert!(
        serde_json::from_value::<TouchpadSettings>(serde_json::json!({"clickMethod": "corner"}))
            .is_err()
    );
}

#[test]
fn complete_touchpad_section_is_not_rewritten() {
    let configured = TouchpadSettings {
        speed: 0.35,
        acceleration_enabled: false,
        click_method: TouchpadClickMethod::ButtonAreas,
        ..TouchpadSettings::default()
    };
    let (touchpad, _, rewritten) = migrated_touchpad(serde_json::to_value(&configured).unwrap());
    assert_eq!(touchpad, configured);
    assert!(!rewritten);
}

#[test]
fn rejects_touchpad_scrolling_layout_swipe_speed_outside_supported_range() {
    let temporary = TemporaryDirectory::new("settings-touchpad-scrolling-layout-swipe-speed");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    for scrolling_layout_swipe_speed_factor in [0.249, 4.001, f64::NAN] {
        let configured = TouchpadSettings {
            scrolling_layout_swipe_speed_factor,
            ..TouchpadSettings::default()
        };
        assert!(matches!(
            manager.prepare_touchpad_update(manager.revision(), configured),
            Err(SettingsError::Touchpad(_))
        ));
    }
}

#[test]
fn mouse_update_is_persistent_and_revisioned() {
    let temporary = TemporaryDirectory::new("settings-mouse-update");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let configured = MouseSettings {
        speed: 0.55,
        acceleration_enabled: false,
        natural_scroll_enabled: true,
    };
    let old_revision = manager.revision();
    let update = manager
        .prepare_mouse_update(old_revision, configured.clone())
        .unwrap();
    manager.commit(update).unwrap();

    assert_eq!(manager.revision(), old_revision + 1);
    assert_eq!(manager.mouse(), &configured);
    let reloaded = SettingsManager::load_path(path).unwrap();
    assert_eq!(reloaded.revision(), old_revision + 1);
    assert_eq!(reloaded.mouse(), &configured);
}

#[test]
fn rejects_mouse_speed_outside_supported_range() {
    let temporary = TemporaryDirectory::new("settings-mouse-speed");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    for speed in [-1.001, 1.001, f64::NAN] {
        assert!(matches!(
            manager.prepare_mouse_update(
                manager.revision(),
                MouseSettings {
                    speed,
                    ..MouseSettings::default()
                }
            ),
            Err(SettingsError::Mouse(_))
        ));
    }
}

#[test]
fn rejects_external_edits_before_commit() {
    let temporary = TemporaryDirectory::new("settings-conflict");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let shell_update = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "preferDark"}
    }));
    let prepared = manager
        .prepare_shell_update(manager.revision(), &shell_update)
        .unwrap();
    let external_edit = shell_document(serde_json::json!({"revision": 77}));
    fs::write(&path, format!("{external_edit}\n")).unwrap();
    assert!(matches!(
        manager.commit(prepared),
        Err(SettingsError::Conflict)
    ));
}

#[test]
fn reloads_external_edit_with_an_authoritative_revision() {
    let temporary = TemporaryDirectory::new("settings-external-reload");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let old_revision = manager.revision();
    let external_edit = shell_document(serde_json::json!({
        "revision": 9000,
        "appearance": {
            "colorSchemePreference": "preferLight",
            "cursorSize": 48
        },
        "externalEditorMarker": true
    }));
    fs::write(&path, format!("{external_edit}\n")).unwrap();

    let prepared = manager
        .prepare_external_reload()
        .unwrap()
        .expect("external bytes should produce a transaction");
    manager.commit(prepared).unwrap();

    assert_eq!(manager.revision(), old_revision + 1);
    assert_eq!(manager.cursor_size(), 48);
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    assert_eq!(document["revision"], old_revision + 1);
    assert_eq!(
        document["appearance"]["colorSchemePreference"],
        "preferLight"
    );
    assert_eq!(document["externalEditorMarker"], true);
    assert!(manager.prepare_external_reload().unwrap().is_none());

    let update = manager
        .prepare_mouse_update(
            manager.revision(),
            MouseSettings {
                speed: 0.25,
                ..MouseSettings::default()
            },
        )
        .unwrap();
    manager.commit(update).unwrap();
}

#[test]
fn external_removal_restores_and_recreates_defaults() {
    let temporary = TemporaryDirectory::new("settings-external-removal");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let update = manager
        .prepare_mouse_update(
            manager.revision(),
            MouseSettings {
                speed: 0.75,
                ..MouseSettings::default()
            },
        )
        .unwrap();
    manager.commit(update).unwrap();
    let old_revision = manager.revision();
    fs::remove_file(&path).unwrap();

    let prepared = manager
        .prepare_external_reload()
        .unwrap()
        .expect("removal should produce a default-settings transaction");
    manager.commit(prepared).unwrap();

    assert_eq!(manager.revision(), old_revision + 1);
    assert_eq!(manager.mouse(), &MouseSettings::default());
    assert!(path.is_file());
}

#[test]
fn invalid_external_edit_stays_on_disk_without_changing_live_state() {
    let temporary = TemporaryDirectory::new("settings-invalid-external-reload");
    let path = temporary.settings_path();
    let manager = SettingsManager::load_path(path.clone()).unwrap();
    let old_revision = manager.revision();
    fs::write(&path, b"{ invalid json\n").unwrap();

    assert!(matches!(
        manager.prepare_external_reload(),
        Err(SettingsError::Json(_))
    ));
    assert_eq!(manager.revision(), old_revision);
    assert_eq!(fs::read(&path).unwrap(), b"{ invalid json\n");
}

#[test]
fn rejects_a_second_external_edit_during_reload() {
    let temporary = TemporaryDirectory::new("settings-external-reload-race");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    let first = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "preferLight"}
    }));
    fs::write(&path, format!("{first}\n")).unwrap();
    let prepared = manager
        .prepare_external_reload()
        .unwrap()
        .expect("first external edit should prepare");
    let second = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "noPreference"}
    }));
    fs::write(&path, format!("{second}\n")).unwrap();

    assert!(matches!(
        manager.commit(prepared),
        Err(SettingsError::Conflict)
    ));
}

#[test]
fn rejects_symlink_target() {
    let temporary = TemporaryDirectory::new("settings-symlink");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    let target = temporary.0.join("target");
    fs::write(&target, b"{}\n").unwrap();
    symlink(&target, &path).unwrap();
    assert!(matches!(
        SettingsManager::load_path(path),
        Err(SettingsError::Path(_))
    ));
}

#[test]
fn validates_keyboard_bounds_and_installed_keymaps() {
    let defaults = KeyboardSettings::default();
    assert_eq!(defaults.compiled_layout_names().unwrap().len(), 1);

    let mut invalid = defaults.clone();
    invalid.layouts[0].layout = "not,a,layout".to_owned();
    assert!(matches!(
        invalid.validate(),
        Err(SettingsError::Keyboard(_))
    ));

    let mut missing = defaults;
    missing.layouts[0].layout = "denial_missing_layout".to_owned();
    assert!(matches!(
        missing.compiled_layout_names(),
        Err(SettingsError::Keyboard(_))
    ));
}

#[test]
fn validates_application_environment_before_writing() {
    let temporary = TemporaryDirectory::new("settings-application-environment");
    let manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    let valid_document = shell_document(serde_json::json!({
        "appearance": {"colorSchemePreference": "preferDark"},
        "applicationEnvironment": {
            "default": {"EMPTY": "", "REMOVE_ME": null},
            "applications": {"org.example.App.desktop": {"APP_ONLY": "1"}}
        }
    }));
    let valid = manager
        .prepare_shell_update(manager.revision(), &valid_document)
        .expect("valid application environment");
    drop(valid);

    for document in [
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "applicationEnvironment": []
        })),
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "applicationEnvironment": {
                "default": {"invalid-name": "value"}, "applications": {}
            }
        })),
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "applicationEnvironment": {
                "default": {"VALID": 3}, "applications": {}
            }
        })),
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "applicationEnvironment": {
                "default": {},
                "applications": {"not/a.desktop": {"VALID": "1"}}
            }
        })),
    ] {
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &document),
            Err(SettingsError::Document(_))
        ));
    }
}

#[test]
fn gtk_input_method_policy_is_split_by_display_backend() {
    fn environment(value: serde_json::Value) -> ApplicationEnvironment {
        let document = serde_json::json!({"applicationEnvironment": value});
        ApplicationEnvironment::from_document(document.as_object().unwrap()).unwrap()
    }

    assert_eq!(GTK_INPUT_METHOD_BACKEND_FALLBACK, "wayland:xim");
    assert_eq!(x11_gtk_input_method_backend_fallback(), "xim");

    let configured = environment(serde_json::json!({
        "default": {"XMODIFIERS": "@im=fcitx"},
        "applications": {}
    }));
    let mut command = Command::new("true");
    configured.apply(&mut command, None, None);
    let child_environment = command.get_envs().collect::<BTreeMap<_, _>>();
    assert_eq!(
        child_environment.get(OsStr::new("XMODIFIERS")),
        Some(&Some(OsStr::new("@im=fcitx")))
    );
    assert!(!child_environment.contains_key(OsStr::new("GTK_IM_MODULE")));
}

#[test]
fn scrolling_swap_size_setting_is_validated_and_persisted() {
    let temporary = TemporaryDirectory::new("settings-scrolling-swap-size");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    assert!(manager.scrolling_layout_preserve_swap_sizes());
    for enabled in [false, true] {
        let update = manager
            .prepare_shell_update(
                manager.revision(),
                &shell_document(serde_json::json!({
                    "appearance": {"colorSchemePreference": "preferDark"},
                    "layout": {"scrollingLayoutPreserveSwapSizes": enabled}
                })),
            )
            .unwrap();
        manager.commit(update).unwrap();
        assert_eq!(manager.scrolling_layout_preserve_swap_sizes(), enabled);
        assert_eq!(
            SettingsManager::load_path(path.clone())
                .unwrap()
                .scrolling_layout_preserve_swap_sizes(),
            enabled
        );
    }
    for invalid in [Value::Null, Value::from(1), Value::from("false")] {
        let document = shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "layout": {"scrollingLayoutPreserveSwapSizes": invalid}
        }));
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &document),
            Err(SettingsError::Document(_))
        ));
    }
}

#[test]
fn keyboard_resize_step_defaults_and_validates_on_load_and_update() {
    use super::super::keyboard_resize::ResizeStep;
    let temporary = TemporaryDirectory::new("keyboard-resize-step");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(manager.keyboard_resize_step(), ResizeStep::Percent(2.0));
    for (value, expected) in [
        ("32px", ResizeStep::Pixels(32.0)),
        ("5%", ResizeStep::Percent(5.0)),
    ] {
        let document = shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "layout": {"keyboardResizeStep": value}
        }));
        let update = manager
            .prepare_shell_update(manager.revision(), &document)
            .unwrap();
        manager.commit(update).unwrap();
        assert_eq!(manager.keyboard_resize_step(), expected);
        assert_eq!(
            SettingsManager::load_path(path.clone())
                .unwrap()
                .keyboard_resize_step(),
            expected
        );
    }
    for value in [
        serde_json::json!(0),
        serde_json::json!("-10%"),
        serde_json::json!("101%"),
        Value::Null,
    ] {
        let document = shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "layout": {"keyboardResizeStep": value}
        }));
        assert!(
            manager
                .prepare_shell_update(manager.revision(), &document)
                .is_err()
        );
    }
    let mut invalid = manager.document.clone();
    invalid["layout"]["keyboardResizeStep"] = Value::String("0px".into());
    let bytes = serde_json::to_vec(&invalid).unwrap();
    assert!(parse_document(&bytes).is_err());
    fs::write(&path, &bytes).unwrap();
    assert_eq!(
        SettingsManager::load_path(path.clone())
            .unwrap()
            .keyboard_resize_step(),
        ResizeStep::default()
    );
    assert_eq!(fs::read(&path).unwrap(), bytes);
}

#[test]
fn rotation_lock_captures_applied_orientation_and_survives_restart() {
    let directory = TemporaryDirectory::new("rotation-lock");
    let path = directory.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    manager.rotation_lock_supported = true;
    manager.current_sensor_rotation = OutputTransform::Rotate270;
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    let mut request = document.clone();
    request["rotationLock"] = serde_json::json!({"enabled": true, "orientation": 90});
    let prepared = manager
        .prepare_shell_update(manager.revision(), &request.to_string())
        .unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(
        manager.locked_sensor_rotation(),
        Some(OutputTransform::Rotate270)
    );
    assert_eq!(
        SettingsManager::load_path(path.clone())
            .unwrap()
            .locked_sensor_rotation(),
        Some(OutputTransform::Rotate270)
    );
    // Native-only snapshot metadata is not persisted or trusted from the shell.
    let saved: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert!(saved.get("rotationLockSupported").is_none());
    let mut legacy_request = request.clone();
    legacy_request
        .as_object_mut()
        .unwrap()
        .remove("rotationLock");
    let prepared = manager
        .prepare_shell_update(manager.revision(), &legacy_request.to_string())
        .unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(
        manager.locked_sensor_rotation(),
        Some(OutputTransform::Rotate270)
    );
    manager.current_sensor_rotation = OutputTransform::Rotate90;
    request["rotationLock"] = serde_json::json!({"enabled": true, "orientation": 180});
    let prepared = manager
        .prepare_shell_update(manager.revision(), &request.to_string())
        .unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(
        manager.locked_sensor_rotation(),
        Some(OutputTransform::Rotate270)
    );
    request["rotationLock"] = serde_json::json!({"enabled": false});
    let prepared = manager
        .prepare_shell_update(manager.revision(), &request.to_string())
        .unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(manager.locked_sensor_rotation(), None);
    request["rotationLock"] = serde_json::json!({"enabled": true});
    let prepared = manager
        .prepare_shell_update(manager.revision(), &request.to_string())
        .unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(
        manager.locked_sensor_rotation(),
        Some(OutputTransform::Rotate90)
    );
}

#[test]
fn rotation_lock_invalid_settings_and_revision_conflicts_are_safe() {
    let directory = TemporaryDirectory::new("rotation-lock-invalid");
    let mut manager = SettingsManager::load_path(directory.settings_path()).unwrap();
    assert_eq!(manager.locked_sensor_rotation(), None);
    let mut document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    document["rotationLock"] = serde_json::json!({"enabled": "yes"});
    assert!(
        manager
            .prepare_shell_update(manager.revision(), &document.to_string())
            .is_err()
    );
    document["rotationLock"] = serde_json::json!({"enabled": true});
    assert!(
        manager
            .prepare_shell_update(manager.revision() + 1, &document.to_string())
            .is_err()
    );
    assert_eq!(manager.locked_sensor_rotation(), None);
    for invalid in [
        serde_json::json!(45),
        serde_json::json!(-90),
        serde_json::json!("90"),
    ] {
        document["rotationLock"] = serde_json::json!({"enabled": true, "orientation": invalid});
        assert!(parse_document(document.to_string().as_bytes()).is_err());
    }
    let bytes = document.to_string().into_bytes();
    fs::write(manager.path(), &bytes).unwrap();
    manager = SettingsManager::load_path(manager.path().to_path_buf()).unwrap();
    assert_eq!(manager.locked_sensor_rotation(), None);
    assert_eq!(fs::read(manager.path()).unwrap(), bytes);
}

#[test]
fn rotation_lock_external_enable_captures_current_not_editor_orientation() {
    let directory = TemporaryDirectory::new("rotation-lock-editor");
    let mut manager = SettingsManager::load_path(directory.settings_path()).unwrap();
    manager.current_sensor_rotation = OutputTransform::Rotate180;
    let mut document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    document["rotationLock"] = serde_json::json!({"enabled": true, "orientation": 0});
    fs::write(manager.path(), document.to_string()).unwrap();
    let prepared = manager.prepare_external_reload().unwrap().unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(
        manager.locked_sensor_rotation(),
        Some(OutputTransform::Rotate180)
    );
    document["rotationLock"] = serde_json::json!({"enabled": false, "orientation": 0});
    fs::write(manager.path(), document.to_string()).unwrap();
    let prepared = manager.prepare_external_reload().unwrap().unwrap();
    manager.commit(prepared).unwrap();
    assert_eq!(manager.locked_sensor_rotation(), None);
}

#[test]
fn mobile_default_document_seeds_the_mobile_appearance() {
    let (desktop, _, _) = default_document(false);
    assert!(desktop["appearance"].get("glass").is_none());
    assert!(desktop["appearance"].get("cornerRadiusScale").is_none());

    let (mobile, _, _) = default_document(true);
    let appearance = &mobile["appearance"];
    assert_eq!(appearance["customAccentColor"], 0xFFD0_BCFF_u32);
    assert_eq!(appearance["cornerRadiusScale"], 1.6);
    assert_eq!(appearance["monitorCornerRadiusScale"], 0.4);
    assert_eq!(appearance["glass"]["opacity"], 0.2);
    assert_eq!(appearance["glass"]["windowOpacity"], 0.5);
    assert_eq!(appearance["glass"]["appPanelOpacity"], 0.4);
    assert_eq!(appearance["glass"]["blurSigma"], 26.1);
    assert_eq!(appearance["colorSchemePreference"], "preferDark");
    assert_eq!(mobile["power"]["idleDpmsTimeoutSeconds"], 30);
    assert!(desktop.get("power").is_none());
    assert_eq!(mobile["apps"]["scale"], 1.25);
    assert!(desktop.get("apps").is_none());
    parse_document(serde_json::to_string(&mobile).unwrap().as_bytes()).unwrap();
}

#[test]
fn apps_follow_the_shell_by_default_and_validate_their_text_scales() {
    let temporary = TemporaryDirectory::new("settings-apps-follow");
    let mut manager = SettingsManager::load_path(temporary.settings_path()).unwrap();
    assert_eq!(manager.apps_follow(), AppsFollow::default());
    assert!(manager.apps_follow().enabled);
    let with_apps = |apps: Value| {
        shell_document(serde_json::json!({
            "appearance": {"colorSchemePreference": "preferDark"},
            "apps": apps
        }))
    };
    for (apps, key) in [
        (serde_json::json!({"followMode": "yes"}), "apps.followMode"),
        (
            serde_json::json!({"tabletTextScale": 0.4}),
            "apps.tabletTextScale",
        ),
        (
            serde_json::json!({"desktopTextScale": 3.5}),
            "apps.desktopTextScale",
        ),
        (
            serde_json::json!({"tabletTextScale": "big"}),
            "apps.tabletTextScale",
        ),
    ] {
        assert!(matches!(
            manager.prepare_shell_update(manager.revision(), &with_apps(apps)),
            Err(SettingsError::Document(message)) if message.starts_with(key)
        ));
    }
    let document = with_apps(serde_json::json!({
        "scale": 1.25,
        "followMode": false,
        "tabletTextScale": 1.15,
        "desktopTextScale": null
    }));
    let update = manager
        .prepare_shell_update(manager.revision(), &document)
        .unwrap();
    manager.commit(update).unwrap();
    assert_eq!(
        manager.apps_follow(),
        AppsFollow {
            enabled: false,
            tablet_text_scaling_milli: Some(1150),
            desktop_text_scaling_milli: None,
        }
    );
    assert_eq!(manager.apps_scale(), 1.25);
}

#[test]
fn apps_follow_only_a_tablets_shell_and_only_while_switched_on() {
    let follow = AppsFollow {
        enabled: true,
        tablet_text_scaling_milli: Some(1150),
        desktop_text_scaling_milli: None,
    };
    assert_eq!(
        follow.shell_state(DesktopPresentation::Tablet, false),
        DesktopShellState {
            presentation: DesktopPresentation::Tablet,
            keyboard_attached: false,
            tablet_mode: true,
            text_scaling_milli: Some(1150),
        }
    );
    // Desktop presentation: no touch layouts, and with no desktop text
    // scale set the desktop's own setting stands.
    assert_eq!(
        follow.shell_state(DesktopPresentation::Desktop, true),
        DesktopShellState {
            presentation: DesktopPresentation::Desktop,
            keyboard_attached: true,
            tablet_mode: false,
            text_scaling_milli: None,
        }
    );
    // Switched off: the presentation and keyboard are still published, but
    // apps are told nothing to follow.
    let off = AppsFollow {
        enabled: false,
        ..follow
    };
    assert_eq!(
        off.shell_state(DesktopPresentation::Tablet, true),
        DesktopShellState {
            presentation: DesktopPresentation::Tablet,
            keyboard_attached: true,
            tablet_mode: false,
            text_scaling_milli: None,
        }
    );
}

/// Loads a complete document with `power` as its power section and returns
/// the migrated section, and whether the file was rewritten.
fn migrated_power(power: Value) -> (serde_json::Map<String, Value>, bool) {
    let temporary = TemporaryDirectory::new("settings-suspend-after");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    // deniald completes and writes a bare document once.
    fs::write(&path, format!(r#"{{"version":{SETTINGS_SCHEMA_VERSION}}}"#)).unwrap();
    SettingsManager::load_path(path.clone()).unwrap();
    let mut complete: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    complete["power"] = power;
    let written = serde_json::to_vec(&complete).unwrap();
    fs::write(&path, &written).unwrap();
    let manager = SettingsManager::load_path(path.clone()).unwrap();
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    let rewritten = fs::read(&path).unwrap() != written;
    (document["power"].as_object().unwrap().clone(), rewritten)
}

#[test]
fn a_suspend_timeout_no_longer_than_the_display_timeout_carries_over() {
    // The tablet's owner: the screen off after 30 min, sleep after 5 min,
    // which the shell had stretched to 30 min after the last touch.
    let (power, rewritten) = migrated_power(serde_json::json!({
        "idleDpmsTimeoutSeconds": 1800,
        "idleSuspendEnabled": true,
        "idleSuspendTimeoutSeconds": 300,
        "stayAwake": false,
        "powerButtonAction": "dpms",
    }));
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 300);
    assert_eq!(power["idleSuspendEnabled"], true);
    assert_eq!(power["idleDpmsTimeoutSeconds"], 1800);
    // Kept for an older Denial.
    assert_eq!(power["idleSuspendTimeoutSeconds"], 300);
    assert!(rewritten);
    // Equal timeouts carry over too.
    let (power, _) = migrated_power(serde_json::json!({
        "idleDpmsTimeoutSeconds": 900,
        "idleSuspendTimeoutSeconds": 900,
    }));
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 900);
}

#[test]
fn a_longer_suspend_timeout_keeps_what_was_left_after_the_screen_went_dark() {
    let (power, _) = migrated_power(serde_json::json!({
        "idleDpmsTimeoutSeconds": 900,
        "idleSuspendTimeoutSeconds": 1800,
    }));
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 900);
    // A display timeout the document leaves out was the shell's 15 min.
    let (power, _) = migrated_power(serde_json::json!({"idleSuspendTimeoutSeconds": 2700}));
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 1800);
    // Never shorter than half a minute.
    let (power, _) = migrated_power(serde_json::json!({
        "idleDpmsTimeoutSeconds": 900,
        "idleSuspendTimeoutSeconds": 910,
    }));
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 30);
}

#[test]
fn suspend_migration_keeps_it_disabled_and_runs_once() {
    let (power, rewritten) = migrated_power(serde_json::json!({
        "idleDpmsTimeoutSeconds": 600,
        "idleSuspendEnabled": false,
        "idleSuspendTimeoutSeconds": 1200,
    }));
    assert_eq!(power["idleSuspendEnabled"], false);
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 600);
    assert!(rewritten);

    // Already there: left as it is, the file untouched.
    let (power, rewritten) = migrated_power(serde_json::json!({
        "idleDpmsTimeoutSeconds": 1800,
        "idleSuspendTimeoutSeconds": 300,
        "idleSuspendAfterScreenOffSeconds": 120,
    }));
    assert_eq!(power["idleSuspendAfterScreenOffSeconds"], 120);
    assert!(!rewritten);

    // Nothing stored: the shell's default applies, nothing is written.
    let (power, rewritten) = migrated_power(serde_json::json!({"idleDpmsTimeoutSeconds": 30}));
    assert!(!power.contains_key("idleSuspendAfterScreenOffSeconds"));
    assert!(!rewritten);
}

#[test]
fn suspend_migration_follows_the_minutes_migration() {
    let temporary = TemporaryDirectory::new("settings-suspend-minutes");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(
        &path,
        br#"{"version":29,"power":{"idleDpmsTimeoutMinutes":15,"idleSuspendTimeoutMinutes":45}}"#,
    )
    .unwrap();
    let manager = SettingsManager::load_path(path).unwrap();
    let document: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    assert_eq!(document["power"]["idleSuspendTimeoutSeconds"], 2700);
    assert_eq!(document["power"]["idleSuspendAfterScreenOffSeconds"], 1800);
}

/// What `deniald` up to `eb16.tp1` accepts in `layout.windowLayout`: any
/// other value makes it reject the whole file and run on defaults.
fn older_deniald_accepts(file: &Value) -> bool {
    matches!(
        file["layout"]["windowLayout"].as_str(),
        Some("stacking" | "dwindle" | "scrolling")
    )
}

fn commit_window_layout(manager: &mut SettingsManager, layout: Value) {
    let update = manager
        .prepare_shell_update(
            manager.revision(),
            &shell_document(serde_json::json!({
                "appearance": {"colorSchemePreference": "preferDark"},
                "layout": layout
            })),
        )
        .unwrap();
    manager.commit(update).unwrap();
}

#[test]
fn screens_layout_is_stored_so_an_older_deniald_still_loads_the_file() {
    let temporary = TemporaryDirectory::new("settings-screens-layout");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    commit_window_layout(&mut manager, serde_json::json!({"windowLayout": "screens"}));
    assert_eq!(manager.window_layout_kind(), WindowLayoutKind::Screens);

    // On disk: a layout every release knows, the real one beside it.
    let file: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert!(older_deniald_accepts(&file));
    assert_eq!(file["layout"]["windowLayout"], "scrolling");
    assert_eq!(file["layout"]["windowLayoutVariant"], "screens");

    // Served to the shell and Settings as itself.
    let served: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    assert_eq!(served["layout"]["windowLayout"], "screens");
    assert!(served["layout"].get("windowLayoutVariant").is_none());

    // This release reads it back, and an external edit of the file is no
    // change at all.
    let reloaded = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(reloaded.window_layout_kind(), WindowLayoutKind::Screens);
    assert!(manager.prepare_external_reload().unwrap().is_none());

    // Leaving the layout leaves no variant behind.
    commit_window_layout(&mut manager, serde_json::json!({"windowLayout": "dwindle"}));
    let file: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(file["layout"]["windowLayout"], "dwindle");
    assert!(file["layout"].get("windowLayoutVariant").is_none());
}

#[test]
fn a_stale_or_unknown_layout_variant_keeps_the_stored_layout() {
    let temporary = TemporaryDirectory::new("settings-layout-variant");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    for (stored, variant, expected) in [
        // An older release changed the layout since: its choice stands.
        ("dwindle", "screens", WindowLayoutKind::Dwindle),
        // A layout from a newer release: its fallback stands.
        ("scrolling", "tiles", WindowLayoutKind::Scrolling),
        ("scrolling", "screens", WindowLayoutKind::Screens),
    ] {
        fs::write(
            &path,
            serde_json::to_vec(&serde_json::json!({
                "version": SETTINGS_SCHEMA_VERSION,
                "revision": 3,
                "layout": {"windowLayout": stored, "windowLayoutVariant": variant}
            }))
            .unwrap(),
        )
        .unwrap();
        let manager = SettingsManager::load_path(path.clone()).unwrap();
        assert_eq!(manager.window_layout_kind(), expected, "{stored} {variant}");
        let served: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
        assert!(served["layout"].get("windowLayoutVariant").is_none());
    }
}

#[test]
fn screens_layout_turns_workspaces_off_but_keeps_the_users_choice() {
    let temporary = TemporaryDirectory::new("settings-screens-workspaces");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path).unwrap();
    commit_window_layout(
        &mut manager,
        serde_json::json!({"windowLayout": "dwindle", "workspacesEnabled": true, "workspaceCount": 5}),
    );
    assert!(manager.workspace_settings().enabled);

    commit_window_layout(
        &mut manager,
        serde_json::json!({"windowLayout": "screens", "workspacesEnabled": true, "workspaceCount": 5}),
    );
    let workspaces = manager.workspace_settings();
    assert!(!workspaces.enabled);
    assert_eq!(workspaces.count, 5);
    let served: Value = serde_json::from_str(&manager.document_json().unwrap()).unwrap();
    assert_eq!(served["layout"]["workspacesEnabled"], true);

    commit_window_layout(
        &mut manager,
        serde_json::json!({"windowLayout": "dwindle", "workspacesEnabled": true, "workspaceCount": 5}),
    );
    assert!(manager.workspace_settings().enabled);
}

#[test]
fn the_shortcut_preset_is_its_own_section_older_releases_skip() {
    use crate::native_shortcut::ShortcutPreset;

    let temporary = TemporaryDirectory::new("settings-shortcut-preset");
    let path = temporary.settings_path();
    let mut manager = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(manager.shortcut_preset(), ShortcutPreset::Standard);
    let before: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();

    // Settings writes it through the shell document, as any other key.
    let update = manager
        .prepare_shell_update(
            manager.revision(),
            &shell_document(serde_json::json!({
                "appearance": {"colorSchemePreference": "preferDark"},
                "shortcuts": {"preset": "mac"}
            })),
        )
        .unwrap();
    manager.commit(update).unwrap();
    assert_eq!(manager.shortcut_preset(), ShortcutPreset::Mac);

    // On disk it is one new top-level section. Releases up to eb17 read only
    // the sections they know (and keep the rest), and none of the sections
    // they parse strictly (keyboard, mouse, touchpad, color) changed.
    let file: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(file["shortcuts"], serde_json::json!({"preset": "mac"}));
    for section in ["keyboard", "mouse", "touchpad", "color"] {
        assert_eq!(file[section], before[section], "{section}");
    }
    serde_json::from_value::<KeyboardSettings>(file["keyboard"].clone()).unwrap();
    serde_json::from_value::<MouseSettings>(file["mouse"].clone()).unwrap();
    serde_json::from_value::<TouchpadSettings>(file["touchpad"].clone()).unwrap();
    serde_json::from_value::<ColorSettings>(file["color"].clone()).unwrap();

    // This release reads it back.
    let reloaded = SettingsManager::load_path(path.clone()).unwrap();
    assert_eq!(reloaded.shortcut_preset(), ShortcutPreset::Mac);
}

#[test]
fn an_unknown_shortcut_preset_reads_as_the_standard_keys() {
    use crate::native_shortcut::ShortcutPreset;

    let temporary = TemporaryDirectory::new("settings-shortcut-preset-unknown");
    let path = temporary.settings_path();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    for preset in [
        serde_json::json!("windows"),
        serde_json::json!(true),
        serde_json::json!(null),
    ] {
        fs::write(
            &path,
            serde_json::to_vec(&serde_json::json!({
                "version": SETTINGS_SCHEMA_VERSION,
                "revision": 3,
                "shortcuts": {"preset": preset}
            }))
            .unwrap(),
        )
        .unwrap();
        // The file loads: a value from a newer release rejects nothing.
        let manager = SettingsManager::load_path(path.clone()).unwrap();
        assert_eq!(manager.revision(), 3);
        assert_eq!(manager.shortcut_preset(), ShortcutPreset::Standard);
    }
}
