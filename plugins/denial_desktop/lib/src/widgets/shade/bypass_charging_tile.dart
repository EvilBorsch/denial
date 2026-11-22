import 'dart:async';

import 'package:denial_flutter_sdk/localization.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bypass_charging.dart';
import 'quick_settings_tiles.dart';

/// The Bypass charging tile. While it is lit the battery's charging is held
/// off and a connected charger powers the system directly
/// ([BypassChargingController]). The kernel holds the choice; the tile shows
/// what the battery reports.
///
/// Null, so the shade shows no tile, unless a battery offers bypass charging
/// and this user may switch it. A switch the kernel refuses shows the tile
/// unavailable until the shade is next opened.
QuickTile? bypassChargingQuickTile(WidgetRef ref, AppLocalizations l10n) {
  final bypass = ref.watch(bypassChargingProvider);
  if (!bypass.available) return null;
  return QuickTile(
    icon: Icons.power_rounded,
    title: l10n.quickSettingsBypassCharging,
    subtitle: bypass.failed
        ? l10n.commonUnavailable
        : (bypass.on ? l10n.commonOn : l10n.commonOff),
    active: bypass.on,
    enabled: !bypass.failed && !bypass.busy,
    busy: bypass.busy,
    onTap: () => unawaited(ref.read(bypassChargingProvider.notifier).toggle()),
  );
}
