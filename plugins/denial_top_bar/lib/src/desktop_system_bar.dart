import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_sdk/system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'desktop_system_bar_components.dart';
part 'desktop_system_bar_media.dart';
part 'desktop_workspace_indicator.dart';

/// The desktop system bar. Its strip is reserved from the window work area,
/// so windows maximize beside it while true fullscreen covers it.
///
/// The strip itself paints nothing: modules float as borderless pill cards
/// over the bare wallpaper, and every card follows the wallpaper's extracted
/// accent. Cards cluster at the trailing edge of the strip and spring in one
/// after another when the bar mounts.
const systemBarBatteryButtonKey = ValueKey<String>('system-bar-battery-button');
const systemBarClockButtonKey = ValueKey<String>('system-bar-clock-button');

/// The control-center icon beside the clock: like the clock, it opens and
/// closes the dashboard, the desktop's control center.
const systemBarControlCenterButtonKey = ValueKey<String>(
  'system-bar-control-center-button',
);

class _DesktopSystemBarContent extends ConsumerWidget {
  const _DesktopSystemBarContent({
    required this.monitorId,
    required this.side,
    required this.stayAwake,
    required this.onOpenPowerSettings,
    required this.onToggleDashboard,
  });

  static const double _edgePadding = 8.0;
  static const double _cardMargin = 5.0;
  static const double _cardGap = 8.0;

