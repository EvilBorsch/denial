import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_color_scheme.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';

import '../launcher/window_application.dart';
import '../state/desktop_app_switcher.dart';
import '../state/reference_shell_controller.dart';

// Transitional chrome, like Super+Tab's: the same dark glass over any
// wallpaper and theme.
const _colors = ShellColorScheme.dark;

/// Alt+Tab's app switcher: a centred row of app icons on a glass panel over
/// a dimmed output, the selected app named under it and, while ` steps its
/// windows, their titles. It takes no input: deniald holds the keys.
///
/// Sized for the tablet's 12.1" panel at its shell scale (about 1357×960
/// logical points, as dense as a MacBook's), where ⌘Tab's proportions read
/// well: 88-point icons, 17-point names.
class DesktopAppSwitcherOverlay extends ConsumerStatefulWidget {
  const DesktopAppSwitcherOverlay({
    required this.switcher,
    required this.bounds,
    super.key,
  });

  final DesktopAppSwitcherState? switcher;

  /// The output the switcher shows on, in scene coordinates.
  final Rect bounds;

  @override
  ConsumerState<DesktopAppSwitcherOverlay> createState() =>
      _DesktopAppSwitcherOverlayState();
}

class _DesktopAppSwitcherOverlayState
    extends ConsumerState<DesktopAppSwitcherOverlay> {
  /// The session last shown, kept while it fades out.
  DesktopAppSwitcherState? _shown;

  @override
  Widget build(BuildContext context) {
    final switcher = widget.switcher;
    final visible = switcher?.phase == DesktopAppSwitcherPhase.shown;
    if (visible) {
      _shown = switcher;
    }
    // A quick Alt+Tab never shows; a shown session fades out as it was.
    final content = _shown;
    if (content == null || widget.bounds.isEmpty) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : visible
        ? Motion.appSwitcherOpen
        : Motion.appSwitcherClose;
    final curve = visible
        ? Motion.md3EmphasizedDecelerate
        : Motion.md3EmphasizedAccelerate;
    final windowsById = ref.watch(
      referenceShellProvider.select(
        (state) => state.desk.openAppWindowsByObjectId,
      ),
    );

    return Positioned.fromRect(
      rect: widget.bounds,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: duration,
              curve: curve,
              child: ColoredBox(
                color: _colors.overviewScrim.withValues(alpha: 0.32),
              ),
            ),
            Center(
              child: Semantics(
                container: true,
                label: context.l10n.appSwitcherLabel,
                child: AnimatedOpacity(
                  opacity: visible ? 1.0 : 0.0,
                  duration: duration,
                  curve: curve,
                  onEnd: () {
                    if (!visible && mounted) {
                      setState(() => _shown = null);
                    }
                  },
                  child: AnimatedScale(
                    scale: visible ? 1.0 : 0.96,
                    duration: duration,
                    curve: curve,
                    child: _AppSwitcherPanel(
                      switcher: content,
                      windowsById: windowsById,
                      maxWidth: widget.bounds.width - 64.0,
                      reduceMotion: reduceMotion,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppSwitcherPanel extends StatelessWidget {
  const _AppSwitcherPanel({
    required this.switcher,
    required this.windowsById,
    required this.maxWidth,
    required this.reduceMotion,
  });

  static const double _iconSize = 88.0;
  static const double _cellExtent = 112.0;
  static const double _minimumCellExtent = 56.0;
  static const double _padding = 18.0;

  final DesktopAppSwitcherState switcher;
  final Map<int, DenialWindow> windowsById;
  final double maxWidth;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme.copyWith(colors: _colors);
    final apps = switcher.apps;
    // Many apps shrink the row to the output, as ⌘Tab does.
    final cell = (((maxWidth - _padding * 2) / math.max(1, apps.length)))
        .clamp(_minimumCellExtent, _cellExtent)
        .toDouble();
    final icon = cell * _iconSize / _cellExtent;
    final rowWidth = cell * apps.length;
    final selectDuration = reduceMotion
        ? Duration.zero
        : Motion.appSwitcherSelect;
    final radius = BorderRadius.circular(theme.panelRadius);
    // The name stands under the selected icon, kept on the panel.
    final labelWidth = math.max(rowWidth, 320.0);
    final nameCenter =
        (switcher.selectedApp + 0.5) * cell + (labelWidth - rowWidth) / 2.0;

    return ShellBackdropBlur(
      blur: theme.effectivePanelOpacity < 1.0,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(_colors.panelBackground),
          borderRadius: radius,
          border: Border.all(color: _colors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_padding, _padding, _padding, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: rowWidth,
                height: cell,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: selectDuration,
                      curve: Motion.standard,
                      left: switcher.selectedApp * cell,
                      top: 0,
                      width: cell,
                      height: cell,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _colors.textPrimary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(cell * 0.22),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final app in apps)
                          SizedBox.square(
                            dimension: cell,
                            child: Center(
                              child: SizedBox.square(
                                dimension: icon,
                                child: _AppIcon(app: app),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: labelWidth,
                child: AnimatedAlign(
                  duration: selectDuration,
                  curve: Motion.standard,
                  alignment: Alignment(nameCenter / labelWidth * 2.0 - 1.0, 0),
                  child: _SelectedAppName(
                    app: switcher.selected,
                    window: windowsById[switcher.selected.windowIds.first],
                  ),
                ),
              ),
              AnimatedSize(
                duration: selectDuration,
                curve: Motion.standard,
                alignment: Alignment.topCenter,
                child: switcher.selectedWindow == null
                    ? const SizedBox(width: 0, height: 0)
                    : _WindowList(
                        app: switcher.selected,
                        selected: switcher.selectedWindow!,
                        windowsById: windowsById,
                        width: math.min(math.max(rowWidth, 420.0), 640.0),
                        selectDuration: selectDuration,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends ConsumerWidget {
  const _AppIcon({required this.app});

  final DesktopAppSwitcherApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(app.appId));
    final icon = application.icon;
    if (icon != null) {
      return FittedBox(child: Icon(icon, color: _colors.textPrimary));
    }
    return AppIconImage(iconPath: application.iconPath);
  }
}

class _SelectedAppName extends ConsumerWidget {
  const _SelectedAppName({required this.app, required this.window});

  final DesktopAppSwitcherApp app;
  final DenialWindow? window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(app.appId));
    final name =
        application.name ??
        (window == null ? '' : localizedWindowTitle(context, window!));
    final count = app.windowIds.length;
    return Semantics(
      liveRegion: true,
      label: context.l10n.windowSwitcherSelected(name),
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: name),
              if (count > 1)
                TextSpan(
                  text: '  ${context.l10n.screensOverviewStackCount(count)}',
                  style: TextStyle(
                    color: _colors.textSecondary,
                    fontWeight: FontWeight.w400,
                    fontSize: 15,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// The selected app's windows while ` steps them: their titles, the chosen
/// one highlighted. A long list scrolls to keep the choice in view.
class _WindowList extends StatelessWidget {
  const _WindowList({
    required this.app,
    required this.selected,
    required this.windowsById,
    required this.width,
    required this.selectDuration,
  });

  static const double _rowHeight = 40.0;
  static const int _visibleRows = 7;

  final DesktopAppSwitcherApp app;
  final int selected;
  final Map<int, DenialWindow> windowsById;
  final double width;
  final Duration selectDuration;

  @override
  Widget build(BuildContext context) {
    final count = app.windowIds.length;
    final shown = math.min(count, _visibleRows);
    // The rows shown: a window around the selection.
    final first = (selected - shown ~/ 2).clamp(0, count - shown);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: width,
        height: shown * _rowHeight,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: selectDuration,
              curve: Motion.standard,
              left: 0,
              right: 0,
              top: (selected - first) * _rowHeight,
              height: _rowHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _colors.textPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Column(
              children: [
                for (var index = first; index < first + shown; index += 1)
                  SizedBox(
                    height: _rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _title(context, app.windowIds[index]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: index == selected
                                ? _colors.textPrimary
                                : _colors.textSecondary,
                            fontSize: 16,
                            fontWeight: index == selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _title(BuildContext context, int objectId) {
    final window = windowsById[objectId];
    return window == null ? '' : localizedWindowTitle(context, window);
  }
}
