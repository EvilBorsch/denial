import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/shell_plugin_services.dart' show DesktopApplicationIcon;
import '../search/shell_search_backend.dart';
import '../search/shell_search_view.dart';
import 'desktop_overview_layout.dart';
import 'desktop_overview_motion.dart';
import 'desktop_screens_overview_layout.dart';
import 'desktop_workspace.dart';
import 'eb20o_diag.dart';

/// The overview of the full-screen apps layout as the desktop's hub: a
/// search field over the screen cards, its results, and the screen cards
/// and windows it does not find dimmed.
abstract final class DesktopOverviewHubMetrics {
  /// The band above the cards that holds the search field (in the screens
  /// overview) or the app's name (in the app windows).
  static const double band = 72.0;

  /// The cards' and windows' area of an overview over [bounds].
  static Rect contentBounds(Rect bounds) => bounds.height <= band * 2
      ? bounds
      : Rect.fromLTRB(
          bounds.left,
          bounds.top + band,
          bounds.right,
          bounds.bottom,
        );

  /// The band of an overview whose content lies in [contentBounds].
  static Rect bandOf(Rect contentBounds) => Rect.fromLTRB(
    contentBounds.left,
    contentBounds.top - band,
    contentBounds.right,
    contentBounds.top,
  );

  /// The search field's widest.
  static const double fieldMaxWidth = 600.0;

  /// The search field, centred in the band.
  static Rect searchFieldOf(Rect contentBounds) {
    final band = bandOf(contentBounds);
    final width = math.min(fieldMaxWidth, math.max(0.0, band.width - 48.0));
    return Rect.fromCenter(
      center: band.center + const Offset(0.0, 6.0),
      width: width,
      height: ShellSearchMetrics.desktop.fieldHeight,
    );
  }

  /// How much of a card's surroundings a dimmed card covers: the card and
  /// its label above it.
  static Rect cardVeil(Rect card) => Rect.fromLTRB(
    card.left,
    card.top - DesktopScreensOverviewLayout.labelExtent,
    card.right,
    card.bottom,
  );
}

/// Whether [overview] is the hub: the screens overview of the full-screen
/// apps layout.
bool desktopOverviewIsHub(DesktopOverviewState? overview) =>
    overview?.workspaces?.screens != null;

/// Whether [overview] dims and blurs the desktop behind it: the hub and the
/// app windows.
bool desktopOverviewHasBackdrop(DesktopOverviewState? overview) =>
    desktopOverviewIsHub(overview) || overview?.appWindows != null;

/// Keeps the last overview of a kind while the overview's motion closes it,
/// so its chrome can leave with the windows.
mixin _RetainedOverview<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  DesktopOverviewState? _retained;
  DesktopOverviewMotion? _motion;

  bool keeps(DesktopOverviewState? overview);

  /// The overview to draw: the open one, or the one closing.
  DesktopOverviewState? retainOverview(DesktopOverviewState? overview) {
    final motion = ref.watch(desktopOverviewMotionProvider);
    if (!identical(motion, _motion)) {
      _motion?.removeListener(_motionChanged);
      motion.addListener(_motionChanged);
      _motion = motion;
    }
    if (keeps(overview)) {
      _retained = overview;
    } else if (overview != null || motion.value <= 0.0) {
      _retained = null;
    }
    return _retained;
  }

  void _motionChanged() {
    if (_retained != null &&
        !keeps(ref.read(desktopWorkspaceProvider).overview) &&
        (_motion?.value ?? 0.0) <= 0.0 &&
        mounted) {
      setState(() => _retained = null);
    }
  }

  @override
  void dispose() {
    _motion?.removeListener(_motionChanged);
    super.dispose();
  }
}

/// The desktop behind the hub and the app windows, dimmed and blurred as
/// far as the overview is open.
class DesktopOverviewBackdrop extends ConsumerStatefulWidget {
  const DesktopOverviewBackdrop({super.key});

  @override
  ConsumerState<DesktopOverviewBackdrop> createState() =>
      _DesktopOverviewBackdropState();
}

