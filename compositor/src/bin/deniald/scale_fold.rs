//! One scale per display. Denial's `apps.scale` drew apps larger than the
//! shell; Settings now offers one scale per display for the shell and every
//! app together. When deniald starts with an apps scale above 1, it folds it
//! into the scale of each display it knows, connected or remembered in the
//! output config, so apps keep the size they had and the shell joins them,
//! then drops `apps.scale`.
//!
//! The output config takes explicit scale lines and the settings document
//! loses a key every older deniald defaults to 1, so a rollback reads both
//! files and draws the same sizes. Once `apps.scale` is gone the fold does
//! nothing: it runs once. Without an output config it could rewrite, the apps
//! scale stays and keeps drawing apps larger.

use std::collections::BTreeMap;
use std::path::Path;

use denial_core::topology::SCALE_BASE;
use tracing::{info, warn};

use super::options;
use super::settings::SettingsManager;

/// The range the output config takes for a scale, in 120ths.
const MIN_SCALE_120: u32 = SCALE_BASE / 4;
const MAX_SCALE_120: u32 = SCALE_BASE * 8;

/// Folds the apps scale into the displays' scales, on disk and in
/// `scales_120`, the configured ones in 120ths. `connected` names each
/// connected output with the scale it has when the configuration names none.
///
/// Both files change, or neither: the output config is written aside, the
/// settings saved, and only then is the output config put in place; if that
/// last step fails the apps scale is saved back.
pub(super) fn fold_apps_scale<'a>(
    settings: &mut SettingsManager,
    scales_120: &mut BTreeMap<String, u32>,
    connected: impl IntoIterator<Item = (&'a str, u32)>,
    output_config: Option<&Path>,
) {
    let apps_scale = settings.apps_scale();
    if apps_scale == 1.0 {
        return;
    }
    let Some(path) = output_config else {
        warn!(
            apps_scale,
            "no output config to fold the apps scale into; apps stay larger than the shell"
        );
        return;
    };
    // Every output the configuration remembers, and every connected one at
    // the scale it shows now.
    let mut current = scales_120.clone();
    for (name, default_scale_120) in connected {
        current.entry(name.to_owned()).or_insert(default_scale_120);
    }
    let folded = current
        .into_iter()
        .map(|(name, scale_120)| {
            let scale_120 = (f64::from(scale_120) * apps_scale).round();
            let scale_120 = scale_120.clamp(f64::from(MIN_SCALE_120), f64::from(MAX_SCALE_120));
            (name, scale_120 as u32)
        })
        .collect::<BTreeMap<_, _>>();
    let prepared = match options::prepare_output_scales_persistence(path, &folded) {
        Ok(prepared) => prepared,
        Err(error) => {
            warn!(%error, apps_scale, "could not fold the apps scale into the display scales");
            return;
        }
    };
    if let Err(error) = settings.set_apps_scale(None) {
        warn!(%error, apps_scale, "could not drop the folded apps scale from the settings");
        return;
    }
    if let Err(error) = prepared.commit() {
        warn!(%error, apps_scale, "could not save the folded display scales");
        if let Err(error) = settings.set_apps_scale(Some(apps_scale)) {
            warn!(%error, apps_scale, "could not save the apps scale back");
        }
        return;
    }
    info!(
        apps_scale,
        scales = ?folded
            .iter()
            .map(|(name, scale_120)| (name.as_str(), f64::from(*scale_120) / f64::from(SCALE_BASE)))
            .collect::<Vec<_>>(),
        "folded the apps scale into the display scales"
    );
    scales_120.extend(folded);
}

#[cfg(test)]
#[path = "scale_fold/tests.rs"]
mod tests;
