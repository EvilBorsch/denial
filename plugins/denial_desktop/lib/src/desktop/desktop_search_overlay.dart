import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../search/shell_search_backend.dart';
import '../search/shell_search_view.dart';
import '../t3_code/t3_code_controller.dart';
import 'desktop_shell_search.dart';

/// The one search over the desktop: a bare Super, Super+S, Alt+F in the Mac
/// preset and four fingers up all open it (Spotlight and Launchpad in one).
///
/// With nothing typed it shows the apps started last and every app, a
/// scrollable grid. Typing finds apps first, then open windows. Enter starts
/// the best app, or switches to it when it runs, or goes to the window; the
/// arrows choose another. Esc clears what was typed, then closes, as does a
/// click outside. It stays built offstage while closed, from the shell's
/// start, so it opens with its grid laid out and its icons drawn.
class DesktopSearchOverlay extends ConsumerStatefulWidget {
  const DesktopSearchOverlay({
    super.key,
    required this.viewSize,
    required this.displayLayout,
    required this.onActivateWindow,
    required this.onLaunchApplication,
    required this.onLaunchLocalApplication,
    this.keyboardTop = double.infinity,
    this.aiEnabled = true,
  });

  final Size viewSize;

  /// The top of the on-screen keyboard in the view, as it slides.
  final double keyboardTop;
  final bool aiEnabled;
  final DisplayLayout? displayLayout;
  final ValueChanged<DenialWindow> onActivateWindow;
  final ValueChanged<DesktopApp> onLaunchApplication;
  final ValueChanged<LocalFlutterApplication> onLaunchLocalApplication;

  /// Where the search's panel sits on an output's [workArea]: centred, wide
  /// enough for a grid of seven or eight apps, a little above the middle.
  /// Over the on-screen keyboard, whose top is at [keyboardTop], it ends a
  /// margin above it, so the keyboard covers none of its results.
  static Rect panelBounds(
    Rect workArea, {
    double keyboardTop = double.infinity,
  }) {
    final width = math.min(880.0, math.max(0.0, workArea.width - 96.0));
    final height = math.max(0.0, workArea.height * 0.8);
    final top = workArea.top + math.max(0.0, workArea.height - height) * 0.45;
    final bottom = math.min(top + height, keyboardTop - _keyboardMargin);
    return Rect.fromLTRB(
      workArea.center.dx - width / 2.0,
      top,
      workArea.center.dx + width / 2.0,
      math.max(top, bottom),
    );
  }

  static const double _keyboardMargin = 16;

  @override
  ConsumerState<DesktopSearchOverlay> createState() =>
      _DesktopSearchOverlayState();
}

