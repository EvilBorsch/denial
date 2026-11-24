import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

void main() {
  final term = phoneWindow(1, 'org.gnome.Console');
  final firefox = phoneWindow(2, 'firefox', title: 'GitHub');
  final firefox2 = phoneWindow(3, 'firefox', title: 'Inbox');
  final files = phoneWindow(4, 'org.gnome.Nautilus');

  Future<MobileShellHarness> shellWith(WidgetTester tester) async {
    final shell = MobileShellHarness();
    addTearDown(shell.dispose);
    await shell.publish(tester, [term, firefox, firefox2, files]);
    // In front in turn: Firefox, Files, the terminal, Firefox's second
    // window.
    for (final window in [firefox, files, term, firefox2]) {
      shell.controller.focusWindow(window);
      await tester.pump();
    }
    await shell.settle(tester);
    return shell;
  }

  testWidgets('the home pill keeps the order the apps were in front in', (
    tester,
  ) async {
    final shell = await shellWith(tester);
    // The app used before is one swipe away.
    expect(shell.controller.deck.order, [2, 4, 1, 3]);
    expect(shell.controller.deck.row.target, 3);
    await shell.finish(tester);
  });

  testWidgets('Recents puts the windows of one app side by side', (
    tester,
  ) async {
    final shell = await shellWith(tester);
    shell.controller.openOverview();
    await tester.pump();
    // Files, the terminal, then both Firefox windows, the one in front
    // last.
    expect(shell.controller.deck.order, [4, 1, 2, 3]);
    // The card in the middle is the app used before Firefox: the terminal.
    expect(shell.controller.deck.row.target, 1);
    await shell.settle(tester);
    expect(shell.controller.deck.order, [4, 1, 2, 3]);
    await shell.finish(tester);
  });

  testWidgets('after Recents the pill switches in the order of use again', (
    tester,
  ) async {
    final shell = await shellWith(tester);
    shell.controller.openOverview();
    await tester.pump();
    await shell.settle(tester);
    // A tap on the terminal's card.
    shell.controller.openFromRecents(term);
    await tester.pump();
    await shell.settle(tester);
    expect(shell.controller.deck.order, [2, 4, 3, 1]);
    expect(shell.controller.deck.row.target, 3);
    await shell.finish(tester);
  });

  /// «Close all», as Recents does it: every card leaves the row, Recents
  /// goes home, and each app is closed as its card has gone.
  void closeAll(MobileShellHarness shell) {
    final controller = shell.controller;
    final cards = [
      for (final id in controller.deck.order)
        controller.state.deckAppsByObjectId[id]!,
    ];
    for (final card in cards) {
      controller.leaveRecents(card);
    }
    controller.closeOverview();
    for (final card in cards) {
      controller.dismissFromRecents(card);
    }
  }

  /// Opens Recents and closes everything in it, letting the deck settle.
  Future<MobileShellHarness> closedAll(WidgetTester tester) async {
    final shell = await shellWith(tester);
    shell.controller.openOverview();
    await tester.pump();
    await shell.settle(tester);
    shell.bridge.requests.clear();
    closeAll(shell);
    await shell.settle(tester);
    return shell;
  }

  /// The app brought to the front lands, as its flight from home would.
  void land(MobileShellHarness shell) {
    final state = shell.controller.state;
    shell.controller.completeLaunchTransition(
      state.launchRequest!.requestId,
      state.launchingObjectId!,
    );
  }

  testWidgets('apps that close in time do not come back', (tester) async {
    final shell = await closedAll(tester);
    expect(
      shell.bridge.requests.where((request) => request.startsWith('close ')),
      hasLength(4),
    );
    await shell.publish(tester, const []);
    await tester.pump(const Duration(seconds: 2));
    expect(shell.controller.state.foregroundObjectId, isNull);
    expect(shell.controller.deck.order, isEmpty);
    expect(
      shell.bridge.requests.where((request) => request.startsWith('focus ')),
      isEmpty,
    );
    await shell.finish(tester);
  });

  testWidgets('a dialog opening over a closing app brings it to the front', (
    tester,
  ) async {
    final shell = await closedAll(tester);
    // Files asks something in a dialog of its own; the others are gone.
    final dialog = phoneWindow(9, 'org.gnome.Nautilus', transientParent: 4);
    await shell.publish(tester, [files, dialog]);
    // At once, not after the grace: the app is waiting for an answer.
    expect(shell.controller.state.foregroundObjectId, 9);
    expect(shell.bridge.requests, contains('focus 9'));
    expect(shell.controller.deck.order, [4]);
    await shell.finish(tester);
  });

  testWidgets('the next app with a question comes once the first closes', (
    tester,
  ) async {
    final shell = await closedAll(tester);
    // The terminal and Files both keep their windows open.
    await shell.publish(tester, [term, files]);
    await tester.pump(const Duration(seconds: 1));
    // The one used last comes first.
    expect(shell.controller.state.foregroundObjectId, 1);
    land(shell);
    expect(shell.bridge.requests, isNot(contains('focus 4')));
    // Answered, the terminal closes: Files comes next.
    await shell.publish(tester, [files]);
    expect(shell.controller.state.foregroundObjectId, 4);
    expect(shell.bridge.requests, contains('focus 4'));
    await shell.finish(tester);
  });

  testWidgets('turning away from the question leaves the rest in Recents', (
    tester,
  ) async {
    final shell = await closedAll(tester);
    await shell.publish(tester, [term, files]);
    await tester.pump(const Duration(seconds: 1));
    expect(shell.controller.state.foregroundObjectId, 1);
    land(shell);
    // The user cancels the terminal's question and goes home.
    shell.controller.goHome();
    shell.controller.completeHomeTransition();
    await shell.settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(shell.controller.state.foregroundObjectId, isNull);
    expect(shell.bridge.requests, isNot(contains('focus 4')));
    // Both are in Recents again.
    expect(shell.controller.deck.order, unorderedEquals([1, 4]));
    await shell.finish(tester);
  });

  testWidgets('in open Recents an app that keeps its window comes back to '
      'the row', (tester) async {
    final shell = await shellWith(tester);
    shell.controller.openOverview();
    await tester.pump();
    await shell.settle(tester);
    shell.bridge.requests.clear();
    shell.controller
      ..leaveRecents(term)
      ..dismissFromRecents(term);
    expect(shell.controller.deck.order, isNot(contains(1)));
    // The terminal asks before it closes; Recents is still open.
    await tester.pump(const Duration(seconds: 1));
    expect(shell.controller.state.overviewVisible, isTrue);
    expect(shell.controller.deck.order, contains(1));
    expect(
      shell.bridge.requests.where((request) => request.startsWith('focus ')),
      isEmpty,
    );
    await shell.finish(tester);
  });

  testWidgets('closing a card of a grouped app closes only its window', (
    tester,
  ) async {
    final shell = await shellWith(tester);
    shell.controller.openOverview();
    await tester.pump();
    await shell.settle(tester);
    shell.bridge.requests.clear();
    shell.controller.leaveRecents(firefox);
    shell.controller.dismissFromRecents(firefox);
    expect(shell.bridge.requests, ['close 2']);
    expect(shell.controller.deck.order, [4, 1, 3]);
    await shell.finish(tester);
  });
}
