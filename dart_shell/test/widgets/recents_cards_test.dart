import 'package:denial_desktop/src/state/app_deck.dart';
import 'package:denial_desktop/src/state/reference_shell_metrics.dart';
import 'package:denial_desktop/src/widgets/overview/app_deck_layer.dart';
import 'package:denial_desktop/src/widgets/overview/overview_card_label.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart' show DenialBridge;
import 'package:denial_flutter_sdk/rendering.dart'
    show PosedWindow, WindowPose, WindowSurface;
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

DesktopApp _app(String id, String name) => DesktopApp(
  id: id,
  name: name,
  exec: id,
  desktopPath: '/usr/share/applications/$id.desktop',
  categories: const <String>[],
);

class _Grid extends HomeGridController {
  @override
  Future<HomeGridState> build() async => HomeGridState(
    slots: [
      HomeGridItem.app(_app('firefox', 'Firefox')),
      HomeGridItem.app(_app('org.gnome.Console', 'Terminal')),
    ],
  );
}

class _Bridge implements DenialBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final l10n = AppLocalizationsEn();
  final term = phoneWindow(
    1,
    'org.gnome.Console',
    title: 'pingv@pad: ~',
    texture: false,
  );
  final github = phoneWindow(2, 'firefox', title: 'GitHub', texture: false);
  final inbox = phoneWindow(3, 'firefox', title: 'Inbox', texture: false);

  Future<({AppDeck deck, List<String> calls})> recents(
    WidgetTester tester, {
    DenialWindow? front,
    List<DenialWindow>? windows,
    ShellThemeData theme = const ShellThemeData(
      transparencyMode: ShellTransparencyMode.off,
    ),
  }) async {
    tester.view
      ..physicalSize = tabletView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final deck = AppDeck();
    addTearDown(deck.dispose);
    final calls = <String>[];
    final open = windows ?? [term, github, inbox];
    deck.arrange([
      for (final window in open) window.objectId,
    ], rowAt: (open.length - 1).clamp(0, open.length).toDouble());
    deck.open.jump(1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          denialBridgeProvider.overrideWithValue(_Bridge()),
          homeGridControllerProvider.overrideWith(_Grid.new),
        ],
        child: DenialLocalizationScope(
          locale: const Locale('en'),
          child: MediaQuery(
            data: const MediaQueryData(size: tabletView),
            child: ShellTheme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(
                  children: [
                    AppDeckLayer(
                      deck: deck,
                      windows: open,
                      recents: true,
                      onPresentationChanged: (_) {},
                      onCloseRecents: () => calls.add('home'),
                      onLeaveWindow: (window) =>
                          calls.add('leave ${window.objectId}'),
                      onDismissWindow: (window) =>
                          calls.add('close ${window.objectId}'),
                      onOpenWindow: (window) =>
                          calls.add('open ${window.objectId}'),
                      splitTargetOf: (window) =>
                          front == null || window.objectId == front.objectId
                          ? null
                          : front,
                      onSplit: (window, {required onLeft}) => calls.add(
                        'split ${window.objectId} '
                        '${onLeft ? 'left' : 'right'}',
                      ),
                      onLift: () => calls.add('lift'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (deck: deck, calls: calls);
  }

  testWidgets('recents cards keep the shell roundness while apps sliding '
      'side by side follow the windows', (tester) async {
    WindowPose middle(AppDeck deck, {required double open, double row = 2}) =>
        deck.geometry.pose(2, open: open, row: row, homeward: 0, attached: 1);
    const card = 28 * 1.6;

    // The tablet's owner: shell roundness 1.6, square windows.
    final square = await recents(
      tester,
      theme: const ShellThemeData(
        transparencyMode: ShellTransparencyMode.off,
        cornerRadiusScale: 1.6,
      ),
    );
    expect(middle(square.deck, open: 1).radius, closeTo(card, 1e-9));
    expect(middle(square.deck, open: 0, row: 2.5).radius, 0);

    final rounded = await recents(
      tester,
      theme: const ShellThemeData(
        transparencyMode: ShellTransparencyMode.off,
        cornerRadiusScale: 1.6,
        roundedWindowFrame: true,
        windowCornerRadiusScale: 0.5,
      ),
    );
    expect(middle(rounded.deck, open: 1).radius, closeTo(card, 1e-9));
    expect(middle(rounded.deck, open: 0, row: 2.5).radius, 9);
    // At rest an app fills the screen with square corners either way.
    expect(middle(rounded.deck, open: 0).radius, 0);
  });

  testWidgets('cards of an app with several windows name their window', (
    tester,
  ) async {
    await recents(tester);
    expect(find.text('Firefox'), findsWidgets);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    // One window: the app's name alone, as before.
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('pingv@pad: ~'), findsNothing);
  });

  testWidgets('a close-all closes every window of the app', (tester) async {
    final shown = await recents(tester);
    final closeAll = find.bySemanticsLabel(
      l10n.recentsCloseAppWindows('Firefox', 2),
    );
    expect(closeAll, findsWidgets);
    expect(
      find.bySemanticsLabel(l10n.recentsCloseAppWindows('Terminal', 1)),
      findsNothing,
    );
    await tester.tap(closeAll.first);
    await tester.pump();
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shown.calls, containsAll(['leave 2', 'leave 3']));
    expect(shown.calls, containsAll(['close 2', 'close 3']));
    expect(shown.calls, isNot(contains('close 1')));
    expect(shown.calls, isNot(contains('open 2')));
  });

  testWidgets('Close all sits under the cards, clear of the home gesture', (
    tester,
  ) async {
    final shown = await recents(tester);
    final button = find.byType(RecentsCloseAllButton);
    expect(button, findsOneWidget);
    expect(find.text('Close all'), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.recentsCloseAll), findsOneWidget);
    final rect = tester.getRect(button);
    final gesture = ReferenceShellMetrics.gestureRect(tabletView);
    // Big enough for a finger, in the middle under the cards.
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.width, greaterThanOrEqualTo(RecentsCloseAllButton.minWidth));
    // A pill around its label, not a bar across the screen.
    expect(rect.width, lessThan(tabletView.width / 4));
    expect(rect.center.dx, closeTo(tabletView.width / 2, 0.5));
    expect(rect.top, greaterThan(shown.deck.geometry.card.bottom));
    expect(
      rect.bottom,
      lessThanOrEqualTo(gesture.top - RecentsCloseAllButton.gestureClearance),
    );
  });

  test('Close all keeps clear of the cards and the gesture upright too', () {
    for (final size in [tabletView, tabletView.flipped]) {
      final geometry = DeckGeometry(
        size: size,
        padding: EdgeInsets.zero,
        windowRadius: 20,
        switchRadius: 18,
        ltr: true,
      );
      final top = recentsCloseAllTop(geometry);
      final gesture = ReferenceShellMetrics.gestureRect(size);
      expect(top, greaterThan(geometry.card.bottom));
      expect(
        top + RecentsCloseAllButton.height,
        lessThanOrEqualTo(gesture.top - RecentsCloseAllButton.gestureClearance),
      );
    }
  });

  testWidgets('Close all shows only when there is something to close', (
    tester,
  ) async {
    await recents(tester, windows: const []);
    expect(find.byType(RecentsCloseAllButton), findsNothing);
    expect(find.text(l10n.overviewNoWindows), findsOneWidget);
  });

  testWidgets('Close all sends every card away, closing each app, and goes '
      'home', (tester) async {
    final shown = await recents(tester);
    await tester.tap(find.byType(RecentsCloseAllButton));
    // Every card leaves the row, and Recents goes home at once.
    expect(shown.calls, containsAll(['leave 1', 'leave 2', 'leave 3']));
    expect(shown.calls.last, 'home');
    expect(shown.calls.where((call) => call.startsWith('close')), isEmpty);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    // Each app closes once its card is gone, as a swiped card's does.
    expect(shown.calls, containsAll(['close 1', 'close 2', 'close 3']));
    expect(shown.calls.where((call) => call == 'home'), hasLength(1));
    expect(shown.calls.where((call) => call.startsWith('open')), isEmpty);
  });

  testWidgets('a card sent away by Close all flies straight up', (
    tester,
  ) async {
    await recents(tester, windows: [term]);
    // Where the card is drawn: its window, as its pose places it.
    final window = find.descendant(
      of: find.byType(PosedWindow),
      matching: find.byType(WindowSurface),
    );
    Rect card() => tester.getRect(window);
    final before = card();
    await tester.tap(find.byType(RecentsCloseAllButton));
    // The frame that starts the throw draws the card where it was.
    await tester.pump();
    var previous = card();
    var moved = 0;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (window.evaluate().isEmpty) break;
      final now = card();
      // It moves on every frame, up, and keeps its place across.
      expect(now.center.dy, lessThan(previous.center.dy));
      expect(now.center.dx, closeTo(before.center.dx, 0.5));
      previous = now;
      moved++;
    }
    expect(moved, greaterThan(3));
  });

  testWidgets('a long-pressed card dropped on a side shares the screen', (
    tester,
  ) async {
    final shown = await recents(tester, front: term);
    // The card in the middle: Inbox.
    final gesture = await tester.startGesture(const Offset(678, 480));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(shown.calls, ['lift']);
    expect(find.text(l10n.recentsSplitWith('Terminal')), findsNWidgets(2));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(shown.calls, ['lift', 'split 3 right']);
    expect(find.text(l10n.recentsSplitWith('Terminal')), findsNothing);
  });

  testWidgets('dropped in the middle, it goes back', (tester) async {
    final shown = await recents(tester, front: term);
    final gesture = await tester.startGesture(const Offset(678, 480));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(shown.calls, ['lift']);
  });

  testWidgets('the card of the app in front cannot be lifted', (tester) async {
    final shown = await recents(tester, front: inbox);
    final gesture = await tester.startGesture(const Offset(678, 480));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text(l10n.recentsSplitWith('Firefox')), findsNothing);
    await gesture.up();
    await tester.pump();
    // Held and let go, it is a tap, as before.
    expect(shown.calls, ['open 3']);
  });

  group('a card covered by the newer one beside it', () {
    const card = Rect.fromLTWH(100, 200, 400, 300);

    test('keeps its whole label row without a card over it', () {
      expect(
        uncoveredLabelWidth(
          card: card,
          cover: null,
          labelWidth: 400,
          ltr: true,
        ),
        400,
      );
      // The newer card lies on the other side, or past the row's end.
      for (final rect in [
        const Rect.fromLTWH(-350, 200, 400, 300),
        const Rect.fromLTWH(520, 200, 400, 300),
      ]) {
        expect(
          uncoveredLabelWidth(
            card: card,
            cover: WindowPose(rect, 20),
            labelWidth: 400,
            ltr: true,
          ),
          400,
        );
      }
    });

    test('keeps its buttons to the part of the row left uncovered', () {
      // Overlapped from x = 440: the row ends a gap before it.
      expect(
        uncoveredLabelWidth(
          card: card,
          cover: const WindowPose(Rect.fromLTWH(440, 200, 400, 300), 20),
          labelWidth: 400,
          ltr: true,
        ),
        340 - OverviewCardLabel.gap,
      );
      // Mostly covered: hardly any of the row shows.
      expect(
        uncoveredLabelWidth(
          card: card,
          cover: const WindowPose(Rect.fromLTWH(110, 200, 400, 300), 20),
          labelWidth: 400,
          ltr: true,
        ),
        0,
      );
    });

    test('mirrors right to left, and ignores a hidden card', () {
      expect(
        uncoveredLabelWidth(
          card: card,
          cover: const WindowPose(Rect.fromLTWH(-200, 200, 400, 300), 20),
          labelWidth: 400,
          ltr: false,
        ),
        300 - OverviewCardLabel.gap,
      );
      expect(
        uncoveredLabelWidth(
          card: card,
          cover: WindowPose.hidden,
          labelWidth: 400,
          ltr: true,
        ),
        400,
      );
    });
  });
}
