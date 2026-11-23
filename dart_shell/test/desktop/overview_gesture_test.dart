import 'package:denial_desktop/src/desktop/desktop_overview_motion.dart';
import 'package:denial_desktop/src/desktop/retained_animated_positioned.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

DenialShellGesture _gesture(
  DenialShellGestureKind kind,
  DenialShellGesturePhase phase, {
  double progress = 0.0,
  double velocity = 0.0,
  bool committed = false,
}) => DenialShellGesture(
  kind: kind,
  phase: phase,
  progress: progress,
  velocity: velocity,
  committed: committed,
);

const _up = DenialShellGestureKind.up;
const _down = DenialShellGestureKind.down;
const _begin = DenialShellGesturePhase.begin;
const _update = DenialShellGesturePhase.update;
const _end = DenialShellGesturePhase.end;
const _cancel = DenialShellGesturePhase.cancel;

/// The overview as the shell would run it: a view that opens and closes,
/// and a scene that closes the motion when the view closes.
class _Shell {
  _Shell() {
    gestures = DesktopOverviewGestures(
      motion: motion,
      currentView: () => view,
      openView: (view, monitorId) {
        opened.add((view, monitorId));
        if (!canOpen) {
          return false;
        }
        this.view = view;
        return true;
      },
      dismiss: () {
        dismissed += 1;
        view = null;
        motion.close();
      },
    );
  }

  final motion = DesktopOverviewMotion();
  late final DesktopOverviewGestures gestures;
  DesktopOverviewGestureView? view;
  bool canOpen = true;
  final opened = <(DesktopOverviewGestureView, int?)>[];
  var dismissed = 0;

  void dispose() => motion.dispose();
}

