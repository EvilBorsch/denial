import 'package:denial_desktop/src/features/mobile/mobile_window_layers.dart';
import 'package:denial_desktop/src/widgets/overview/app_deck_layer.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

/// «Close all» in the tablet's Recents, with the shell's own controller over
/// a bridge that records what the shell asks of the compositor.
void main() {
  final term = phoneWindow(1, 'org.gnome.Console', texture: false);
  final github = phoneWindow(2, 'firefox', title: 'GitHub', texture: false);
  final inbox = phoneWindow(3, 'firefox', title: 'Inbox', texture: false);
  // A Split View pair: one card, two apps.
  final (editor, calculator) = splitWindows(
    (5, 'org.gnome.TextEditor'),
    (6, 'org.gnome.Calculator'),
    texture: false,
  );
  // An Android app as Droidloom shows it: its package is its app id.
  final android = phoneWindow(7, 'org.fdroid.fdroid', texture: false);
  final everything = [term, github, inbox, editor, calculator, android];

  Future<MobileShellHarness> recents(
    WidgetTester tester,
    List<DenialWindow> windows,
  ) async {
    tester.view
      ..physicalSize = tabletView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = MobileShellHarness();
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: shell.container,
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
                  children: [MobileAppDeckLayer(onPresentationChanged: (_) {})],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await shell.publish(tester, windows);
    for (final window in windows) {
      if (window.objectId == calculator.objectId) continue;
      shell.controller.focusWindow(window);
      await tester.pump();
    }
    await shell.settle(tester);
    shell.controller.openOverview();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    shell.bridge.requests.clear();
    return shell;
  }

  Future<void> frames(WidgetTester tester, [int count = 120]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
  }

  testWidgets(
    'Close all closes every window: grouped ones, both apps of a Split View '
    'pair and Android apps, then Recents goes home',
    (tester) async {
      final shell = await recents(tester, everything);
      final controller = shell.controller;
      expect(controller.state.overviewVisible, isTrue);
      expect(controller.deck.order, hasLength(5));
      expect(find.byType(RecentsCloseAllButton), findsOneWidget);

      await tester.tap(find.byType(RecentsCloseAllButton));
      await tester.pump();
      // Recents goes home at once, the cards flying out over it.
      expect(controller.state.overviewVisible, isFalse);
      expect(controller.deck.order, isEmpty);
      expect(controller.deck.leaving, isNotEmpty);
      expect(controller.deck.presenting.value, isTrue);

      await frames(tester);
      final closes = [
        for (final request in shell.bridge.requests)
          if (request.startsWith('close ')) request,
      ];
      expect(
        closes,
        unorderedEquals([
          'close 1',
          'close 2',
          'close 3',
          'close 5',
          'close 6',
          'close 7',
        ]),
      );
      // Gone: nothing is drawn any more, and home shows.
      expect(controller.deck.leaving, isEmpty);
      expect(controller.deck.presenting.value, isFalse);
      expect(controller.state.foregroundWindow, isNull);
      expect(find.byType(RecentsCloseAllButton), findsNothing);
      await shell.finish(tester);
    },
  );

  testWidgets('Close all asks each app to close and kills none', (
    tester,
  ) async {
    final shell = await recents(tester, everything);
    await tester.tap(find.byType(RecentsCloseAllButton));
    await frames(tester);
    // The compositor hears a close request per window, as from the
    // window's own close button: nothing else but the app in front going to
    // the background as home comes.
    final requests = shell.bridge.requests;
    for (final window in everything) {
      expect(
        requests.where((request) => request == 'close ${window.objectId}'),
        hasLength(1),
      );
    }
    expect(
      requests.where(
        (request) =>
            !request.startsWith('close ') && !request.startsWith('minimize '),
      ),
      isEmpty,
    );
    // The windows stay until their apps close them.
    expect(shell.controller.state.openAppWindows, hasLength(6));
    await shell.finish(tester);
  });

  testWidgets('the button shows only while there is something to close', (
    tester,
  ) async {
    final shell = await recents(tester, [term]);
    expect(find.byType(RecentsCloseAllButton), findsOneWidget);
    // The last card swiped away: Recents goes home without the button.
    shell.controller
      ..leaveRecents(term)
      ..dismissFromRecents(term);
    await tester.pump();
    expect(find.byType(RecentsCloseAllButton), findsNothing);
    await frames(tester);
    // Recents with no apps at all.
    await shell.publish(tester, const []);
    shell.controller.openOverview();
    await frames(tester, 60);
    expect(shell.controller.state.overviewVisible, isTrue);
    expect(find.byType(RecentsCloseAllButton), findsNothing);
    await shell.finish(tester);
  });

  testWidgets(
    'an app that asks to save stays open and comes to the front with its '
    'question',
    (tester) async {
      final unsaved = phoneWindow(8, 'org.gnome.TextEditor', texture: false);
      final shell = await recents(tester, [term, github, unsaved]);
      await tester.tap(find.byType(RecentsCloseAllButton));
      await frames(tester);
      expect(shell.bridge.requests, contains('close 8'));
      // Every app closes but the editor, which asks in its window whether to
      // save. Home shows meanwhile.
      await shell.publish(tester, [unsaved]);
      expect(shell.controller.state.foregroundWindow, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(shell.controller.state.foregroundObjectId, 8);
      expect(shell.bridge.requests, contains('focus 8'));
      // Back in Recents, not hidden away as a closed app.
      expect(shell.controller.deck.order, [8]);
      await shell.finish(tester);
    },
  );
}
