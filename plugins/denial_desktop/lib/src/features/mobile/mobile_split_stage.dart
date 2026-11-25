import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show hapticsServiceProvider;
import 'package:denial_flutter_sdk/tokens.dart';

import '../../launcher/widgets/launcher_icon.dart';
import '../../launcher/window_application.dart';
import '../../state/reference_shell_controller.dart';
import '../../state/reference_shell_metrics.dart';
import '../../state/split_view.dart';

/// Sizes of Split View's controls, in logical pixels.
abstract final class SplitViewMetrics {
  /// The divider as drawn: deniald leaves this gap between rounded windows
  /// (`SPLIT_VIEW_GAP` in `split_view.rs`), and [squareGap] between square
  /// ones (`SQUARE_SPLIT_VIEW_GAP`).
  static const double gap = 10;
  static const double squareGap = 2;

  /// The divider's touch zone, centred on the gap.
  static const double dividerZone = 44;
  static const double grabLength = 44;
  static const double grabThickness = 4;

  /// A window's handle: a short bar at the top of its half, below the
  /// status bar, and the zone around it that takes a finger.
  static const double handleWidth = 36;
  static const double handleThickness = 5;
  static const double handleZoneWidth = 96;
  static const double handleZoneHeight = 36;

  /// A window lifted by its handle shrinks this much.
  static const double liftScale = 0.94;
}

/// Lays [child] out over the horizontal span [left] to [right] of its
/// parent, as shares of the parent's width, at the parent's full height.
class SplitPane extends StatelessWidget {
  const SplitPane({
    super.key,
    required this.left,
    required this.right,
    required this.child,
  });

  final double left;
  final double right;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (left <= 0 && right >= 1) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: left * width,
              width: math.max(0, (right - left) * width),
              top: 0,
              bottom: 0,
              child: child,
            ),
          ],
        );
      },
    );
  }
}

/// The windows of one card as the deck and its flights draw them, the
/// app's first: each where it is on the screen, so a Split View pair shows
/// side by side on the divider's dark bar, and a dialog over its app.
class CardWindows extends StatelessWidget {
  const CardWindows({super.key, required this.windows});

  final List<DenialWindow> windows;

  @override
  Widget build(BuildContext context) {
    final placement = splitPlacement(windows);
    final split = windows.any((window) => window.inSplitView);
    final app = windows.first;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (split) const ColoredBox(color: ShellMediaColors.darkness),
        for (final window in windows)
          SplitPane(
            key: ValueKey<int>(window.objectId),
            left: placement[window.objectId]!.left,
            right: placement[window.objectId]!.right,
            child: WindowSurface(
              window: window,
              // Glass would hide the app beneath; side by side, there is
              // none beneath.
              applyBackdrop: window == app || window.inSplitView,
              contentPadding: const EdgeInsets.only(
                top: ReferenceShellMetrics.statusBarHeight,
              ),
            ),
          ),
      ],
    );
  }
}

/// Two apps side by side in Split View, in front: each window in its half,
/// the divider between them and a handle on top of each.
///
/// Dragging the divider covers both apps with their icons, as on iPadOS:
/// the apps take their new widths only when it is let go, at a third, a
/// half or two thirds, or, dragged to an edge, the app on that side leaves
/// and the other fills the screen. Dragging a handle lifts its app: let go
/// over the other half the two change sides, pulled down it leaves the pair
/// and fills the screen.
class MobileSplitStage extends ConsumerStatefulWidget {
  const MobileSplitStage({
    super.key,
    required this.pair,
    required this.windows,
    required this.foreground,
    required this.opacity,
  });

  final SplitPair pair;

  /// The windows of the pair's card, back to front: the two and any window
  /// opened over them.
  final List<DenialWindow> windows;
  final int? foreground;
  final double opacity;

  @override
  ConsumerState<MobileSplitStage> createState() => _MobileSplitStageState();
}

