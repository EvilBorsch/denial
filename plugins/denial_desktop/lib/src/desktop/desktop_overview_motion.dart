import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/platform.dart'
    show DenialShellGesture, DenialShellGestureKind, DenialShellGesturePhase;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_workspace.dart';

/// How far the desktop overview is open: 0 shows the desktop, 1 the
/// overview.
///
/// One value moves the whole overview of the managed layouts and the app
/// windows: every window between its place on the desktop and its place in
/// the overview, the cards around them, the dimmed background and the
/// overview's chrome. A gesture holds it and moves it with the fingers; a
/// key, or the end of a gesture, lets a spring carry it the rest of the way
/// with the fingers' speed. Closing returns over the overview's closing time
/// and curve, which every window that leaves the overview shares.
class DesktopOverviewMotion {
  DesktopOverviewMotion({TickerProvider vsync = const _Tickers()})
    : _controller = AnimationController.unbounded(vsync: vsync);

  final AnimationController _controller;

  /// The overview's openness, kept to 0..1 for everything it moves.
  late final Animation<double> presence = _UnitPresence(_controller);

  /// The unclamped value, as a gesture or a spring left it.
  double get value => _controller.value;

  /// Whether a gesture holds the overview where its fingers are.
  bool get held => _held;
  bool _held = false;

  bool get isAnimating => _controller.isAnimating;

  /// A gesture takes the overview, at [at] or where it is now.
  void hold([double? at]) {
    _controller.stop();
    _held = true;
    if (at != null) {
      _controller.value = at;
    }
  }

  /// Moves a held overview with the fingers.
  void track(double value) {
    if (_held && value.isFinite) {
      _controller.value = value;
    }
  }

  /// Opens from wherever the overview is, carrying [velocity] (presence per
  /// second) into a spring.
  TickerFuture open({double velocity = 0.0, bool animate = true}) {
    _held = false;
    if (!animate) {
      _controller.value = 1.0;
      return TickerFuture.complete();
    }
    return springTo(
      _controller,
      1.0,
      velocity: velocity.isFinite ? velocity : 0.0,
      telemetryLabel: 'desktop overview',
    );
  }

  /// Returns to the desktop from wherever the overview is.
  TickerFuture close({bool animate = true}) {
    _held = false;
    if (!animate || _controller.value <= 0.0) {
      _controller.value = 0.0;
      return TickerFuture.complete();
    }
    return _controller.animateBack(
      0.0,
      duration: Motion.overviewClose,
      curve: Motion.overviewExitCurve,
    );
  }

  void addListener(VoidCallback listener) => _controller.addListener(listener);
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  void dispose() => _controller.dispose();
}

final desktopOverviewMotionProvider = Provider<DesktopOverviewMotion>((ref) {
  final motion = DesktopOverviewMotion();
  ref.onDispose(motion.dispose);
  return motion;
});

/// Whether [overview] moves with [DesktopOverviewMotion]: the managed
/// layouts' workspace and screen cards, and the app windows of one app. The
/// stacking spread keeps its windows' own easing.
bool desktopOverviewFollowsMotion(DesktopOverviewState? overview) =>
    overview != null &&
    (overview.workspaces != null || overview.appWindows != null);

/// Where a window of [overview] rests when the overview is closed, so that
/// the motion carries it between there and [frame], its overview place.
///
/// Card overviews put it where the camera, zoomed into the current card,
/// puts it: on the screen for the current card's windows, beside the screen
/// for the others. That is where the cards behind them go too. The app
/// windows put it at its own place on the desktop, [desktopFrame].
Rect? desktopOverviewHome({
  required DesktopOverviewState overview,
  required DesktopWorkspaceState desktop,
  required Rect frame,
  required Rect desktopFrame,
}) {
  final workspaces = overview.workspaces;
  if (workspaces != null) {
    final camera =
        workspaces.screens?.currentCardId ??
        desktop.activeWorkspaceFor(overview.monitorId);
    return workspaces.cameraRect(frame, camera);
  }
  if (overview.appWindows != null) {
    return desktopFrame;
  }
  return null;
}

/// The two views a three-finger (or middle-button) gesture opens.
enum DesktopOverviewGestureView { overview, appWindows }

/// What one shell gesture does to the overview, and where its fingers put
/// it.
///
/// Up opens the overview and down the app windows, as the fingers move;
/// with one of them open, the opposite direction closes it, also with the
/// fingers. The same direction again does nothing.
@immutable
class DesktopOverviewGestureSession {
  const DesktopOverviewGestureSession({
    required this.view,
    required this.opening,
    required this.from,
  });

