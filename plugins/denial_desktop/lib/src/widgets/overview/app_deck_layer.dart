import 'package:denial_desktop/src/state/app_deck.dart';
import 'package:denial_desktop/src/state/reference_shell_metrics.dart';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motor/motor.dart' as motor;

import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';

import '../../launcher/home_icon_locator.dart' show launcherAppIdentity;
import '../../features/mobile/mobile_split_stage.dart' show CardWindows;
import '../../launcher/window_application.dart';
import 'overview_card_label.dart';
import 'overview_chrome.dart';

/// Draws the open apps wherever the [deck] has them, while it presents:
/// switching, lifting into recents, recents itself, a card opening, and
/// recents leaving for home. At rest with an app filling the screen it draws
/// nothing, and the app's own stage shows the app.
///
/// In recents a tap opens a card, a card swiped up closes its app, a
/// sideways drag scrolls the row, and a tap beside the cards goes home.
/// Cards of an app with several windows name their window under the app,
/// and carry a button that closes them all. «Close all» under the cards
/// closes every app in recents: every card leaves as a swiped one does, and
/// recents goes home at once behind them.
class AppDeckLayer extends StatefulWidget {
  const AppDeckLayer({
    super.key,
    required this.deck,
    required this.windows,
    this.windowsOver = const <int, List<DenialWindow>>{},
    required this.recents,
    this.backdrop,
    required this.onPresentationChanged,
    this.onProgressChanged,
    required this.onCloseRecents,
    required this.onLeaveWindow,
    required this.onDismissWindow,
    required this.onOpenWindow,
    this.onMoveWindowToDesk,
    this.splitTargetOf,
    this.onSplit,
    this.onLift,
  });

  final AppDeck deck;

  /// The open apps.
  final List<DenialWindow> windows;

  /// The windows drawn over an app on its card, such as its dialog, by app.
  final Map<int, List<DenialWindow>> windowsOver;

  /// Recents is open or opening, and takes touches.
  final bool recents;

  /// The scene behind recents, frosted once. Translucent apps draw slices of
  /// it as their glass instead of filtering the scene on every frame.
  final ValueListenable<FrostedBackdrop?>? backdrop;
  final ValueChanged<bool> onPresentationChanged;

  /// How far recents is open, for the launcher beneath.
  final ValueChanged<double>? onProgressChanged;
  final VoidCallback onCloseRecents;

  /// A card was thrown away and is leaving the screen.
  final ValueChanged<DenialWindow> onLeaveWindow;

  /// A thrown card has left the screen.
  final ValueChanged<DenialWindow> onDismissWindow;
  final ValueChanged<DenialWindow> onOpenWindow;

  /// Moves an app to the monitor beside the phone; none without a monitor.
  final ValueChanged<DenialWindow>? onMoveWindowToDesk;

  /// The app a card's window can share the screen with in Split View: the
  /// app in front; null when there is none to share with.
  final DenialWindow? Function(DenialWindow window)? splitTargetOf;

  /// A card lifted by a long press was dropped on the left ([onLeft]) or
  /// right side of the screen: its window shares the screen with
  /// [splitTargetOf]'s.
  final void Function(DenialWindow window, {required bool onLeft})? onSplit;

  /// A card was lifted by a long press, for a tap of the haptic motor.
  final VoidCallback? onLift;

  @override
  State<AppDeckLayer> createState() => _AppDeckLayerState();
}

class _AppDeckLayerState extends State<AppDeckLayer> {
  /// How far a fling carries the recents row, in seconds of its speed.
  static const double _rowFlingProjection = 0.35;

  /// A fling coasts to its card for at least this long, in seconds; a card
  /// nearer than that is passed for the next one. Slower than the longest,
  /// a release springs to the nearest card instead.
  static const double _shortestGlide = 0.3;
  static const double _longestGlide = 1.1;

  /// A release this fast, in logical pixels per second, is a flick and
  /// reaches at least the next card it heads for: Launcher3's fling
  /// threshold, 500 dp/s.
  static const double _flickSpeed = 500;

  final _open = ValueNotifier(0.0);
  late final Animation<double> _openAnimation = Animation.fromValueListenable(
    _open,
  );
  late final Animation<double> _labelOpacity = Animation.fromValueListenable(
    _open,
    transformer: const Interval(0.7, 1).transform,
  );
  var _windows = <int, DenialWindow>{};
  final _poses = <int, ValueNotifier<WindowPose>>{};

  /// The deck's windows of each app, by window: the window's app's windows.
  var _appWindows = <int, List<int>>{};

  /// Cards told to leave by a close-all: they go as a flung card goes.
  var _closing = <int>{};

  /// «Close all» was tapped: every card is leaving and recents goes home.
  /// The button fades out with recents and takes no second tap.
  bool _closingAll = false;

