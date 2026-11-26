import 'dart:async';

import 'package:denial_flutter_sdk/controls.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/bypass_charging.dart';
import '../state/phone_desk.dart';
import '../state/power_tiles.dart';
import '../widgets/connectivity/wifi_detail_surface.dart';
import 'desktop_dashboard_controls.dart';

/// Brightness slider and tablet quick-settings toggles (Wi-Fi, Do Not Disturb,
/// Stay awake, Bypass charging, Auto-rotate, Screen recording, Screen off,
/// Sleep) surfaced inside the desktop Control Center.
class DesktopQuickTogglesSection extends ConsumerWidget {
  const DesktopQuickTogglesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final output = ref.watch(
      sceneDisplayLayoutProvider(
        ShellPart.of(context),
      ).select((layout) => layout?.mainOutput),
    );
    final brightness = ref.watch(
      displayBrightnessProvider.select(
        (state) => state.levels[output?.monitorId] ?? 0.72,
      ),
    );
    final brightnessController = ref.read(displayBrightnessProvider.notifier);

    final network = ref.watch(networkConnectivityProvider);
    final networkController = ref.read(networkConnectivityProvider.notifier);
    final networkSnapshot = network.snapshot;
    final wifiOn =
        networkSnapshot.wirelessEnabled && networkSnapshot.wifiDeviceAvailable;
    final wifiEnabled =
        !network.initializing &&
        networkSnapshot.serviceAvailable &&
        networkSnapshot.wifiDeviceAvailable &&
        networkSnapshot.wirelessHardwareEnabled &&
        networkSnapshot.radioPermission != NetworkPermission.denied &&
        !network.radioChanging;

    final dnd = ref.watch(
      desktopNotificationsProvider.select((state) => state.doNotDisturb),
    );
    final settingsReady =
        ref.watch(shellSettingsSyncStatusProvider).phase ==
        ShellSettingsSyncPhase.ready;
    final stayAwake = ref.watch(
      shellSettingsProvider.select((settings) => settings.power.stayAwake),
    );
    final bypass = ref.watch(bypassChargingProvider);
    final rotationLock = ref.watch(rotationLockProvider);
    final recording = ref.watch(screenRecordingProvider);
    final powerTiles = ref.watch(powerTilesProvider);