class _DesktopSearchOverlayState extends ConsumerState<DesktopSearchOverlay>
    with SingleTickerProviderStateMixin<DesktopSearchOverlay> {
  late final ShellSearchSession _session =
      ShellSearchSession(debugLabel: 'desktop-search')
        ..onDismiss = _close
        ..onActivate = _activate
        ..onAskAi = _askAi;
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: Motion.desktopPanelOpen,
    reverseDuration: Motion.desktopPanelFadeClose,
  )..addStatusListener(_presenceChanged);
  late final Animation<double> _scale = Tween<double>(begin: 0.96, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _presence,
          curve: Motion.md3EmphasizedDecelerate,
          reverseCurve: Motion.md3EmphasizedAccelerate,
        ),
      );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _presence,
    curve: Motion.standard,
  );

  /// The monitor the search is shown on; kept while it is closed, where it
  /// waits offstage.
  int? _monitorId;
  bool _shown = false;

  @override
  void dispose() {
    _presence.dispose();
    _session.dispose();
    super.dispose();
  }

  void _presenceChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      // Closed, it goes offstage with an empty query: the grid it opens
      // with next time is ready.
      _session.start(focusField: false);
      setState(() => _shown = false);
    }
  }

  void _show(int monitorId) {
    _monitorId = monitorId;
    _shown = true;
    _session.start();
    if (MediaQuery.disableAnimationsOf(context)) {
      _presence.value = 1.0;
    } else {
      _presence.forward();
    }
  }

  void _hide() {
    _session.focus.unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _presence.value = 0.0;
    } else {
      _presence.reverse();
    }
  }

  void _close() => ref.read(desktopSearchOverlayProvider.notifier).close();

  void _askAi(String prompt) {
    _close();
    unawaited(
      ref.read(t3CodeControllerProvider.notifier).sendTextPrompt(prompt),
    );
  }

  /// An app starts, or comes to the front when it runs; a window comes to
  /// the front.
  void _activate(ShellSearchTarget target, Rect _) {
    switch (target) {
      case ShellSearchWindowTarget(:final window):
        _close();
        widget.onActivateWindow(window.window);
      case ShellSearchAppTarget(:final app):
        final running = ref
            .read(shellSearchBackendProvider)
            .openWindowOf(app, ref.read(shellSearchDeskWindowsProvider));
        _close();
        if (running != null) {
          ref.read(applicationRecentsProvider.notifier).record(app.id);
          widget.onActivateWindow(running);
        } else if (app.desktopApp case final desktop?) {
          widget.onLaunchApplication(desktop);
        } else if (app.localApp case final local?) {
          widget.onLaunchLocalApplication(local);
        }
    }
  }

  Rect _workArea(int monitorId) {
    final canvas = Offset.zero & widget.viewSize;
    final layout = widget.displayLayout;
    if (layout == null) {
      return canvas;
    }
    DisplayOutput? output;
    for (final candidate in layout.outputs) {
      if (candidate.monitorId == monitorId) {
        output = candidate;
      }
    }
    output ??= layout.mainOutput;
    if (output == null) {
      return canvas;
    }
    final area = layout.workAreaOf(output).intersect(canvas);
    return area.isEmpty ? canvas : area;
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(desktopSearchOverlayProvider);
    ref.listen<int?>(desktopSearchOverlayProvider, (previous, next) {
      if (next != null && (previous == null || !_shown)) {
        setState(() => _show(next));
      } else if (next == null && previous != null) {
        _hide();
      }
    });
    // Built offstage from the start, on the main output until it opens: its
    // first opening draws a grid that is already laid out, with its icons
    // decoded.
    final monitorId = _monitorId ??=
        widget.displayLayout?.mainOutput?.monitorId;
    if (monitorId == null) {
      return const SizedBox.shrink();
    }
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final panel = DesktopSearchOverlay.panelBounds(
      _workArea(monitorId),
      keyboardTop: widget.keyboardTop,
    );
    final radius = BorderRadius.circular(theme.panelRadius);
    final scrim = colors.overviewScrim;
    final active = open != null;
    return Offstage(
      offstage: !_shown,
      child: TickerMode(
        enabled: _shown,
        child: ShellInputRegion(
          debugLabel: 'Desktop search',
          active: active,
          pointerPolicy: ShellPointerPolicy.fullScene,
          keyboardPolicy: ShellKeyboardPolicy.capture,
          compositorPolicy: ShellCompositorPolicy.exclusive,
          child: IgnorePointer(
            ignoring: !active,
            child: ExcludeSemantics(
              excluding: !active,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: FadeTransition(
                        opacity: _fade,
                        child: ColoredBox(
                          color: scrim.withValues(alpha: scrim.a * 0.4),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: panel,
                    // The panel is drawn once and then only faded and
                    // scaled as one composited layer.
                    child: RepaintBoundary(
                      child: FadeTransition(
                        opacity: _fade,
                        child: ScaleTransition(
                          scale: _scale,
                          alignment: Alignment.topCenter,
                          child: ShellBackdropBlur(
                            blur: theme.effectivePanelOpacity < 1.0,
                            borderRadius: radius,
                            blendMode: BlendMode.srcOver,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.panelColor(colors.panelBackground),
                                borderRadius: radius,
                                border: Border.all(color: colors.hairline),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ListenableBuilder(
                                      listenable: _session,
                                      builder: (context, _) {
                                        return ShellSearchField(
                                          style: ShellSearchStyle.desktop,
                                          controller: _session.query,
                                          focusNode: _session.focus,
                                          hint: context.l10n.homeSearchHint,
                                          onSubmitted: _session.submit,
                                          onClear: _session.clear,
                                          aiMode: _session.aiMode,
                                          onAskAi: widget.aiEnabled
                                              ? _session.toggleAiMode
                                              : null,
                                        );
                                      },
                                    ),
                                    Expanded(
                                      child: ShellSearchResults(
                                        session: _session,
                                        style: ShellSearchStyle.desktop,
                                        windows: ShellSearchWindows.desk,
                                        active: active,
                                        onLaunchApp: (app, rect) => _activate(
                                          ShellSearchAppTarget(app),
                                          rect,
                                        ),
                                        onOpenWindow: (window, rect) =>
                                            _activate(
                                              ShellSearchWindowTarget(window),
                                              rect,
                                            ),
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          bottom: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