  /// A card lifted to share the screen: its window, the app it would share
  /// it with, and where the finger is, in this layer's coordinates.
  final _lifted =
      ValueNotifier<
        ({DenialWindow window, DenialWindow target, Offset position})?
      >(null);

  /// The share of the width at each side of the screen that a lifted card
  /// is dropped on to share the screen.
  static const double _splitZone = 0.3;

  /// The apps drawn, back to front.
  List<int> _drawn = const <int>[];
  bool _presenting = false;

  bool _rowDragging = false;
  double _rowDrag = 0;

  /// A touch stopped the recents row where it was.
  bool _rowCaught = false;

  @override
  void initState() {
    super.initState();
    _indexWindows();
    widget.deck.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = context.shellTheme;
    final geometry = DeckGeometry(
      size: MediaQuery.sizeOf(context),
      padding: MediaQuery.paddingOf(context),
      windowRadius: theme.windowRadius,
      switchRadius: theme.scaledRadius(18),
      ltr: Directionality.of(context) == TextDirection.ltr,
    );
    if (geometry != widget.deck.geometry) {
      widget.deck.geometry = geometry;
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    }
  }

  @override
  void didUpdateWidget(covariant AppDeckLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deck != oldWidget.deck) {
      oldWidget.deck.removeListener(_update);
      widget.deck.addListener(_update);
    }
    if (!identical(widget.windows, oldWidget.windows)) _indexWindows();
    if (!widget.recents) _endRowDrag(null);
    // Recents opened again, even over cards still leaving: what is left in
    // it can be closed again.
    if (widget.recents && !oldWidget.recents) _closingAll = false;
  }

  @override
  void dispose() {
    widget.deck.removeListener(_update);
    for (final pose in _poses.values) {
      pose.dispose();
    }
    _open.dispose();
    _lifted.dispose();
    super.dispose();
  }

  Offset _local(Offset global) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.globalToLocal(global) : global;
  }

  /// The side of the screen a lifted card over [position] would take:
  /// true left, false right, null neither.
  bool? _splitSide(Offset position) {
    final width = widget.deck.geometry.size.width;
    if (width <= 0) return null;
    if (position.dx < width * _splitZone) return true;
    if (position.dx > width * (1 - _splitZone)) return false;
    return null;
  }

  void _liftMoved(DenialWindow window, Offset? global) {
    if (global == null) {
      _lifted.value = null;
      return;
    }
    final target = _lifted.value?.target ?? widget.splitTargetOf?.call(window);
    if (target == null) return;
    if (_lifted.value == null) widget.onLift?.call();
    _lifted.value = (window: window, target: target, position: _local(global));
  }

  void _liftDropped(DenialWindow window, Offset global) {
    final side = _splitSide(_local(global));
    final lifted = _lifted.value;
    _lifted.value = null;
    if (side == null || lifted == null) return;
    widget.onSplit?.call(window, onLeft: side);
  }

  void _indexWindows() {
    _windows = {for (final window in widget.windows) window.objectId: window};
    final byApp = <String, List<int>>{};
    final appWindows = <int, List<int>>{};
    for (final window in widget.windows) {
      final over = widget.windowsOver[window.objectId] ?? const [];
      final app = over.any((other) => other.inSplitView)
          ? ''
          : launcherAppIdentity(window.appId);
      if (app.isEmpty) {
        appWindows[window.objectId] = [window.objectId];
        continue;
      }
      final windows = byApp[app] ??= <int>[];
      windows.add(window.objectId);
      appWindows[window.objectId] = windows;
    }
    _appWindows = appWindows;
    _closing = {
      for (final id in _closing)
        if (_windows.containsKey(id)) id,
    };
    _poses.removeWhere((id, pose) {
      if (_windows.containsKey(id)) return false;
      WidgetsBinding.instance.addPostFrameCallback((_) => pose.dispose());
      return true;
    });
  }

  /// Poses every app from the deck's values, and draws those on screen
  /// newer in front of older, in the same order however the row moves.
  void _update() {
    if (!mounted) return;
    final deck = widget.deck;
    final shown = deck.shown;
    _open.value = shown;
    widget.onProgressChanged?.call(shown);
    final presenting = deck.presenting.value;
    final geometry = deck.geometry;
    final ids = <int>[];
    if (presenting && !geometry.isEmpty) {
      final screen = geometry.screen;
      // A card thrown away is drawn over the row that closes under it.
      for (final id in [...deck.order, ...deck.leaving]) {
        if (id == deck.hidden || !_windows.containsKey(id)) continue;
        final pose = deck.poseOf(id);
        (_poses[id] ??= ValueNotifier(pose)).value = pose;
        if (pose.rect.overlaps(screen)) ids.add(id);
      }
    }
    if (presenting != _presenting) {
      widget.onPresentationChanged(presenting);
    }
    if (presenting != _presenting || !listEquals(ids, _drawn)) {
      setState(() {
        _presenting = presenting;
        _drawn = ids;
        if (!presenting) _closingAll = false;
      });
    }
  }

  /// «Close all»: every card in recents leaves as a flung card does, each
  /// app closing as its card goes, just as a swipe closes it. Recents goes
  /// home at once: the cards have left the row where they were drawn, so
  /// they fly straight out over home as it comes.
  void _closeAll() {
    final deck = widget.deck;
    if (_closingAll || !widget.recents || deck.length == 0) return;
    _sendAway(deck.order);
    setState(() => _closingAll = true);
    widget.onCloseRecents();
  }

  /// The close-all of [window]'s card: every card of its app leaves, as a
  /// flung card does.
  void _closeApp(DenialWindow window) =>
      _sendAway(_appWindows[window.objectId] ?? [window.objectId]);

  /// The cards of [ids] leave the row now, each where it is drawn, and fly
  /// out as flung cards; cards off screen have nothing to show and are gone
  /// at once.
  void _sendAway(Iterable<int> ids) {
    final drawn = _drawn.toSet();
    final cards = [
      for (final id in [...ids]) ?_windows[id],
    ];
    for (final card in cards) {
      widget.onLeaveWindow(card);
    }
    final animated = <int>{};
    for (final card in cards) {
      if (drawn.contains(card.objectId)) {
        animated.add(card.objectId);
      } else {
        widget.onDismissWindow(card);
      }
    }
    if (animated.isNotEmpty) {
      setState(() => _closing = {..._closing, ...animated});
    }
  }

  // The recents row under the finger --------------------------------------

  void _catchRow(PointerDownEvent event) {
    final row = widget.deck.row;
    if (!widget.recents || !row.moving || row.held) return;
    row.grab();
    _rowCaught = true;
  }

  void _releaseCatch(PointerEvent event) {
    if (!_rowCaught || _rowDragging) return;
    _rowCaught = false;
    final row = widget.deck.row;
    if (row.held) {
      row.settle(_nearestCard(row.value), ShellSprings.appStrip);
    }
  }

  void _startRowDrag(DragStartDetails details) {
    final deck = widget.deck;
    if (!widget.recents || deck.length == 0) {
      return;
    }
    if (!deck.row.held) deck.row.grab();
    _rowDragging = true;
    _rowCaught = false;
    _rowDrag = 0;
  }

  void _moveRow(DragUpdateDetails details) {
    if (!_rowDragging) return;
    final deck = widget.deck;
    _rowDrag += details.delta.dx;
    final position = deck.row.grabbedAt + deck.geometry.rowDelta(_rowDrag, 1);
    deck.row.hold(_stretch(position));
  }

  /// A fling coasts on to the card nearest where it would come to rest, at
  /// least the next one it heads for, or runs past the first or last card
  /// and bounces back; a slow release springs to the nearest card.
  void _endRowDrag(DragEndDetails? details) {
    if (!_rowDragging) return;
    _rowDragging = false;
    final deck = widget.deck;
    final row = deck.row;
    final speed = details?.velocity.pixelsPerSecond.dx ?? 0;
    final rate = deck.geometry.rowDelta(speed, 1);
    final last = math.max(0, deck.length - 1).toDouble();
    var target = (row.value + rate * _rowFlingProjection).roundToDouble();
    if (speed.abs() >= _flickSpeed) {
      target = rate > 0
          ? math.max(target, row.value.floorToDouble() + 1)
          : math.min(target, row.value.ceilToDouble() - 1);
    }
    if (row.glideTime(target, rate) < _shortestGlide) target += rate.sign;
    if (target < 0 || target > last) {
      // Already past the end, the stretch springs back on its own.
      final outside = row.value < 0 || row.value > last;
      row.settle(
        target < 0 ? 0.0 : last,
        ShellSprings.recentsEdge,
        velocity: outside ? 0 : rate,
      );
    } else if (row.glideTime(target, rate) <= _longestGlide) {
      row.glide(target, rate);
    } else {
      row.settle(target, ShellSprings.appStrip, velocity: rate);
    }
  }

  double _nearestCard(double position) =>
      position.roundToDouble().clamp(0.0, math.max(0, widget.deck.length - 1));

  /// Past the first and last card the row stretches elastically.
  double _stretch(double position) {
    final deck = widget.deck;
    final last = math.max(0, deck.length - 1).toDouble();
    final edge = position.clamp(0.0, last).toDouble();
    final stride = deck.geometry.strideAt(1);
    final extent = deck.geometry.size.width;
    final past = (position - edge) * stride;
    if (past == 0 || stride <= 0 || extent <= 0) return edge;
    const resistance = 0.55;
    final stretch = 1 - 1 / (past.abs() * resistance / extent + 1);
    return edge + past.sign * stretch * extent / stride;
  }

  @override
  Widget build(BuildContext context) {
    if (!_presenting) return const SizedBox.shrink();
    final deck = widget.deck;
    final geometry = deck.geometry;
    final interactive = widget.recents;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !interactive,
        child: Listener(
          onPointerDown: _catchRow,
          onPointerUp: _releaseCatch,
          onPointerCancel: _releaseCatch,
          child: GestureDetector(
            onHorizontalDragStart: _startRowDrag,
            onHorizontalDragUpdate: _moveRow,
            onHorizontalDragEnd: _endRowDrag,
            onHorizontalDragCancel: () => _endRowDrag(null),
            child: ValueListenableBuilder<FrostedBackdrop?>(
              valueListenable:
                  widget.backdrop ??
                  const AlwaysStoppedAnimation<FrostedBackdrop?>(null),
              builder: (context, backdrop, stack) => WindowBackdropCache(
                backdrop: backdrop,
                motion: deck,
                overlayColor: OverviewScrim.colorOf(context),
                overlayOpacity: _open,
                child: stack!,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OverviewScrim(
                    opacity: _openAnimation,
                    onTap: widget.onCloseRecents,
                  ),
                  // Not while the last cards leave: recents goes home then.
                  if (deck.length == 0 &&
                      deck.leaving.isEmpty &&
                      widget.recents &&
                      !_closingAll)
                    EmptyOverviewState(progress: _openAnimation),
                  if ((deck.length > 0 || _closingAll) && !geometry.isEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: recentsCloseAllTop(geometry),
                      height: RecentsCloseAllButton.height,
                      child: IgnorePointer(
                        ignoring: _closingAll,
                        child: FadeTransition(
                          opacity: _labelOpacity,
                          child: Center(
                            child: RecentsCloseAllButton(onTap: _closeAll),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder(
                        valueListenable: _lifted,
                        builder: (context, lifted, _) => lifted == null
                            ? const SizedBox.shrink()
                            : _SplitZones(
                                target: lifted.target,
                                side: _splitSide(lifted.position),
                                zone: _splitZone,
                              ),
                      ),
                    ),
                  ),
                  for (final (index, id) in _drawn.indexed)
                    if ((_windows[id], _poses[id]) case (
                      final window?,
                      final pose?,
                    ))
                      _DeckCard(
                        key: ValueKey<int>(id),
                        window: window,
                        over: widget.windowsOver[id] ?? const <DenialWindow>[],
                        pose: pose,
                        coveredBy: index + 1 < _drawn.length
                            ? _poses[_drawn[index + 1]]
                            : null,
                        labelWidth: geometry.card.width,
                        labelOpacity: _labelOpacity,
                        appWindowCount: _appWindows[id]?.length ?? 1,
                        closing: _closing.contains(id),
                        onLiftMove:
                            widget.onSplit == null ||
                                widget.splitTargetOf?.call(window) == null
                            ? null
                            : _liftMoved,
                        onLiftDrop: _liftDropped,
                        onOpen: widget.onOpenWindow,
                        onLeaving: widget.onLeaveWindow,
                        onDismissed: widget.onDismissWindow,
                        onCloseApp: _closeApp,
                        onMoveToDesk: widget.onMoveWindowToDesk,
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

/// One app as the deck poses it. In recents it is a card: a tap opens it,
/// and a swipe up throws it away.
class _DeckCard extends StatefulWidget {
  const _DeckCard({
    super.key,
    required this.window,
    required this.over,
    required this.pose,
    this.coveredBy,
    required this.labelWidth,
    required this.labelOpacity,
    this.appWindowCount = 1,
    this.closing = false,
    this.onLiftMove,
    this.onLiftDrop,
    required this.onOpen,
    required this.onLeaving,
    required this.onDismissed,
    this.onCloseApp,
    this.onMoveToDesk,
  });

  final DenialWindow window;

  /// Windows opened over the app, such as its dialog, drawn over it.
  final List<DenialWindow> over;
  final ValueListenable<WindowPose> pose;

  /// The pose of the card drawn over this one, the newer app beside it: in
  /// landscape Recents it overlaps this card and its label row, so this
  /// card's buttons keep to the part of the row left uncovered.
  final ValueListenable<WindowPose>? coveredBy;
  final double labelWidth;

  /// The app's icon and name above the card; none without it.
  final Animation<double>? labelOpacity;

  /// How many windows of the card's app Recents shows. With more than one,
  /// the label names the window and offers to close them all.
  final int appWindowCount;

  /// A close-all of the app sends the card away.
  final bool closing;

  /// A long press lifts the card, and it follows the finger, which this
  /// hears of (null once it is let go); none when the card cannot share
  /// the screen with the app in front.
  final void Function(DenialWindow window, Offset? global)? onLiftMove;

  /// The lifted card was let go at this global position.
  final void Function(DenialWindow window, Offset global)? onLiftDrop;
  final ValueChanged<DenialWindow> onOpen;

  /// The card was thrown away: the row may close over it at once.
  final ValueChanged<DenialWindow> onLeaving;

  /// The thrown card has left the screen: its app closes.
  final ValueChanged<DenialWindow> onDismissed;

  /// Closes every window of the card's app.
  final ValueChanged<DenialWindow>? onCloseApp;
  final ValueChanged<DenialWindow>? onMoveToDesk;

  @override
  State<_DeckCard> createState() => _DeckCardState();
}

class _DeckCardState extends State<_DeckCard>
    with SingleTickerProviderStateMixin {
  // Android 16 TaskViewDismissTouchController: half the off-screen travel,
  // 25dp undershoot, and BaseSwipeDetector's 1dp/ms release threshold.
  static const double _downwardRubberBandLimit = 25.0;
  static const double _dismissDistanceRatio = 0.5;
  static const double _dismissFlingVelocity = 1000.0;
  static const double _offscreenMargin = 16.0;

  /// How fast a close-all sends a card up, in logical pixels per second.
  static const double _closeAllVelocity = 2400.0;

  /// A card swiped away shrinks as it leaves.
  static const double _dismissShrink = 0.1;

  /// How far the card is thrown up, in logical pixels, negative upward.
  late final motor.SingleMotionController _throw;
  late final _CardPose _pose;
  double _drag = 0;

  /// The card lifted by a long press, and where its finger went.
  bool _lifted = false;
  double _exit = -double.maxFinite;
  bool _leaving = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _throw = motor.SingleMotionController(
      motion: ShellSprings.cardReturn,
      vsync: this,
      initialValue: 0,
    )..addListener(_checkGone);
    _pose = _CardPose(widget.pose, _throw);
  }

  void _liftStart(LongPressStartDetails details) {
    final move = widget.onLiftMove;
    if (_leaving || move == null) return;
    _lifted = true;
    _pose.lift(Offset.zero);
    move(widget.window, details.globalPosition);
  }

  void _liftMove(LongPressMoveUpdateDetails details) {
    if (!_lifted) return;
    _pose.lift(details.offsetFromOrigin);
    widget.onLiftMove?.call(widget.window, details.globalPosition);
  }

  void _liftEnd(LongPressEndDetails details) {
    if (!_lifted) return;
    _lifted = false;
    _pose.lift(null);
    widget.onLiftDrop?.call(widget.window, details.globalPosition);
  }

  void _liftCancel() {
    if (!_lifted) return;
    _lifted = false;
    _pose.lift(null);
    widget.onLiftMove?.call(widget.window, null);
  }

  @override
  void didUpdateWidget(covariant _DeckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pose != oldWidget.pose) _pose.base = widget.pose;
    if (widget.closing && !oldWidget.closing) {
      _pose.length = math.max(
        1.0,
        _pose.base.value.rect.bottom + _offscreenMargin,
      );
      // The layer took the card out of the row as it sent it away.
      _leave(-_closeAllVelocity, rowClosed: true);
    }
  }

  @override
  void dispose() {
    if (_leaving && !_dismissed) {
      // Taken off screen before it got out: the row has closed over it, so
      // its app still closes.
      final (close, window) = (widget.onDismissed, widget.window);
      WidgetsBinding.instance.addPostFrameCallback((_) => close(window));
    }
    _pose.dispose();
    _throw.dispose();
    super.dispose();
  }

  void _startDrag(DragStartDetails details) {
    if (_leaving) return;
    _throw.stop(canceled: true);
    _pose.length = math.max(
      1.0,
      _pose.base.value.rect.bottom + _offscreenMargin,
    );
    final value = _throw.value;
    final length = _pose.length;
    // Continue from where the card is, also inside its downward stretch.
    _drag = value <= 0
        ? value
        : length *
              (1 -
                  math.sqrt(
                    1 - (value / _downwardRubberBandLimit).clamp(0.0, 1.0),
                  ));
  }

  void _moveDrag(DragUpdateDetails details) {
    if (_leaving) return;
    _drag += details.delta.dy;
    final length = _pose.length;
    if (_drag <= 0) {
      _throw.value = _drag.clamp(-length, 0.0);
    } else {
      // Resistance unwinds smoothly when the finger reverses.
      final fraction = (_drag / length).clamp(0.0, 1.0);
      _throw.value =
          _downwardRubberBandLimit * Curves.decelerate.transform(fraction);
    }
  }

  void _endDrag(DragEndDetails details) {
    if (_leaving) return;
    final velocity = details.velocity.pixelsPerSecond.dy.clamp(-8000.0, 8000.0);
    final passed = _throw.value < -_pose.length * _dismissDistanceRatio;
    final flingUp = velocity < -_dismissFlingVelocity;
    final flingDown = velocity > _dismissFlingVelocity;
    // The release's direction comes before distance: thrown back down, a
    // card returns even past the threshold.
    if (flingUp || (passed && !flingDown)) {
      _leave(velocity);
    } else {
      _settleBack(velocity);
    }
  }

  /// The card leaves upward at [velocity], and its window closes once it
  /// is gone. The row closes over it at once, unless [rowClosed] already.
  void _leave(double velocity, {bool rowClosed = false}) {
    if (_leaving) return;
    _leaving = true;
    _exit = -_pose.length;
    _throw
      ..motion = ShellSprings.cardDismiss
      ..animateTo(_exit, withVelocity: velocity);
    if (!rowClosed) widget.onLeaving(widget.window);
  }

  void _settleBack([double velocity = 0]) {
    if (_leaving) return;
    _throw
      ..motion = ShellSprings.cardReturn
      ..animateTo(0, withVelocity: velocity);
  }

  /// The app closes as soon as its card has left the screen; the spring's
  /// tail past that would only delay it.
  void _checkGone() {
    if (!_leaving || _dismissed || _throw.value > _exit + _offscreenMargin) {
      return;
    }
    _dismissed = true;
    final window = widget.window;
    // Present this last frame before releasing the app's surface.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _throw.stop(canceled: true);
      widget.onDismissed(window);
    });
  }

  /// The Split View partner riding on this card, if any.
  DenialWindow? get _splitPartner {
    final partner = widget.window.splitViewPartnerObjectId;
    if (partner == null) return null;
    for (final window in widget.over) {
      if (window.objectId == partner) return window;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final labelOpacity = widget.labelOpacity;
    final onMoveToDesk = widget.onMoveToDesk;
    final onCloseApp = widget.appWindowCount > 1 ? widget.onCloseApp : null;
    final buttons = [
      if (onCloseApp != null)
        _CloseAppButton(
          window: widget.window,
          count: widget.appWindowCount,
          onTap: () {
            if (!_leaving) onCloseApp(widget.window);
          },
        ),
      if (onMoveToDesk != null)
        _MoveToDeskButton(
          onTap: () {
            if (!_leaving) onMoveToDesk(widget.window);
          },
        ),
    ];
    final buttonsWidth =
        (onCloseApp == null ? 0.0 : _CloseAppButton.width) +
        (onMoveToDesk == null ? 0.0 : _MoveToDeskButton.size) +
        (buttons.length > 1 ? OverviewCardLabel.gap : 0.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: WindowBackdropMotion(
            motion: _pose,
            child: PosedWindow(
              pose: _pose,
              child: widget.over.isEmpty
                  ? WindowSurface(
                      window: widget.window,
                      contentPadding: const EdgeInsets.only(
                        top: ReferenceShellMetrics.statusBarHeight,
                      ),
                    )
                  : CardWindows(windows: [widget.window, ...widget.over]),
            ),
          ),
        ),
        if (labelOpacity != null)
          Positioned(
            left: 0,
            top: 0,
            width: widget.labelWidth,
            height: OverviewCardLabel.height,
            child: IgnorePointer(
              child: CompositedTranslation(
                translation: _pose.label,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                child: FadeTransition(
                  opacity: labelOpacity,
                  child: OverviewCardLabel(
                    window: widget.window,
                    partner: _splitPartner,
                    showsTitle: widget.appWindowCount > 1,
                    trailingSpace: buttons.isEmpty
                        ? 0
                        : buttonsWidth + OverviewCardLabel.gap,
                  ),
                ),
              ),
            ),
          ),
        _PoseHitRegion(
          pose: _pose,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!_leaving) widget.onOpen(widget.window);
            },
            onVerticalDragStart: _startDrag,
            onVerticalDragUpdate: _moveDrag,
            onVerticalDragEnd: _endDrag,
            onVerticalDragCancel: _settleBack,
            onLongPressStart: widget.onLiftMove == null ? null : _liftStart,
            onLongPressMoveUpdate: widget.onLiftMove == null ? null : _liftMove,
            onLongPressEnd: widget.onLiftMove == null ? null : _liftEnd,
            onLongPressCancel: widget.onLiftMove == null ? null : _liftCancel,
          ),
        ),
        if (labelOpacity != null && buttons.isNotEmpty)
          // The translation spans the deck, so a tap on a button is tested
          // where the label is drawn, not at the label's untranslated slot.
          Positioned.fill(
            child: CompositedTranslation(
              translation: _pose.label,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              child: ListenableBuilder(
                listenable: Listenable.merge([_pose, ?widget.coveredBy]),
                builder: (context, row) {
                  final visible = uncoveredLabelWidth(
                    card: _pose.value.rect,
                    cover: widget.coveredBy?.value,
                    labelWidth: widget.labelWidth,
                    ltr: Directionality.of(context) == TextDirection.ltr,
                  );
                  // Too little of the row shows: the buttons would sit
                  // beside another app's label.
                  final shown =
                      visible >=
                      OverviewCardLabel.iconSize +
                          OverviewCardLabel.gap +
                          buttonsWidth;
                  return Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        width: visible,
                        height: OverviewCardLabel.height,
                        child: Visibility(
                          visible: shown,
                          maintainState: true,
                          child: row!,
                        ),
                      ),
                    ],
                  );
                },
                child: FadeTransition(
                  opacity: labelOpacity,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, button) in buttons.indexed) ...[
                          if (index > 0)
                            const SizedBox(width: OverviewCardLabel.gap),
                          button,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The deck's pose of a card, thrown up and shrinking as it leaves.
class _CardPose extends ChangeNotifier implements ValueListenable<WindowPose> {
  _CardPose(this._base, this._throw) {
    _base.addListener(_changed);
    _throw.addListener(_changed);
    _changed();
  }

  ValueListenable<WindowPose> _base;
  final Animation<double> _throw;

  /// How far the card travels to leave the screen.
  double length = 1;

  /// Where a card lifted by a long press was moved; null when it rests.
  Offset? _lift;

  /// A lifted card shrinks this much.
  static const double _liftScale = 0.9;

  void lift(Offset? offset) {
    if (offset == _lift) return;
    _lift = offset;
    _changed();
  }

  /// Where the card's label goes: above its top edge.
  final label = ValueNotifier(Offset.zero);

  ValueListenable<WindowPose> get base => _base;
  set base(ValueListenable<WindowPose> value) {
    if (identical(value, _base)) return;
    _base.removeListener(_changed);
    _base = value..addListener(_changed);
    _changed();
  }

  @override
  WindowPose get value {
    final lifted = _liftedPose;
    if (lifted != null) return lifted;
    final pose = _base.value;
    final dy = _throw.value;
    if (dy == 0) return pose;
    final shrink =
        1 - _DeckCardState._dismissShrink * (-dy / length).clamp(0.0, 1.0);
    final rect = pose.rect;
    return WindowPose(
      Rect.fromCenter(
        center: rect.center.translate(0, dy),
        width: rect.width * shrink,
        height: rect.height * shrink,
      ),
      pose.radius * shrink,
      opacity: pose.opacity,
    );
  }

  WindowPose? get _liftedPose {
    final lift = _lift;
    if (lift == null) return null;
    final pose = _base.value;
    final rect = pose.rect;
    return WindowPose(
      Rect.fromCenter(
        center: rect.center + lift,
        width: rect.width * _liftScale,
        height: rect.height * _liftScale,
      ),
      pose.radius * _liftScale,
      opacity: pose.opacity,
    );
  }

  void _changed() {
    final rect = value.rect;
    label.value = Offset(
      rect.left,
      rect.top - OverviewCardLabel.gap - OverviewCardLabel.height,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _base.removeListener(_changed);
    _throw.removeListener(_changed);
    label.dispose();
    super.dispose();
  }
}

/// Takes touches only inside its [pose], in the screen's coordinates.
class _PoseHitRegion extends SingleChildRenderObjectWidget {
  const _PoseHitRegion({required this.pose, super.child});

  final ValueListenable<WindowPose> pose;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPoseHitRegion(pose);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPoseHitRegion).pose = pose;
  }
}

class _RenderPoseHitRegion extends RenderProxyBox {
  _RenderPoseHitRegion(this.pose);

  ValueListenable<WindowPose> pose;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final current = pose.value;
    if (current.opacity <= 0 ||
        !RRect.fromRectAndRadius(
          current.rect,
          Radius.circular(current.radius),
        ).contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

/// The sides of the screen a lifted card is dropped on to share the screen
/// with [target], the app in front; the one under the finger ([side], true
/// for the left) lights up.
class _SplitZones extends StatelessWidget {
  const _SplitZones({
    required this.target,
    required this.side,
    required this.zone,
  });

  final DenialWindow target;
  final bool? side;
  final double zone;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * zone;
        return Stack(
          children: [
            for (final left in [true, false])
              Positioned(
                left: left ? 16 : null,
                right: left ? null : 16,
                top: 64,
                bottom: 64,
                width: width - 24,
                child: _SplitZone(target: target, lit: side == left),
              ),
          ],
        );
      },
    );
  }
}

class _SplitZone extends ConsumerWidget {
  const _SplitZone({required this.target, required this.lit});

  final DenialWindow target;
  final bool lit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(target.appId));
    final name = application.name ?? localizedWindowTitle(context, target);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: lit ? const Color(0x59ffffff) : const Color(0x26ffffff),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: lit ? const Color(0xccffffff) : const Color(0x4dffffff),
          width: 2,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.recentsSplitWith(name),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xfff7f7f8),
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Closes every window of a card's app: a × and how many.
class _CloseAppButton extends ConsumerWidget {
  const _CloseAppButton({
    required this.window,
    required this.count,
    required this.onTap,
  });

  static const double width = 72;
  static const double height = 44;

  final DenialWindow window;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ShellTheme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E);
    final application = ref.watch(windowApplicationProvider(window.appId));
    final app = application.name ?? localizedWindowTitle(context, window);
    return Semantics(
      button: true,
      label: context.l10n.recentsCloseAppWindows(app, count),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: dark ? const Color(0x73000000) : const Color(0x8CFFFFFF),
            border: Border.all(
              color: dark ? const Color(0x24FFFFFF) : const Color(0x1F000000),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 20, color: ink),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where «Close all» sits in recents, its top edge in the layer's
/// coordinates: in the middle of the free band under the cards, and always
/// clear of the bottom gesture's area, so a tap on it is never taken for
/// the home swipe and a swipe never lands on it.
@visibleForTesting
double recentsCloseAllTop(DeckGeometry geometry) {
  const height = RecentsCloseAllButton.height;
  const clearance = RecentsCloseAllButton.gestureClearance;
  final gesture = ReferenceShellMetrics.gestureRect(geometry.size).top;
  final lowest = gesture - clearance - height;
  final centred = (geometry.card.bottom + gesture - clearance - height) / 2;
  return math.max(0.0, math.min(centred, lowest));
}

/// «Close all» at the bottom of recents: closes every app in it, as the
/// app switchers of Android and iPadOS offer. A pill sized for a finger,
/// dimmed while pressed.
@visibleForTesting
class RecentsCloseAllButton extends StatefulWidget {
  const RecentsCloseAllButton({super.key, required this.onTap});

  /// 48 logical pixels, about 10 mm on the tablet's panel at the shell's
  /// scale of 2.5: Material's touch target, above Apple's 44 points.
  static const double height = 48;
  static const double minWidth = 136;

  /// The least gap between the button and the bottom gesture's area.
  static const double gestureClearance = 16;

  final VoidCallback onTap;

  @override
  State<RecentsCloseAllButton> createState() => _RecentsCloseAllButtonState();
}

class _RecentsCloseAllButtonState extends State<RecentsCloseAllButton> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E);
    final label = context.l10n.recentsCloseAll;
    const radius = BorderRadius.all(
      Radius.circular(RecentsCloseAllButton.height / 2),
    );
    // Glass, as the shell's other panels over the wallpaper: a slice of the
    // shared frost under a lighter tint, no blur pass of its own.
    final glass = theme.effectivePanelOpacity < 1.0
        ? WindowBackdropCache.maybeOf(context)
        : null;
    final tint = switch ((dark, glass != null)) {
      (true, true) => const Color(0x40000000),
      (true, false) => const Color(0x73000000),
      (false, true) => const Color(0x59FFFFFF),
      (false, false) => const Color(0x8CFFFFFF),
    };
    final pill = Container(
      height: RecentsCloseAllButton.height,
      constraints: const BoxConstraints(
        minWidth: RecentsCloseAllButton.minWidth,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      // Sized by its label: an alignment here would stretch the pill across
      // the free width the layer gives it.
      decoration: BoxDecoration(
        borderRadius: radius,
        color: tint,
        border: Border.all(
          color: dark ? const Color(0x24FFFFFF) : const Color(0x1F000000),
        ),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _press(true),
          onTapCancel: () => _press(false),
          onTapUp: (_) => _press(false),
          onTap: widget.onTap,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.6 : 1,
            duration: const Duration(milliseconds: 90),
            child: glass == null
                ? pill
                : Stack(
                    children: [
                      Positioned.fill(
                        child: WindowBackdropSlice(
                          cache: glass,
                          borderRadius: radius,
                          glass: theme.windowGlassShading,
                        ),
                      ),
                      pill,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Sends a card's app to the monitor beside the phone.
class _MoveToDeskButton extends StatelessWidget {
  const _MoveToDeskButton({required this.onTap});

  static const double size = 40;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ShellTheme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1C1C1E);
    return Semantics(
      button: true,
      label: context.l10n.moveToMonitor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dark ? const Color(0x73000000) : const Color(0x8CFFFFFF),
            border: Border.all(
              color: dark ? const Color(0x24FFFFFF) : const Color(0x1F000000),
            ),
          ),
          child: Icon(Icons.desktop_windows_rounded, size: 20, color: ink),
        ),
      ),
    );
  }
}

/// How much of a recents card's label row, [labelWidth] wide from the
/// card's leading edge, is not under the card drawn over it ([cover]): the
/// newer card beside it overlaps it in landscape. The whole row without a
/// cover, or with one that does not reach into the row.
@visibleForTesting
double uncoveredLabelWidth({
  required Rect card,
  required WindowPose? cover,
  required double labelWidth,
  required bool ltr,
}) {
  final over = cover?.rect;
  if (over == null || over.isEmpty || (cover?.opacity ?? 0) <= 0) {
    return labelWidth;
  }
  final start = ltr ? card.left : card.right;
  final reach = ltr ? over.left - start : start - over.right;
  final behind = ltr ? over.right > start : over.left < start;
  if (!behind) return labelWidth;
  return (reach - OverviewCardLabel.gap).clamp(0.0, labelWidth);
}
