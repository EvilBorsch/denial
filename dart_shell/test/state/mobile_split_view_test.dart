import 'dart:ui' show Rect;

import 'package:denial_desktop/src/state/reference_input_layout_coordinator.dart';
import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

void main() {
  final files = phoneWindow(1, 'org.gnome.Nautilus');
  final editor = phoneWindow(2, 'org.gnome.TextEditor');
  final terminal = phoneWindow(3, 'org.gnome.Console');

  Future<MobileShellHarness> shellWith(
    WidgetTester tester, {
    List<int> inFront = const [1, 3, 2],
  }) async {
    final shell = MobileShellHarness();
    addTearDown(shell.dispose);
    await shell.publish(tester, [files, editor, terminal]);
    final windows = {1: files, 2: editor, 3: terminal};
    for (final id in inFront) {
      shell.controller.focusWindow(windows[id]!);
      await tester.pump();
    }
    await shell.settle(tester);
    return shell;
  }

  /// deniald made [left] and [right] a pair, as it publishes it.
  Future<void> pairUp(
    MobileShellHarness shell,
    WidgetTester tester,
    (int, String) left,
    (int, String) right, {
    double share = 0.5,
    List<int> others = const [],
  }) async {
    final (l, r) = splitWindows(left, right, share: share);
    final rest = {1: files, 2: editor, 3: terminal};
    await shell.publish(tester, [for (final id in others) rest[id]!, l, r]);
  }

  group('entering from Recents', () {
    testWidgets('a card dropped on a side shares the screen with the app in '
        'front', (tester) async {
      final shell = await shellWith(tester);
      final controller = shell.controller;
      controller.openOverview();
      await tester.pump();
      // The editor is in front; a long press on the files' card offers it.
      expect(controller.splitTargetFor(files)?.objectId, 2);
      // Its own card has none to share with.
      expect(controller.splitTargetFor(editor), isNull);
      shell.bridge.requests.clear();
      expect(controller.splitWithFront(files, onLeft: true), isTrue);
      expect(shell.bridge.requests, ['split 1 2 left 0.500']);
      // Recents waits for deniald's pair, then opens on it.
      expect(
        shell.container.read(referenceShellProvider).overviewVisible,
        isTrue,
      );
      await pairUp(
        shell,
        tester,
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
        others: [3],
      );
      final state = shell.container.read(referenceShellProvider);
      expect(state.overviewVisible, isFalse);
      expect(state.foregroundObjectId, 1);
      final pair = state.primarySplit!;
      expect(pair.left.objectId, 1);
      expect(pair.right.objectId, 2);
      expect(pair.share, 0.5);
      await shell.settle(tester);
      await shell.finish(tester);
    });

    testWidgets('a pair deniald refuses opens the card alone', (tester) async {
      final shell = await shellWith(tester);
      final controller = shell.controller;
      controller.openOverview();
      await tester.pump();
      controller.splitWithFront(terminal, onLeft: false);
      await tester.pump(const Duration(milliseconds: 1100));
      final state = shell.container.read(referenceShellProvider);
      expect(state.overviewVisible, isFalse);
      expect(state.foregroundObjectId, 3);
      expect(state.primarySplit, isNull);
      await shell.settle(tester);
      await shell.finish(tester);
    });

    testWidgets('from home there is no app to share the screen with', (
      tester,
    ) async {
      final shell = await shellWith(tester);
      shell.controller.goHome();
      await tester.pump();
      await shell.settle(tester);
      shell.controller.openOverview();
      await tester.pump();
      expect(shell.controller.splitTargetFor(files), isNull);
      expect(shell.controller.splitWithFront(files, onLeft: true), isFalse);
      await shell.settle(tester);
      await shell.finish(tester);
    });
  });

  group('a pair', () {
    testWidgets('is one card in Recents and for the home pill', (tester) async {
      final shell = await shellWith(tester);
      await pairUp(
        shell,
        tester,
        (2, 'org.gnome.TextEditor'),
        (1, 'org.gnome.Nautilus'),
        others: [3],
      );
      final state = shell.container.read(referenceShellProvider);
      // The window with the lower id holds the card.
      expect([for (final window in state.deckApps) window.objectId], [3, 1]);
      expect(state.deckAppOf(2), 1);
      expect(
        [for (final window in state.deckCardWindows(1)) window.objectId],
        [2, 1],
      );
      expect(state.deckFocusOf(1)?.objectId, 1);
      await shell.finish(tester);
    });

    testWidgets('closing one side leaves the other on the whole screen', (
      tester,
    ) async {
      final shell = await shellWith(tester);
      await pairUp(
        shell,
        tester,
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
        others: [3],
      );
      expect(
        shell.container.read(referenceShellProvider).primarySplit,
        isNotNull,
      );
      // The files app quits: deniald gives the editor the whole screen.
      await shell.publish(tester, [terminal, editor]);
      final state = shell.container.read(referenceShellProvider);
      expect(state.primarySplit, isNull);
      expect(state.foregroundObjectId, 2);
      expect(state.primaryWindow?.objectId, 2);
      await shell.finish(tester);
    });

    testWidgets('touching the other side does not minimize the app left', (
      tester,
    ) async {
      final shell = await shellWith(tester);
      await pairUp(
        shell,
        tester,
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
        others: [3],
      );
      shell.bridge.requests.clear();
      // A touch on the files app: deniald activates it.
      final (left, _) = splitWindows(
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
      );
      shell.bridge.activate(left);
      await tester.pump();
      expect(
        shell.container.read(referenceShellProvider).foregroundObjectId,
        1,
      );
      expect(
        shell.bridge.requests.where((r) => r.startsWith('minimize')),
        isEmpty,
      );
      // Leaving the pair for the terminal minimizes it once: deniald takes
      // the partner along.
      shell.controller.focusWindow(terminal);
      await tester.pump();
      expect(
        shell.bridge.requests.where((r) => r.startsWith('minimize')),
        hasLength(1),
      );
      await shell.settle(tester);
      await shell.finish(tester);
    });

    testWidgets('the divider settles its share, swaps, and drags an app off', (
      tester,
    ) async {
      final shell = await shellWith(tester);
      await pairUp(
        shell,
        tester,
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
        others: [3],
      );
      final controller = shell.controller;
      final pair = shell.container.read(referenceShellProvider).primarySplit!;
      shell.bridge.requests.clear();
      controller.setSplitShare(pair, 2 / 3);
      controller.setSplitShare(pair, 0.5);
      controller.swapSplit(pair);
      expect(shell.bridge.requests, [
        'split 1 2 left 0.667',
        'split 1 2 right 0.500',
      ]);
      shell.bridge.requests.clear();
      final (_, right) = splitWindows(
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
      );
      controller.leaveSplit(pair, stays: right);
      // The editor fills the screen in front; the files app leaves it.
      expect(shell.bridge.requests, ['leave split 2', 'minimize 1', 'focus 2']);
      await shell.settle(tester);
      await shell.finish(tester);
    });

    testWidgets('both windows take touches in their halves', (tester) async {
      tester.view
        ..physicalSize = tabletView
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shell = await shellWith(tester);
      await pairUp(
        shell,
        tester,
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
        share: 1 / 3,
        others: [3],
      );
      final (left, _) = splitWindows(
        (1, 'org.gnome.Nautilus'),
        (2, 'org.gnome.TextEditor'),
        share: 1 / 3,
      );
      shell.bridge.activate(left);
      await tester.pump();
      shell.bridge.inputLayouts.clear();
      ReferenceInputLayoutCoordinator(shell.bridge).publish(
        state: shell.container.read(referenceShellProvider),
        viewSize: tabletView,
        interactions: ShellInteractionSnapshot.empty(),
      );
      final layout = shell.bridge.inputLayouts.last;
      final regions = {
        for (final region in layout.windows) region.window.objectId: region,
      };
      expect(regions.keys, unorderedEquals([1, 2]));
      expect(regions[1]!.rect, const Rect.fromLTRB(0, 0, 449, 960));
      expect(regions[2]!.rect, const Rect.fromLTRB(459, 0, 1357, 960));
      // Each maps to its own window's coordinates.
      expect(regions[2]!.sourceRect.width, closeTo(898, 0.5));
      await shell.settle(tester);
      await shell.finish(tester);
    });
  });
}
