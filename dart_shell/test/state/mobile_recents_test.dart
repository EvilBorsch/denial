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