    final tiles = <Widget>[
      _DesktopToggleTile(
        icon: wifiOn ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        title: l10n.commonWifi,
        subtitle: wifiOn ? l10n.commonOn : l10n.commonOff,
        active: wifiOn,
        enabled: wifiEnabled,
        busy: network.radioChanging,
        onTap: networkController.toggleWireless,
        onSecondaryTap: () {
          ref
              .read(shellPopupControllerProvider.notifier)
              .show(
                keyName: 'wifi-details',
                debugLabel: 'Wi-Fi details',
                builder: (_, handle) =>
                    WifiDetailSurface(onClose: handle.close),
              );
        },
      ),
      _DesktopToggleTile(
        icon: dnd
            ? Icons.notifications_off_rounded
            : Icons.notifications_rounded,
        title: l10n.quickSettingsSilent,
        subtitle: settingsReady
            ? (dnd ? l10n.commonOn : l10n.quickSettingsNormal)
            : l10n.commonLoading,
        active: dnd,
        enabled: settingsReady,
        onTap: ref
            .read(desktopNotificationsProvider.notifier)
            .toggleDoNotDisturb,
      ),
      _DesktopToggleTile(
        icon: Icons.coffee_rounded,
        title: l10n.quickSettingsStayAwake,
        subtitle: settingsReady
            ? (stayAwake ? l10n.commonOn : l10n.commonOff)
            : l10n.commonLoading,
        active: stayAwake,
        enabled: settingsReady,
        onTap: () => ref
            .read(shellSettingsProvider.notifier)
            .setStayAwake(!ref.read(shellSettingsProvider).power.stayAwake),
      ),
      if (bypass.available)
        _DesktopToggleTile(
          icon: Icons.power_rounded,
          title: l10n.quickSettingsBypassCharging,
          subtitle: bypass.failed
              ? l10n.commonUnavailable
              : (bypass.on ? l10n.commonOn : l10n.commonOff),
          active: bypass.on,
          enabled: !bypass.failed && !bypass.busy,
          busy: bypass.busy,
          onTap: () =>
              unawaited(ref.read(bypassChargingProvider.notifier).toggle()),
        ),
      if (rotationLock.supported)
        _DesktopToggleTile(
          icon: rotationLock.locked
              ? Icons.screen_lock_rotation_rounded
              : Icons.screen_rotation_rounded,
          title: l10n.quickSettingsAutoRotate,
          subtitle: rotationLock.error != null
              ? l10n.commonError
              : (rotationLock.locked ? l10n.commonOff : l10n.commonOn),
          active: !rotationLock.locked,
          enabled: !rotationLock.busy,
          busy: rotationLock.busy,
          onTap: () => ref.read(rotationLockProvider.notifier).toggle(),
        ),
      if (recording.available)
        _DesktopToggleTile(
          icon: recording.recording
              ? Icons.stop_circle_rounded
              : Icons.radio_button_checked_rounded,
          title: recording.recording
              ? l10n.quickSettingsRecording
              : l10n.quickSettingsScreenRecording,
          subtitle: recording.recording ? l10n.commonOn : l10n.commonOff,
          active: recording.recording,
          enabled: !recording.busy,
          busy: recording.busy,
          onTap: () => ref.read(screenRecordingProvider.notifier).toggle(),
        ),
      _DesktopToggleTile(
        icon: Icons.mobile_off_rounded,
        title: l10n.quickSettingsScreenOff,
        active: false,
        enabled: !powerTiles.screenOffPending,
        onTap: () =>
            unawaited(ref.read(powerTilesProvider.notifier).screenOff()),
      ),
      _DesktopToggleTile(
        icon: Icons.bedtime_rounded,
        title: l10n.quickSettingsSleep,
        active: false,
        enabled: !powerTiles.sleepPending,
        busy: powerTiles.sleepPending,
        onTap: () => unawaited(ref.read(powerTilesProvider.notifier).sleep()),
      ),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final first = tiles[i];
      final second = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 8),
            Expanded(child: second ?? const SizedBox.shrink()),
          ],
        ),
      );
      if (i + 2 < tiles.length) {
        rows.add(const SizedBox(height: 8));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (output != null) ...[
              RangeBar(
                icon: Icons.brightness_6_rounded,
                value: brightness,
                activeColor: ShellTheme.of(context).accent,
                inactiveColor: context.shellColors.brightnessTrack,
                onChanged: (value) =>
                    brightnessController.setLevel(output, value),
                onChangeEnd: (value) =>
                    brightnessController.commitLevel(output, value),
                height: 44,
              ),
              const SizedBox(height: 12),
            ],
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _DesktopToggleTile extends StatefulWidget {
  const _DesktopToggleTile({
    required this.icon,
    required this.title,
    required this.active,
    required this.enabled,
    required this.onTap,
    this.subtitle,
    this.busy = false,
    this.onSecondaryTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool active;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;

  @override
  State<_DesktopToggleTile> createState() => _DesktopToggleTileState();
}

class _DesktopToggleTileState extends State<_DesktopToggleTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    final colors = context.shellColors;
    final bg = widget.active
        ? accent.container
        : _hovered
        ? colors.surfaceContainerHighest
        : colors.surfaceContainerHigh;
    final fg = widget.enabled
        ? (widget.active ? accent.onContainer : colors.textPrimary)
        : colors.glyphInactive;
    final subFg = widget.enabled
        ? (widget.active
              ? accent.onContainer.withValues(alpha: 0.78)
              : colors.textSecondary)
        : colors.glyphInactive;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      toggled: widget.active,
      label: widget.title,
      child: MouseRegion(
        cursor: widget.busy
            ? ShellMouseCursors.working
            : widget.enabled
            ? ShellMouseCursors.link
            : ShellMouseCursors.normal,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled && !widget.busy ? widget.onTap : null,
          onSecondaryTap: widget.onSecondaryTap,
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Motion.standard,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: context.shellTheme.borderRadius(14),
              border: Border.all(
                color: widget.active
                    ? accent.primary.withValues(alpha: 0.35)
                    : colors.hairlineSoft,
              ),
            ),
            child: Row(
              children: [
                if (widget.busy)
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                else
                  Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.shellTheme.text.cardTitle.copyWith(
                          color: fg,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.shellTheme.text.cardTitle.copyWith(
                            color: subFg,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.onSecondaryTap != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onSecondaryTap,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: subFg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