  /// Decides what a gesture of [kind] that begins now does, with [open] the
  /// view open now (null for none) and [presence] the overview's openness.
  /// Null when it does nothing.
  static DesktopOverviewGestureSession? begin({
    required DenialShellGestureKind kind,
    required DesktopOverviewGestureView? open,
    required double presence,
  }) {
    final from = presence.isFinite ? presence.clamp(0.0, 1.0).toDouble() : 0.0;
    if (open == null) {
      return DesktopOverviewGestureSession(
        view: kind == DenialShellGestureKind.up
            ? DesktopOverviewGestureView.overview
            : DesktopOverviewGestureView.appWindows,
        opening: true,
        from: from,
      );
    }
    final closes = switch (open) {
      DesktopOverviewGestureView.overview =>
        kind == DenialShellGestureKind.down,
      DesktopOverviewGestureView.appWindows =>
        kind == DenialShellGestureKind.up,
    };
    return closes
        ? DesktopOverviewGestureSession(view: open, opening: false, from: from)
        : null;
  }

  final DesktopOverviewGestureView view;

  /// Opening [view], or closing it.
  final bool opening;

  /// The overview's openness when the gesture began.
  final double from;

  /// The openness for the fingers' [progress]: 0 where they began, 1 a full
  /// gesture. Past either end the view stays where it ends.
  double presenceAt(double progress) {
    final travel = progress.isFinite ? progress : 0.0;
    final value = opening
        ? from + (1.0 - from) * travel
        : from * (1.0 - travel);
    return value.clamp(0.0, 1.0).toDouble();
  }

  /// Openness per second for the fingers' [velocity] (progress per second).
  double presenceVelocity(double velocity) {
    final speed = velocity.isFinite ? velocity : 0.0;
    return opening ? (1.0 - from) * speed : -from * speed;
  }

  /// Whether the view is open after the gesture's [phase] ended with
  /// [committed] (the gesture did what it set out to do).
  bool endsOpen(DenialShellGesturePhase phase, {required bool committed}) {
    final done = phase == DenialShellGesturePhase.end && committed;
    return opening ? done : !done;
  }
}

/// Follows the shell gestures deniald sends for three fingers up and down
/// (and a middle-button drag): the overview and the app windows open and
/// close with the fingers, and settle open or closed when they lift.
class DesktopOverviewGestures {
  DesktopOverviewGestures({
    required this.motion,
    required this.currentView,
    required this.openView,
    required this.dismiss,
  });

  final DesktopOverviewMotion motion;

  /// The view open now, or null.
  final DesktopOverviewGestureView? Function() currentView;

  /// Opens [view] on the output of the monitor the gesture came from (null
  /// for the focused one); false when there is nothing to show.
  final bool Function(DesktopOverviewGestureView view, int? monitorId) openView;

  /// Closes the open view; the scene then closes the motion.
  final VoidCallback dismiss;

  DesktopOverviewGestureSession? _session;

  /// Whether a gesture is moving the overview now.
  bool get active => _session != null;

  /// Forgets the gesture in progress, as a key takes over the overview.
  void interrupt() {
    if (_session == null) {
      return;
    }
    _session = null;
    if (currentView() != null && motion.held) {
      motion.open();
    }
  }

  void handle(
    DenialShellGesture gesture, {
    int? monitorId,
    bool reduceMotion = false,
  }) {
    switch (gesture.phase) {
      case DenialShellGesturePhase.begin:
        _begin(gesture, monitorId);
      case DenialShellGesturePhase.update:
        final session = _session;
        if (session != null) {
          motion.track(session.presenceAt(gesture.progress));
        }
      case DenialShellGesturePhase.end:
      case DenialShellGesturePhase.cancel:
        final session = _session;
        _session = null;
        if (session == null) {
          return;
        }
        if (currentView() == null) {
          // The view closed under the fingers; its close moved the motion.
          if (motion.held) {
            motion.close(animate: !reduceMotion);
          }
          return;
        }
        if (session.endsOpen(gesture.phase, committed: gesture.committed)) {
          motion.open(
            velocity: session.presenceVelocity(gesture.velocity),
            animate: !reduceMotion,
          );
        } else {
          dismiss();
        }
    }
  }

  void _begin(DenialShellGesture gesture, int? monitorId) {
    _session = null;
    final open = currentView();
    final session = DesktopOverviewGestureSession.begin(
      kind: gesture.kind,
      open: open,
      presence: motion.value,
    );
    if (session == null) {
      return;
    }
    motion.hold(session.presenceAt(gesture.progress));
    if (session.opening && !openView(session.view, monitorId)) {
      motion.close(animate: false);
      return;
    }
    _session = session;
  }
}

/// The overview's openness, clamped to the range it is drawn in.
class _UnitPresence extends Animation<double>
    with AnimationWithParentMixin<double> {
  _UnitPresence(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => parent.value.clamp(0.0, 1.0).toDouble();
}

/// Tickers that run whatever [TickerMode] says: the motion belongs to the
/// whole desktop scene, not to one subtree.
class _Tickers implements TickerProvider {
  const _Tickers();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
