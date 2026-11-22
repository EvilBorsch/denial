import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quick_settings_tiles.dart';

/// The Stay awake tile. While it is lit the idle timeout does not suspend
/// the system ([ShellPowerSettings.stayAwake]); the screen still goes dark
/// and locks, and closing the lid still suspends. Its state is the persisted
/// setting, so it can be switched off here at any time and it outlives a
/// restart of the shell.
///
/// Until the settings document has loaded the tile cannot tell on from off
/// and cannot be switched.
QuickTile stayAwakeQuickTile(WidgetRef ref, AppLocalizations l10n) {
  final stayAwake = ref.watch(
    shellSettingsProvider.select((settings) => settings.power.stayAwake),
  );
  final loaded =
      ref.watch(shellSettingsSyncStatusProvider).phase ==
      ShellSettingsSyncPhase.ready;
  return QuickTile(
    icon: Icons.coffee_rounded,
    title: l10n.quickSettingsStayAwake,
    subtitle: loaded
        ? (stayAwake ? l10n.commonOn : l10n.commonOff)
        : l10n.commonLoading,
    active: stayAwake,
    enabled: loaded,
    onTap: () => ref
        .read(shellSettingsProvider.notifier)
        .setStayAwake(!ref.read(shellSettingsProvider).power.stayAwake),
  );
}
