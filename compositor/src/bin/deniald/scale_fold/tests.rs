use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{Value, json};

use super::fold_apps_scale;
use crate::settings::SettingsManager;

static SEQUENCE: AtomicU64 = AtomicU64::new(0);

const MANAGED: &str = "# Output settings managed by Denial output control.";

/// A user's settings document and output config, in a folder of their own.
struct Files(PathBuf);

impl Files {
    fn new(settings: Value, outputs: &str) -> Self {
        let folder = std::env::temp_dir().join(format!(
            "denial-scale-fold-{}-{}",
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(folder.join("denial")).unwrap();
        fs::write(
            folder.join("denial/settings.json"),
            serde_json::to_vec(&settings).unwrap(),
        )
        .unwrap();
        fs::write(folder.join("outputs.conf"), outputs).unwrap();
        Self(folder)
    }

    fn settings(&self) -> SettingsManager {
        SettingsManager::load_path(self.0.join("denial/settings.json")).unwrap()
    }

    fn outputs(&self) -> PathBuf {
        self.0.join("outputs.conf")
    }

    fn outputs_text(&self) -> String {
        fs::read_to_string(self.outputs()).unwrap()
    }

    fn settings_document(&self) -> Value {
        serde_json::from_slice(&fs::read(self.0.join("denial/settings.json")).unwrap()).unwrap()
    }
}

impl Drop for Files {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn an_eb18_tablet_keeps_its_apps_size_and_the_shell_joins_them() {
    // eb18 on the Pad 3: the shell at 2.5, apps 1.2 times larger. Settings
    // saved the panel's lines under the managed header.
    let outputs = format!(
        "# The tablet's own file.\n\n{MANAGED}\n\
         DSI-1=0,0\nmode=DSI-1,3392,2400,120000\nscale=DSI-1,2.5\n"
    );
    let files = Files::new(
        json!({"version": 30, "apps": {"scale": 1.2, "followMode": false}}),
        &outputs,
    );
    let mut settings = files.settings();
    let mut scales_120 = BTreeMap::from([("DSI-1".to_owned(), 300)]);

    fold_apps_scale(
        &mut settings,
        &mut scales_120,
        [("DSI-1", 300)],
        Some(&files.outputs()),
    );

    assert_eq!(
        files.outputs_text(),
        outputs.replace("scale=DSI-1,2.5", "scale=DSI-1,3")
    );
    assert_eq!(scales_120, BTreeMap::from([("DSI-1".to_owned(), 360)]));
    assert_eq!(settings.apps_scale(), 1.0);
    // Every older deniald reads a missing apps scale as 1.
    assert_eq!(files.settings_document()["apps"], json!({"followMode": false}));

    // The next start finds nothing to fold.
    let (folded_outputs, folded_settings) = (files.outputs_text(), files.settings_document());
    fold_apps_scale(
        &mut files.settings(),
        &mut scales_120,
        [("DSI-1", 300)],
        Some(&files.outputs()),
    );
    assert_eq!(files.outputs_text(), folded_outputs);
    assert_eq!(files.settings_document(), folded_settings);
    assert_eq!(scales_120, BTreeMap::from([("DSI-1".to_owned(), 360)]));
}

#[test]
fn a_default_scale_and_a_remembered_monitor_fold_as_well() {
    // A new user of erhai-denial 1.9: apps 1.25 times the shell, the panel at
    // its default 2.5 with no scale line, and a monitor seen before at 1.5.
    let files = Files::new(
        json!({"version": 30, "apps": {"scale": 1.25}}),
        "mode=DSI-1,3392,2400,120000\nscale=DP-1,1.5\n",
    );
    let mut settings = files.settings();
    let mut scales_120 = BTreeMap::from([("DP-1".to_owned(), 180)]);

    fold_apps_scale(
        &mut settings,
        &mut scales_120,
        [("DSI-1", 300)],
        Some(&files.outputs()),
    );

    assert_eq!(
        files.outputs_text(),
        format!("mode=DSI-1,3392,2400,120000\nscale=DP-1,1.875\n\n{MANAGED}\nscale=DSI-1,3.125\n")
    );
    assert_eq!(
        scales_120,
        BTreeMap::from([("DP-1".to_owned(), 225), ("DSI-1".to_owned(), 375)])
    );
    assert!(files.settings_document().get("apps").is_none());
}

#[test]
fn one_scale_already_leaves_both_files_alone() {
    // The owner's tablet: the panel at 2, apps at the same size.
    let outputs = format!("{MANAGED}\nDSI-1=0,0\nscale=DSI-1,2\n");
    let files = Files::new(json!({"version": 30, "apps": {"scale": 1.0}}), &outputs);
    let mut settings = files.settings();
    let before = files.settings_document();
    let mut scales_120 = BTreeMap::from([("DSI-1".to_owned(), 240)]);

    fold_apps_scale(
        &mut settings,
        &mut scales_120,
        [("DSI-1", 300)],
        Some(&files.outputs()),
    );

    assert_eq!(files.outputs_text(), outputs);
    assert_eq!(files.settings_document(), before);
    assert_eq!(scales_120, BTreeMap::from([("DSI-1".to_owned(), 240)]));
}

#[test]
fn apps_stay_larger_where_the_output_config_cannot_take_the_scales() {
    let files = Files::new(json!({"version": 30, "apps": {"scale": 1.5}}), "");
    let mut scales_120 = BTreeMap::new();

    // No output config at all.
    let mut settings = files.settings();
    fold_apps_scale(&mut settings, &mut scales_120, [("DSI-1", 300)], None);
    assert_eq!(settings.apps_scale(), 1.5);

    // A declarative one deniald does not replace.
    let link = files.0.join("linked.conf");
    std::os::unix::fs::symlink(files.outputs(), &link).unwrap();
    fold_apps_scale(&mut settings, &mut scales_120, [("DSI-1", 300)], Some(&link));
    assert_eq!(settings.apps_scale(), 1.5);
    assert_eq!(files.settings_document()["apps"]["scale"], 1.5);
    assert_eq!(files.outputs_text(), "");
    assert!(scales_120.is_empty());
}
