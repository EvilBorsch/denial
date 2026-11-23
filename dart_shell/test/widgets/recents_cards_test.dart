import 'package:denial_desktop/src/state/app_deck.dart';
import 'package:denial_desktop/src/widgets/overview/app_deck_layer.dart';
import 'package:denial_desktop/src/widgets/overview/overview_card_label.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart' show DenialBridge;
import 'package:denial_flutter_sdk/rendering.dart' show WindowPose;
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
  }) async {
    tester.view
      ..physicalSize = tabletView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final deck = AppDeck();
    addTearDown(deck.dispose);
    final calls = <String>[];
    deck.arrange([1, 2, 3], rowAt: 2);
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
              data: const ShellThemeData(
                transparencyMode: ShellTransparencyMode.off,
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(
                  children: [
                    AppDeckLayer(
                      deck: deck,
                      windows: [term, github, inbox],
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