class _DesktopOverviewBackdropState
    extends ConsumerState<DesktopOverviewBackdrop>
    with _RetainedOverview<DesktopOverviewBackdrop> {
  @override
  bool keeps(DesktopOverviewState? overview) =>
      desktopOverviewHasBackdrop(overview);

  @override
  Widget build(BuildContext context) {
    final overview = retainOverview(
      ref.watch(desktopWorkspaceProvider.select((state) => state.overview)),
    );
    if (overview == null) {
      return const SizedBox.shrink();
    }
    final motion = ref.watch(desktopOverviewMotionProvider).presence;
    final scrim = context.shellColors.overviewScrim;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: overview.backgroundBounds,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ShellBackdropBlur(
                // The blurred desktop fades in over the sharp one; the blur
                // itself does not change per frame.
                opacity: eb20oDiag().contains('nofade') ? null : motion,
                blendMode: BlendMode.srcOver,
                child: ColoredBox(
                  color: scrim.withValues(alpha: math.min(1.0, scrim.a * 0.8)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The hub's chrome over the overview's windows: the search field, its
/// results and the dimming of what it does not find; and the app windows'
/// name and titles.
///
/// The overview searches only what is open: the apps that run and their
/// windows ([ShellSearchScope.openWindows]). Starting apps is the one
/// search's job (Super, Super+S, Alt+F, four fingers up).
class DesktopOverviewHub extends ConsumerStatefulWidget {
  const DesktopOverviewHub({
    super.key,
    required this.onActivateWindow,
    required this.onDismiss,
    required this.onNavigate,
    required this.onActivateSelection,
  });

  final ValueChanged<DenialWindow> onActivateWindow;
  final VoidCallback onDismiss;
  final ValueChanged<DesktopOverviewDirection> onNavigate;
  final VoidCallback onActivateSelection;

  @override
  ConsumerState<DesktopOverviewHub> createState() => _DesktopOverviewHubState();
}

class _DesktopOverviewHubState extends ConsumerState<DesktopOverviewHub>
    with _RetainedOverview<DesktopOverviewHub> {
  late final ShellSearchSession _session =
      ShellSearchSession(debugLabel: 'desktop-search')
        ..onDismiss = _dismiss
        ..onActivate = _activate
        ..onKeyWithoutQuery = _keyWithoutQuery
        ..onSubmitWithoutQuery = _submitWithoutQuery;
  final ShellSearchIndexCache _indexCache = ShellSearchIndexCache();
  DesktopOverviewState? _open;

  @override
  void initState() {
    super.initState();
    _session.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _session
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  /// The hub dims what a new query does not find, and selects on its card
  /// the window the arrows choose.
  void _searchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  bool keeps(DesktopOverviewState? overview) =>
      desktopOverviewHasBackdrop(overview);

  void _dismiss() => widget.onDismiss();

  void _activate(ShellSearchTarget target, Rect _) {
    if (target case ShellSearchWindowTarget(:final window)) {
      _session.focus.unfocus();
      widget.onActivateWindow(window.window);
    }
  }

  /// With nothing typed the arrows move between the overview's windows.
  bool _keyWithoutQuery(LogicalKeyboardKey key) {
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => DesktopOverviewDirection.left,
      LogicalKeyboardKey.arrowRight => DesktopOverviewDirection.right,
      LogicalKeyboardKey.arrowUp => DesktopOverviewDirection.up,
      LogicalKeyboardKey.arrowDown => DesktopOverviewDirection.down,
      _ => null,
    };
    if (direction == null) {
      return false;
    }
    widget.onNavigate(direction);
    return true;
  }

  void _submitWithoutQuery() => widget.onActivateSelection();

  void _overviewChanged(DesktopOverviewState? overview) {
    final hub = desktopOverviewIsHub(overview) ? overview : null;
    final opened = hub != null && _open == null;
    final closed = hub == null && _open != null;
    _open = hub;
    if (opened) {
      _session.start();
    } else if (closed) {
      _session.focus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(
      desktopWorkspaceProvider.select((state) => state.overview),
    );
    ref.listen<DesktopOverviewState?>(
      desktopWorkspaceProvider.select((state) => state.overview),
      (_, next) => _overviewChanged(next),
    );
    final overview = retainOverview(live);
    if (overview == null) {
      return const SizedBox.shrink();
    }
    final interactive = identical(overview, live);
    final motion = ref.watch(desktopOverviewMotionProvider).presence;
    final content = overview.bounds;
    final index = _indexCache.resolve(context, ref);
    if (overview.appWindows case final appId?) {
      return IgnorePointer(
        child: _AppWindowsChrome(
          overview: overview,
          appId: appId,
          appName: index.appOfWindow(appId)?.name ?? appId,
          motion: motion,
        ),
      );
    }
    final outcome = ref
        .watch(shellSearchBackendProvider)
        .search(
          _session.query.text,
          scope: ShellSearchScope.openWindows,
          index: index,
          windows: watchShellSearchWindows(
            context,
            ref,
            ShellSearchWindows.desk,
            index,
          ),
        );
    final field = DesktopOverviewHubMetrics.searchFieldOf(content);
    final listHeight = ShellSearchWindowResults.heightFor(
      outcome,
      math.max(
        ShellSearchMetrics.desktop.rowHeight * 2,
        (overview.backgroundBounds.bottom - field.bottom) * 0.62,
      ),
    );
    // The window chosen among the results is the overview's selection too,
    // so the arrows visibly move between the windows they choose.
    if (interactive && outcome.searching) {
      final key = _session.chosen;
      final chosen =
          outcome.windows
              .where((window) => 'w:${window.id}' == key)
              .firstOrNull ??
          outcome.windows.firstOrNull;
      if (chosen case final window?
          when overview.selectedObjectId != window.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(desktopWorkspaceProvider.notifier)
                .selectOverviewWindow(window.id);
          }
        });
      }
    }
    // The window being dragged goes undimmed with the pointer.
    final dragged = ref.watch(
      desktopWorkspaceProvider.select((state) {
        for (final placement in state.placements.values) {
          if (placement.dragging) {
            return placement.objectId;
          }
        }
        return null;
      }),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: _SearchVeils(
            overview: overview,
            desktop: ref.read(desktopWorkspaceProvider),
            dragged: dragged,
            outcome: outcome,
            motion: motion,
            // A closing overview may zoom into another screen than the one
            // it opened on; the dimming fades instead of following it.
            shown: interactive,
          ),
        ),
        Positioned.fromRect(
          rect: field,
          child: _ArrivesWith(
            motion: motion,
            child: IgnorePointer(
              ignoring: !interactive,
              child: ShellSearchField(
                style: ShellSearchStyle.desktop,
                controller: _session.query,
                focusNode: _session.focus,
                hint: context.l10n.shellSearchOpenWindowsHint,
                onSubmitted: _session.submit,
                onClear: _session.clear,
                elevated: true,
              ),
            ),
          ),
        ),
        Positioned(
          left: field.left,
          top: field.bottom + 10,
          width: field.width,
          height: listHeight,
          child: IgnorePointer(
            ignoring: !interactive || !outcome.searching,
            child: _Dropdown(
              visible: interactive && outcome.searching,
              child: ShellSearchWindowResults(
                session: _session,
                outcome: outcome.searching ? outcome : ShellSearchOutcome.empty,
                onOpenWindow: (window, rect) =>
                    _activate(ShellSearchWindowTarget(window), rect),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades a piece of the overview's chrome in as the overview opens and
/// lowers it from above, without rebuilding it.
class _ArrivesWith extends StatelessWidget {
  const _ArrivesWith({required this.motion, required this.child});

  final Animation<double> motion;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: motion,
    child: SlideTransition(
      position: motion.drive(
        Tween<Offset>(begin: const Offset(0.0, -0.6), end: Offset.zero),
      ),
      child: child,
    ),
  );
}

/// The results under the hub's field, which appear and leave with the
/// query.
class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final radius = BorderRadius.circular(theme.panelRadius);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: reduceMotion ? Duration.zero : Motion.desktopPanelFadeOpen,
      curve: Motion.standard,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.97,
        alignment: Alignment.topCenter,
        duration: reduceMotion ? Duration.zero : Motion.desktopPanelFadeOpen,
        curve: Motion.md3EmphasizedDecelerate,
        child: ShellBackdropBlur(
          blur: visible && theme.effectivePanelOpacity < 1.0,
          borderRadius: radius,
          blendMode: BlendMode.srcOver,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.panelColor(colors.panelBackground),
              borderRadius: radius,
              border: Border.all(color: colors.hairline),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Dims the screen cards and windows of the overview the search does not
/// find. A stack counts as found when any of its windows is.
class _SearchVeils extends StatelessWidget {
  const _SearchVeils({
    required this.overview,
    required this.desktop,
    required this.dragged,
    required this.outcome,
    required this.motion,
    required this.shown,
  });

  final DesktopOverviewState overview;
  final DesktopWorkspaceState desktop;
  final int? dragged;
  final ShellSearchOutcome outcome;
  final Animation<double> motion;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final veils = desktopOverviewSearchVeils(
      overview: overview,
      desktop: desktop,
      dragged: dragged,
      outcome: outcome,
      windowRadius: context.shellTheme.windowRadius,
      cardRadius: context.shellTheme.panelRadius,
    );
    final scrim = context.shellColors.overviewScrim;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: shown && veils.isNotEmpty ? 1.0 : 0.0),
      duration: reduceMotion ? Duration.zero : Motion.tile,
      curve: Motion.standard,
      builder: (context, strength, _) => CustomPaint(
        size: Size.infinite,
        painter: _VeilPainter(
          veils: veils,
          motion: motion,
          color: scrim.withValues(alpha: 0.66 * strength),
        ),
      ),
    );
  }
}

/// A dimmed screen card or window of the hub: drawn at [rect] when the
/// overview is open, at [home] when closed, between them as it moves.
typedef DesktopOverviewVeil = ({Rect home, Rect rect, double radius});

/// What the hub dims while [outcome] searches: every screen card none of
/// whose windows is found (with its label), and in a found card that is not
/// a stack every window that is not found. Nothing while nothing is typed.
List<DesktopOverviewVeil> desktopOverviewSearchVeils({
  required DesktopOverviewState overview,
  required DesktopWorkspaceState desktop,
  required int? dragged,
  required ShellSearchOutcome outcome,
  required double windowRadius,
  required double cardRadius,
}) {
  final screens = overview.workspaces?.screens;
  if (!outcome.searching || screens == null) {
    return const <DesktopOverviewVeil>[];
  }
  final found = {for (final window in outcome.windows) window.id};
  final workspaces = overview.workspaces!;
  final veils = <DesktopOverviewVeil>[];
  for (final card in screens.cards) {
    if (!card.objectIds.any(found.contains)) {
      final rect = DesktopOverviewHubMetrics.cardVeil(card.geometry.rect);
      veils.add((
        home: workspaces.cameraRect(rect, screens.currentCardId ?? 1),
        rect: rect,
        radius: cardRadius,
      ));
      continue;
    }
    if (card.stacked) {
      continue;
    }
    for (final objectId in card.objectIds) {
      final frame = overview.frames[objectId];
      final placement = desktop.placements[objectId];
      if (frame == null ||
          placement == null ||
          objectId == dragged ||
          found.contains(objectId)) {
        continue;
      }
      veils.add((
        home:
            desktopOverviewHome(
              overview: overview,
              desktop: desktop,
              frame: frame,
              desktopFrame: placement.frame,
            ) ??
            frame,
        rect: frame,
        radius: windowRadius * card.geometry.scale,
      ));
    }
  }
  return veils;
}

class _VeilPainter extends CustomPainter {
  _VeilPainter({required this.veils, required this.motion, required this.color})
    : super(repaint: motion);

  final List<DesktopOverviewVeil> veils;
  final Animation<double> motion;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0.0) {
      return;
    }
    final paint = Paint()..color = color;
    final t = motion.value;
    for (final veil in veils) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.lerp(veil.home, veil.rect, t)!,
          Radius.circular(veil.radius),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VeilPainter oldDelegate) =>
      oldDelegate.color != color ||
      !identical(oldDelegate.motion, motion) ||
      oldDelegate.veils.length != veils.length ||
      !_sameVeils(oldDelegate.veils, veils);

  static bool _sameVeils(
    List<DesktopOverviewVeil> left,
    List<DesktopOverviewVeil> right,
  ) {
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

/// The app windows' name, the app's icon and its number of windows, above
/// them, and every window's title under it.
class _AppWindowsChrome extends ConsumerWidget {
  const _AppWindowsChrome({
    required this.overview,
    required this.appId,
    required this.appName,
    required this.motion,
  });

  final DesktopOverviewState overview;
  final String appId;
  final String appName;
  final Animation<double> motion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = <int, DenialWindow>{
      for (final window in ref.watch(shellSearchDeskWindowsProvider))
        window.objectId: window,
    };
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final band = DesktopOverviewHubMetrics.bandOf(overview.bounds);
    final textStyle = theme.text.base.copyWith(
      decoration: TextDecoration.none,
      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
    );
    return FadeTransition(
      opacity: motion,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: Rect.fromCenter(
              center: band.center + const Offset(0.0, 6.0),
              width: math.max(0.0, band.width - 48.0),
              height: 48.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: DesktopApplicationIcon(appId: appId),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.screensOverviewStackCount(
                    overview.frames.length,
                  ),
                  style: textStyle.copyWith(
                    fontSize: 16,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          for (final entry in overview.frames.entries)
            if (windows[entry.key] case final window?)
              Positioned(
                key: ValueKey<int>(entry.key),
                left: entry.value.left,
                top: entry.value.bottom + 8,
                width: entry.value.width,
                height: DesktopOverviewLayout.titleExtent - 8,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    localizedWindowTitle(context, window),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: textStyle.copyWith(
                      fontSize: 16,
                      fontWeight: overview.selectedObjectId == entry.key
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: overview.selectedObjectId == entry.key
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
