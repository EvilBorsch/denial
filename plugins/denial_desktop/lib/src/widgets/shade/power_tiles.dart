import 'dart:async';

import 'package:denial_flutter_sdk/localization.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/power_tiles.dart';
import 'quick_settings_tiles.dart';

/// The Screen off tile: the shade closes and the screen goes dark as a short
/// press of the power button turns it off ([PowerTilesController.screenOff]).
/// The session locks as for the button, except under Stay awake.
QuickTile screenOffQuickTile(WidgetRef ref, AppLocalizations l10n) {
  final pending = ref.watch(
    powerTilesProvider.select((tiles) => tiles.screenOffPending),
  );
  return QuickTile(
    icon: Icons.mobile_off_rounded,
    title: l10n.quickSettingsScreenOff,
    active: false,
    enabled: !pending,
    onTap: () => unawaited(ref.read(powerTilesProvider.notifier).screenOff()),
  );
}

/// The Sleep tile: the system suspends now, even under Stay awake
/// ([PowerTilesController.sleep]). It waits while logind is asked; a refusal
/// opens the power and session controls, which say why.
QuickTile sleepQuickTile(WidgetRef ref, AppLocalizations l10n) {
  final pending = ref.watch(
    powerTilesProvider.select((tiles) => tiles.sleepPending),
  );
  return QuickTile(
    icon: Icons.bedtime_rounded,
    title: l10n.quickSettingsSleep,
    active: false,
    enabled: !pending,
    busy: pending,
    onTap: () => unawaited(ref.read(powerTilesProvider.notifier).sleep()),
  );
}