class _MobileSplitStageState extends ConsumerState<MobileSplitStage>
    with SingleTickerProviderStateMixin {
  /// Where the divider is drawn while a finger moves it or it settles, as a
  /// share of the width; null at rest, where the windows say.
  double? _share;
  double _dragStartShare = 0;
  double _dragDx = 0;

  /// The apps are covered by their icons: the divider moves, or the apps
  /// have not yet taken the widths it settled at.
  bool _covered = false;

  /// The share the apps are to take, until they have.
  double? _awaitedShare;
  Timer? _coverTimeout;

  /// How long the covers wait for the apps' new sizes.
  static const Duration _coverWait = Duration(milliseconds: 700);

  /// A window lifted by its handle, and how far it moved.
  int? _lifted;
  Offset _lift = Offset.zero;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Animation<double>? _settleShare;
  Animation<Offset>? _settleLift;

  @override
  void didUpdateWidget(covariant MobileSplitStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkCovers();
  }

  @override
  void dispose() {
    _coverTimeout?.cancel();
    _settle.dispose();
    super.dispose();
  }

  // Divider ---------------------------------------------------------------

  void _dividerStart(DragStartDetails details) {
    _settle.stop();
    _coverTimeout?.cancel();
    _awaitedShare = null;
    _dragStartShare = _share ?? widget.pair.share;
    _dragDx = 0;
    setState(() {
      _share = _dragStartShare;
      _covered = true;
    });
  }

  void _dividerMove(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    _dragDx += details.delta.dx;
    setState(() {
      _share = (_dragStartShare + _dragDx / width).clamp(0.0, 1.0);
    });
  }

  void _dividerEnd(DragEndDetails details, double width) {
    final share = _share ?? widget.pair.share;
    final velocity = width <= 0
        ? 0.0
        : details.velocity.pixelsPerSecond.dx / width;
    final release = releaseSplitDivider(share, velocity: velocity);
    final shell = ref.read(referenceShellProvider.notifier);
    switch (release) {
      case SplitDividerRests(share: final rest):
        ref.read(hapticsServiceProvider).pulse();
        _animateShare(rest);
        _awaitedShare = rest;
        shell.setSplitShare(widget.pair, rest);
        _coverTimeout = Timer(_coverWait, _uncover);
        _checkCovers();
      case SplitDividerCloses(:final leftLeaves):
        _animateShare(leftLeaves ? 0 : 1);
        final stays = leftLeaves ? widget.pair.right : widget.pair.left;
        // The divider reaches the edge first.
        Timer(_settle.duration!, () {
          if (mounted) shell.leaveSplit(widget.pair, stays: stays);
        });
    }
  }

  void _animateShare(double target) {
    final from = _share ?? widget.pair.share;
    _settleShare = Tween<double>(
      begin: from,
      end: target,
    ).animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    _settleLift = null;
    unawaited(
      _settle.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _settleShare = null);
      }),
    );
    setState(() => _share = target);
  }

  /// The covers go once both apps have the widths the divider settled at.
  void _checkCovers() {
    final awaited = _awaitedShare;
    if (awaited == null || !_covered) return;
    final pair = widget.pair;
    bool sized(DenialWindow window) =>
        (window.surfaceWidth - window.geometryWidth).abs() <= 2;
    if ((pair.share - awaited).abs() < 1e-3 &&
        sized(pair.left) &&
        sized(pair.right)) {
      _uncover();
    }
  }

  void _uncover() {
    _coverTimeout?.cancel();
    _awaitedShare = null;
    if (!mounted) return;
    setState(() {
      _covered = false;
      _share = null;
    });
  }

  // Handles ---------------------------------------------------------------

  void _handleStart(DenialWindow window) {
    _settle.stop();
    ref.read(hapticsServiceProvider).pulse();
    setState(() {
      _lifted = window.objectId;
      _lift = Offset.zero;
    });
  }

  void _handleMove(DragUpdateDetails details) {
    if (_lifted == null) return;
    setState(() => _lift += details.delta);
  }

  void _handleEnd(DenialWindow window, Size size) {
    if (_lifted != window.objectId) return;
    final pair = widget.pair;
    final release = releaseSplitHandle(
      drag: _lift,
      screen: size,
      onLeft: window.objectId == pair.left.objectId,
      share: pair.share,
    );
    final shell = ref.read(referenceShellProvider.notifier);
    switch (release) {
      case SplitHandleRelease.fullScreen:
        setState(() => _lifted = null);
        shell.leaveSplit(pair, stays: window);
      case SplitHandleRelease.swap:
        ref.read(hapticsServiceProvider).pulse();
        setState(() {
          _lifted = null;
          _covered = true;
        });
        shell.swapSplit(pair);
        _coverTimeout?.cancel();
        _coverTimeout = Timer(_coverWait, _uncover);
        _awaitedShare = 1 - pair.share;
      case SplitHandleRelease.stay:
        _settleLift = Tween<Offset>(
          begin: _lift,
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutBack));
        _settleShare = null;
        unawaited(
          _settle.forward(from: 0).whenComplete(() {
            if (mounted) {
              setState(() {
                _lifted = null;
                _lift = Offset.zero;
                _settleLift = null;
              });
            }
          }),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final placement = splitPlacement(widget.windows);
    return Opacity(
      opacity: widget.opacity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return AnimatedBuilder(
            animation: _settle,
            builder: (context, _) => _stage(context, size, placement),
          );
        },
      ),
    );
  }

  Widget _stage(
    BuildContext context,
    Size size,
    Map<int, ({double left, double right})> placement,
  ) {
    final pair = widget.pair;
    final width = size.width;
    final share = _settleShare?.value ?? _share;
    final lift = _settleLift?.value ?? _lift;
    final leftSpan = placement[pair.left.objectId]!;
    final rightSpan = placement[pair.right.objectId]!;
    // The divider sits in the gap deniald left, or under the finger.
    final dividerX = share == null
        ? (leftSpan.right + rightSpan.left) / 2 * width
        : share * width;
    const statusBar = ReferenceShellMetrics.statusBarHeight;
    final theme = context.shellTheme;
    final gap = theme.roundedWindowFrame
        ? SplitViewMetrics.gap
        : SplitViewMetrics.squareGap;
    // A lifted app is a window, rounded as apps sliding side by side.
    final liftedRadius = BorderRadius.circular(theme.scaledWindowRadius(18));
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final window in widget.windows)
          if (window.objectId != _lifted)
            SplitPane(
              key: ValueKey<int>(window.objectId),
              left: placement[window.objectId]!.left,
              right: placement[window.objectId]!.right,
              child: _window(window),
            ),
        // The gap between the apps is the divider's bar. Keys keep every
        // control's gesture across the covers coming and going.
        Positioned(
          key: const ValueKey('divider bar'),
          left: dividerX - gap / 2,
          width: gap,
          top: 0,
          bottom: 0,
          child: const ColoredBox(color: ShellMediaColors.darkness),
        ),
        if (_covered) ...[
          _cover(
            const ValueKey('left cover'),
            pair.left,
            0,
            dividerX - gap / 2,
          ),
          _cover(
            const ValueKey('right cover'),
            pair.right,
            dividerX + gap / 2,
            width,
          ),
        ],
        if (_lifted case final lifted?)
          for (final window in widget.windows)
            if (window.objectId == lifted)
              SplitPane(
                key: ValueKey<int>(window.objectId),
                left: placement[window.objectId]!.left,
                right: placement[window.objectId]!.right,
                child: Transform.translate(
                  offset: lift,
                  child: Transform.scale(
                    scale: SplitViewMetrics.liftScale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: liftedRadius,
                        boxShadow: const [
                          BoxShadow(
                            color: ShellMediaColors.shadow,
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: liftedRadius,
                        child: _window(window),
                      ),
                    ),
                  ),
                ),
              ),
        // The grab on the divider, and the zone a finger takes it in.
        Positioned(
          key: const ValueKey('divider grab'),
          left: dividerX - SplitViewMetrics.grabThickness / 2,
          width: SplitViewMetrics.grabThickness,
          top: (size.height + statusBar - SplitViewMetrics.grabLength) / 2,
          height: SplitViewMetrics.grabLength,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xb3ffffff),
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('divider zone'),
          left: dividerX - SplitViewMetrics.dividerZone / 2,
          width: SplitViewMetrics.dividerZone,
          top: statusBar,
          bottom: 0,
          child: ShellInputRegion(
            debugLabel: 'split view divider',
            child: Semantics(
              label: context.l10n.splitViewDivider,
              slider: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _dividerStart,
                onHorizontalDragUpdate: (details) =>
                    _dividerMove(details, width),
                onHorizontalDragEnd: (details) => _dividerEnd(details, width),
                onHorizontalDragCancel: () =>
                    _dividerEnd(DragEndDetails(primaryVelocity: 0), width),
              ),
            ),
          ),
        ),
        if (!_covered)
          for (final window in [pair.left, pair.right])
            _handle(
              context,
              window,
              placement[window.objectId]!,
              size,
              lifted: window.objectId == _lifted,
              lift: lift,
            ),
      ],
    );
  }

  Widget _window(DenialWindow window) => WindowContentRect(
    key: ValueKey<int>(window.objectId),
    window: window,
    active: window.objectId == widget.foreground,
    contentPadding: const EdgeInsets.only(
      top: ReferenceShellMetrics.statusBarHeight,
    ),
  );

  /// An app under the moving divider: its icon on a plain panel over its
  /// live half.
  Widget _cover(Key key, DenialWindow window, double from, double to) {
    return Positioned(
      key: key,
      left: from,
      width: math.max(0, to - from),
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: ColoredBox(
          color: ShellMediaColors.darkSurface,
          child: Center(child: _AppIcon(window: window)),
        ),
      ),
    );
  }

  Widget _handle(
    BuildContext context,
    DenialWindow window,
    ({double left, double right}) span,
    Size size, {
    required bool lifted,
    required Offset lift,
  }) {
    final centre = (span.left + span.right) / 2 * size.width;
    final offset = lifted ? lift : Offset.zero;
    final application = ref.watch(windowApplicationProvider(window.appId));
    final name = application.name ?? localizedWindowTitle(context, window);
    return Positioned(
      key: ValueKey(('handle', window.objectId)),
      left: centre - SplitViewMetrics.handleZoneWidth / 2 + offset.dx,
      top: ReferenceShellMetrics.statusBarHeight + offset.dy,
      width: SplitViewMetrics.handleZoneWidth,
      height: SplitViewMetrics.handleZoneHeight,
      child: ShellInputRegion(
        debugLabel: 'split view handle',
        child: Semantics(
          button: true,
          label: context.l10n.splitViewHandle(name),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _handleStart(window),
            onPanUpdate: _handleMove,
            onPanEnd: (_) => _handleEnd(window, size),
            onPanCancel: () => _handleEnd(window, size),
            child: const Align(
              alignment: Alignment(0, -0.4),
              child: SizedBox(
                width: SplitViewMetrics.handleWidth,
                height: SplitViewMetrics.handleThickness,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xccffffff),
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                    boxShadow: [
                      BoxShadow(color: Color(0x66000000), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends ConsumerWidget {
  const _AppIcon({required this.window});

  final DenialWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(window.appId));
    return SizedBox.square(
      dimension: 72,
      child: LauncherIcon(
        iconPath: application.iconPath,
        icon: application.icon,
      ),
    );
  }
}