void main() {
  group('a gesture session', () {
    test('up opens the overview and down the app windows', () {
      final up = DesktopOverviewGestureSession.begin(
        kind: _up,
        open: null,
        presence: 0.0,
      )!;
      expect(up.view, DesktopOverviewGestureView.overview);
      expect(up.opening, isTrue);
      final down = DesktopOverviewGestureSession.begin(
        kind: _down,
        open: null,
        presence: 0.0,
      )!;
      expect(down.view, DesktopOverviewGestureView.appWindows);
      expect(down.opening, isTrue);
    });

    test('the opposite direction closes an open view, the same does not', () {
      final closeOverview = DesktopOverviewGestureSession.begin(
        kind: _down,
        open: DesktopOverviewGestureView.overview,
        presence: 1.0,
      )!;
      expect(closeOverview.view, DesktopOverviewGestureView.overview);
      expect(closeOverview.opening, isFalse);
      final closeAppWindows = DesktopOverviewGestureSession.begin(
        kind: _up,
        open: DesktopOverviewGestureView.appWindows,
        presence: 1.0,
      )!;
      expect(closeAppWindows.view, DesktopOverviewGestureView.appWindows);
      expect(closeAppWindows.opening, isFalse);

      expect(
        DesktopOverviewGestureSession.begin(
          kind: _up,
          open: DesktopOverviewGestureView.overview,
          presence: 1.0,
        ),
        isNull,
      );
      expect(
        DesktopOverviewGestureSession.begin(
          kind: _down,
          open: DesktopOverviewGestureView.appWindows,
          presence: 1.0,
        ),
        isNull,
      );
    });

    test('the fingers set the openness from where it was', () {
      const opening = DesktopOverviewGestureSession(
        view: DesktopOverviewGestureView.overview,
        opening: true,
        from: 0.2,
      );
      expect(opening.presenceAt(0.0), 0.2);
      expect(opening.presenceAt(0.5), closeTo(0.6, 1e-9));
      expect(opening.presenceAt(1.0), 1.0);
      // Progress may leave 0..1; the overview stays at its ends.
      expect(opening.presenceAt(1.4), 1.0);
      expect(opening.presenceAt(-0.3), 0.0);
      expect(opening.presenceVelocity(2.0), closeTo(1.6, 1e-9));

      const closing = DesktopOverviewGestureSession(
        view: DesktopOverviewGestureView.overview,
        opening: false,
        from: 1.0,
      );
      expect(closing.presenceAt(0.0), 1.0);
      expect(closing.presenceAt(0.25), 0.75);
      expect(closing.presenceAt(1.0), 0.0);
      expect(closing.presenceVelocity(2.0), -2.0);
    });

    test('it ends open when an opening gesture commits', () {
      const opening = DesktopOverviewGestureSession(
        view: DesktopOverviewGestureView.overview,
        opening: true,
        from: 0.0,
      );
      expect(opening.endsOpen(_end, committed: true), isTrue);
      expect(opening.endsOpen(_end, committed: false), isFalse);
      expect(opening.endsOpen(_cancel, committed: true), isFalse);
      const closing = DesktopOverviewGestureSession(
        view: DesktopOverviewGestureView.appWindows,
        opening: false,
        from: 1.0,
      );
      expect(closing.endsOpen(_end, committed: true), isFalse);
      expect(closing.endsOpen(_end, committed: false), isTrue);
      expect(closing.endsOpen(_cancel, committed: false), isTrue);
    });
  });

  group('the overview follows the fingers', () {
    testWidgets('up, committed: opens with the fingers and springs open', (
      tester,
    ) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      shell.gestures.handle(_gesture(_up, _begin), monitorId: 3);
      expect(shell.opened, [(DesktopOverviewGestureView.overview, 3)]);
      expect(shell.view, DesktopOverviewGestureView.overview);
      expect(shell.motion.held, isTrue);
      expect(shell.motion.presence.value, 0.0);

      shell.gestures.handle(_gesture(_up, _update, progress: 0.3));
      expect(shell.motion.presence.value, closeTo(0.3, 1e-9));
      shell.gestures.handle(_gesture(_up, _update, progress: 0.55));
      expect(shell.motion.presence.value, closeTo(0.55, 1e-9));
      // Frames do not move a held overview.
      await tester.pump(const Duration(milliseconds: 100));
      expect(shell.motion.presence.value, closeTo(0.55, 1e-9));

      shell.gestures.handle(
        _gesture(_up, _end, progress: 0.6, velocity: 1.5, committed: true),
      );
      expect(shell.motion.held, isFalse);
      expect(shell.gestures.active, isFalse);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(shell.motion.presence.value, greaterThan(0.55));
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 1.0);
      expect(shell.view, DesktopOverviewGestureView.overview);
      expect(shell.dismissed, 0);
    });

    testWidgets('up, not committed or cancelled: returns to the desktop', (
      tester,
    ) async {
      for (final phase in [_end, _cancel]) {
        final shell = _Shell();
        addTearDown(shell.dispose);
        shell.gestures.handle(_gesture(_up, _begin));
        shell.gestures.handle(_gesture(_up, _update, progress: 0.2));
        shell.gestures.handle(_gesture(_up, phase, progress: 0.2));
        expect(shell.dismissed, 1, reason: '$phase');
        expect(shell.view, isNull);
        await tester.pumpAndSettle();
        expect(shell.motion.presence.value, 0.0);
      }
    });

    testWidgets('down closes the open overview with the fingers', (
      tester,
    ) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      shell.view = DesktopOverviewGestureView.overview;
      shell.motion.open(animate: false);

      shell.gestures.handle(_gesture(_down, _begin));
      expect(shell.opened, isEmpty);
      expect(shell.motion.held, isTrue);
      shell.gestures.handle(_gesture(_down, _update, progress: 0.4));
      expect(shell.motion.presence.value, closeTo(0.6, 1e-9));

      // Let go before the gesture commits: the overview springs back open.
      shell.gestures.handle(_gesture(_down, _end, progress: 0.4));
      expect(shell.dismissed, 0);
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 1.0);

      // Again, committed this time: it closes from where the fingers left it.
      shell.gestures.handle(_gesture(_down, _begin));
      shell.gestures.handle(_gesture(_down, _update, progress: 0.7));
      expect(shell.motion.presence.value, closeTo(0.3, 1e-9));
      shell.gestures.handle(
        _gesture(_down, _end, progress: 0.7, velocity: 2, committed: true),
      );
      expect(shell.dismissed, 1);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(shell.motion.presence.value, lessThan(0.3));
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 0.0);
    });

    testWidgets('down opens the app windows; up closes them; a cancel keeps '
        'them', (tester) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      shell.gestures.handle(_gesture(_down, _begin));
      expect(shell.opened.single.$1, DesktopOverviewGestureView.appWindows);
      shell.gestures.handle(_gesture(_down, _update, progress: 0.8));
      shell.gestures.handle(_gesture(_down, _end, committed: true));
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 1.0);

      // Down again does nothing to the open app windows.
      shell.gestures.handle(_gesture(_down, _begin));
      expect(shell.gestures.active, isFalse);
      expect(shell.motion.held, isFalse);

      shell.gestures.handle(_gesture(_up, _begin));
      shell.gestures.handle(_gesture(_up, _update, progress: 0.5));
      shell.gestures.handle(_gesture(_up, _cancel));
      expect(shell.dismissed, 0);
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 1.0);

      shell.gestures.handle(_gesture(_up, _begin));
      shell.gestures.handle(_gesture(_up, _end, committed: true));
      expect(shell.dismissed, 1);
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 0.0);
    });

    testWidgets('a gesture with nothing to open leaves the desktop alone', (
      tester,
    ) async {
      final shell = _Shell()..canOpen = false;
      addTearDown(shell.dispose);
      shell.gestures.handle(_gesture(_up, _begin));
      expect(shell.gestures.active, isFalse);
      expect(shell.motion.held, isFalse);
      shell.gestures.handle(_gesture(_up, _update, progress: 0.5));
      shell.gestures.handle(_gesture(_up, _end, committed: true));
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 0.0);
      expect(shell.dismissed, 0);
    });

    testWidgets('a key takes over from a gesture and opens fully', (
      tester,
    ) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      shell.gestures.handle(_gesture(_up, _begin));
      shell.gestures.handle(_gesture(_up, _update, progress: 0.4));
      shell.gestures.interrupt();
      expect(shell.motion.held, isFalse);
      await tester.pumpAndSettle();
      expect(shell.motion.presence.value, 1.0);
      // The fingers' later events no longer move it.
      shell.gestures.handle(_gesture(_up, _update, progress: 0.1));
      shell.gestures.handle(_gesture(_up, _end));
      expect(shell.motion.presence.value, 1.0);
      expect(shell.dismissed, 0);
    });
  });

  group('a driven window', () {
    const home = Rect.fromLTWH(0, 0, 400, 300);
    const target = Rect.fromLTWH(200, 100, 100, 75);
    const childKey = ValueKey<String>('window');

    Widget scene({Animation<double>? driver, Rect rect = target}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              RetainedAnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                rect: rect,
                layoutRect: home,
                driver: driver,
                driverHome: driver == null ? null : home,
                child: const SizedBox(key: childKey),
              ),
            ],
          ),
        );

    void expectRect(WidgetTester tester, Rect expected) {
      final actual = tester.getRect(find.byKey(childKey));
      expect(actual.left, closeTo(expected.left, 1e-6));
      expect(actual.top, closeTo(expected.top, 1e-6));
      expect(actual.right, closeTo(expected.right, 1e-6));
      expect(actual.bottom, closeTo(expected.bottom, 1e-6));
    }

    testWidgets('it is drawn between home and its place as the driver moves', (
      tester,
    ) async {
      final controller = AnimationController(vsync: const TestVSync());
      addTearDown(controller.dispose);
      await tester.pumpWidget(scene(driver: controller));
      expectRect(tester, home);

      controller.value = 0.5;
      await tester.pump();
      expectRect(tester, Rect.lerp(home, target, 0.5)!);
      controller.value = 1.0;
      await tester.pump();
      expectRect(tester, target);
    });

    testWidgets('a new place eases in while driven', (tester) async {
      final controller = AnimationController(vsync: const TestVSync());
      addTearDown(controller.dispose);
      controller.value = 1.0;
      await tester.pumpWidget(scene(driver: controller));
      const moved = Rect.fromLTWH(20, 30, 100, 75);
      await tester.pumpWidget(scene(driver: controller, rect: moved));
      await tester.pump(const Duration(milliseconds: 100));
      final halfway = tester.getRect(find.byKey(childKey));
      expect(halfway.left, lessThan(target.left));
      expect(halfway.left, greaterThan(moved.left));
      await tester.pumpAndSettle();
      expectRect(tester, moved);
    });

    testWidgets('without the driver it moves on from where it was drawn', (
      tester,
    ) async {
      final controller = AnimationController(vsync: const TestVSync());
      addTearDown(controller.dispose);
      controller.value = 0.4;
      await tester.pumpWidget(scene(driver: controller));
      final presented = Rect.lerp(home, target, 0.4)!;
      expectRect(tester, presented);

      // The overview closes: the window eases home from where it was.
      await tester.pumpWidget(scene(rect: home));
      expectRect(tester, presented);
      await tester.pump(const Duration(milliseconds: 100));
      final between = tester.getRect(find.byKey(childKey));
      expect(between.left, lessThan(presented.left));
      expect(between.left, greaterThan(home.left));
      await tester.pumpAndSettle();
      expectRect(tester, home);
    });
  });
}