  final int monitorId;
  final PanelEdge side;
  final bool stayAwake;
  final VoidCallback onOpenPowerSettings;
  final VoidCallback onToggleDashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = WallpaperAccent(
      ref.watch(context.presentationServices.accent),
    );
    final batteryVisible = ref.watch(
      context.telemetryServices.battery.select(
        (battery) => battery.capacity != null,
      ),
    );
    final cpuVisible = ref.watch(
      context.telemetryServices.cpu.select((cpu) => cpu.current != null),
    );
    final gpuCount = ref.watch(
      context.telemetryServices.gpus.select((gpus) => gpus.length),
    );
    final mediaVisible = ref.watch(
      context.mediaServices.media.select(
        (media) => media.value?.available ?? false,
      ),
    );
    final trayVisible = ref.watch(context.trayServices.trayVisible);
    final horizontal = side.isHorizontal;
    final modules = Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (trayVisible)
          Expanded(
            child: Align(
              alignment: horizontal
                  ? Alignment.centerLeft
                  : Alignment.topCenter,
              child: SingleChildScrollView(
                scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
                child: _SystemBarEntrance(
                  key: const ValueKey('system-bar-tray'),
                  index: 0,
                  horizontal: horizontal,
                  child: _SystemBarCard(
                    accent: accent,
                    child: _SystemTrayStatusModule(horizontal: horizontal),
                  ),
                ),
              ),
            ),
          ),
        if (mediaVisible)
          _SystemBarEntrance(
            key: const ValueKey('system-bar-media'),
            index:
                (cpuVisible ? 1 : 0) +
                gpuCount +
                (batteryVisible ? 1 : 0) +
                (stayAwake ? 1 : 0) +
                1,
            horizontal: horizontal,
            child: Padding(
              padding: horizontal
                  ? const EdgeInsets.only(right: _cardGap)
                  : const EdgeInsets.only(bottom: _cardGap),
              child: _SystemBarCard(
                accent: accent,
                child: _MediaStatusProviderModule(accent: accent, side: side),
              ),
            ),
          ),
        if (stayAwake)
          _SystemBarEntrance(
            key: const ValueKey('system-bar-stay-awake'),
            index:
                (cpuVisible ? 1 : 0) + gpuCount + (batteryVisible ? 1 : 0) + 1,
            horizontal: horizontal,
            child: Padding(
              padding: horizontal
                  ? const EdgeInsets.only(right: _cardGap)
                  : const EdgeInsets.only(bottom: _cardGap),
              child: _StayAwakeCard(accent: accent, horizontal: horizontal),
            ),
          ),
        if (batteryVisible)
          _SystemBarEntrance(
            key: const ValueKey('system-bar-battery'),
            index: (cpuVisible ? 1 : 0) + gpuCount + 1,
            horizontal: horizontal,
            child: Padding(
              padding: horizontal
                  ? const EdgeInsets.only(right: _cardGap)
                  : const EdgeInsets.only(bottom: _cardGap),
              child: _BatteryStatusCard(
                accent: accent,
                onPressed: onOpenPowerSettings,
              ),
            ),
          ),
        if (gpuCount > 0)
          _GpuStatusCards(
            accent: accent,
            horizontal: horizontal,
            cpuVisible: cpuVisible,
          ),
        if (cpuVisible) _CpuStatusCard(accent: accent, horizontal: horizontal),
        // As on macOS, the control center's icon sits just before the clock.
        _SystemBarEntrance(
          key: const ValueKey('system-bar-control-center'),
          index: 0,
          horizontal: horizontal,
          child: Padding(
            padding: horizontal
                ? const EdgeInsets.only(right: _cardGap)
                : const EdgeInsets.only(bottom: _cardGap),
            child: _ControlCenterButton(
              accent: accent,
              horizontal: horizontal,
              onPressed: onToggleDashboard,
            ),
          ),
        ),
        _SystemBarEntrance(
          key: const ValueKey('system-bar-clock'),
          index: 0,
          horizontal: horizontal,
          child: _SystemBarButton(
            key: systemBarClockButtonKey,
            accent: accent,
            label: context.pluginStrings.openDashboard,
            onPressed: onToggleDashboard,
            child: _ClockStatusModule(accent: accent),
          ),
        ),
      ],
    );
    final workspacesEnabled = ref.watch(
      context.workspaceServices.workspacesEnabled,
    );
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(
              horizontal: _edgePadding,
              vertical: _cardMargin,
            )
          : const EdgeInsets.symmetric(
              horizontal: _cardMargin,
              vertical: _edgePadding,
            ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          modules,
          if (workspacesEnabled)
            Center(
              child: DesktopSystemBarIndicatorSlot(
                horizontal: horizontal,
                child: _WorkspaceIndicator(
                  monitorId: monitorId,
                  horizontal: horizontal,
                  accent: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shrink-wraps the centered workspace pill along the bar's main axis.
///
/// System-bar cards intentionally fill the cross axis. Without this flex
/// boundary, the expanding [Stack] also gives the centered card a bounded main
/// axis, causing its backdrop-filter clip to cover the complete bar strip.
class DesktopSystemBarIndicatorSlot extends StatelessWidget {
  const DesktopSystemBarIndicatorSlot({
    required this.horizontal,
    required this.child,
    super.key,
  });

  final bool horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[child],
    );
  }
}

/// Keeps changes to tray contents out of the complete system-bar build.
class _SystemTrayStatusModule extends ConsumerWidget {
  const _SystemTrayStatusModule({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return context.trayServices.buildSystemTray(
      context,
      horizontal: horizontal,
    );
  }
}

/// Default bar presentation, supplied entirely by the plugin package.
class DesktopSystemBar extends StatelessWidget {
  const DesktopSystemBar({
    required this.monitorId,
    required this.side,
    required this.services,
    this.stayAwake = false,
    super.key,
  });
  final int monitorId;
  final PanelEdge side;
  final ShellServices services;

  /// Whether Stay awake keeps the idle timeout from suspending the system
  /// (`power.stayAwake`): the bar shows a mark while it is on.
  final bool stayAwake;

  @override
  Widget build(BuildContext context) => ShellServicesScope(
    services: services,
    child: _DesktopSystemBarContent(
      monitorId: monitorId,
      side: side,
      stayAwake: stayAwake,
      onOpenPowerSettings: services.openPowerSettings,
      onToggleDashboard: services.toggleDashboard,
    ),
  );
}

/// The control-center icon: two toggle switches, as macOS's. Lit while the
/// dashboard is open. A click opens the dashboard; while it is open, the
/// shell's barrier over the bar takes the next click and closes it.
class _ControlCenterButton extends ConsumerWidget {
  const _ControlCenterButton({
    required this.accent,
    required this.horizontal,
    required this.onPressed,
  });

  final WallpaperAccent accent;
  final bool horizontal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(context.desktopServices.dashboardOpen);
    return _SystemBarButton(
      key: systemBarControlCenterButtonKey,
      accent: accent,
      label: context.pluginStrings.controlCenter,
      onPressed: onPressed,
      active: open,
      padding: horizontal
          ? const EdgeInsets.symmetric(horizontal: 11)
          : const EdgeInsets.symmetric(vertical: 11),
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(18, 15),
          painter: _ControlCenterGlyphPainter(
            color: context.shellColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// The mark shown while Stay awake is on: a cup, like the phone status
/// bar's, on a card of its own beside the battery.
class _StayAwakeCard extends StatelessWidget {
  const _StayAwakeCard({required this.accent, required this.horizontal});

  final WallpaperAccent accent;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => _SystemBarCard(
    accent: accent,
    padding: horizontal
        ? const EdgeInsets.symmetric(horizontal: 10)
        : const EdgeInsets.symmetric(vertical: 10),
    child: Icon(
      Icons.coffee_rounded,
      size: 16,
      color: context.shellColors.textPrimary,
      semanticLabel: context.pluginStrings.stayAwakeOn,
    ),
  );
}

extension _PluginContext on BuildContext {
  ShellTelemetryServices get telemetryServices => ShellServicesScope.of(this);
  ShellMediaServices get mediaServices => ShellServicesScope.of(this);
  ShellWorkspaceServices get workspaceServices => ShellServicesScope.of(this);
  ShellDesktopServices get desktopServices => ShellServicesScope.of(this);
  ShellPresentationServices get presentationServices =>
      ShellServicesScope.of(this);
  ShellTrayServices get trayServices => ShellServicesScope.of(this);
  ShellStrings get pluginStrings => presentationServices.strings(this);
}
