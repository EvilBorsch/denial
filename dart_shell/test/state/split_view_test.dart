import 'package:denial_desktop/src/state/split_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

void main() {
  group('the divider', () {
    test('rests at the nearest third or half', () {
      expect(releaseSplitDivider(0.30), const SplitDividerRests(1 / 3));
      expect(releaseSplitDivider(0.45), const SplitDividerRests(1 / 2));
      expect(releaseSplitDivider(0.58), const SplitDividerRests(1 / 2));
      expect(releaseSplitDivider(0.61), const SplitDividerRests(2 / 3));
      expect(releaseSplitDivider(0.80), const SplitDividerRests(2 / 3));
      expect(releaseSplitDivider(0.2), const SplitDividerRests(1 / 3));
    });

    test('a fling carries it on', () {
      expect(
        releaseSplitDivider(0.5, velocity: 1.5),
        const SplitDividerRests(2 / 3),
      );
      expect(
        releaseSplitDivider(0.5, velocity: -1.5),
        const SplitDividerRests(1 / 3),
      );
    });

    test('dragged to an edge, the app on that side leaves', () {
      expect(
        releaseSplitDivider(0.05),
        const SplitDividerCloses(leftLeaves: true),
      );
      expect(
        releaseSplitDivider(0.95),
        const SplitDividerCloses(leftLeaves: false),
      );
      expect(
        releaseSplitDivider(0.2, velocity: -1),
        const SplitDividerCloses(leftLeaves: true),
      );
    });
  });

  group('a handle let go', () {
    const screen = Size(1357, 960);

    test('pulled down a quarter of the screen takes its app out', () {
      expect(
        releaseSplitHandle(
          drag: const Offset(20, 260),
          screen: screen,
          onLeft: true,
          share: 0.5,
        ),
        SplitHandleRelease.fullScreen,
      );
    });

    test('over the other half swaps the apps', () {
      expect(
        releaseSplitHandle(
          drag: const Offset(400, 40),
          screen: screen,
          onLeft: true,
          share: 0.5,
        ),
        SplitHandleRelease.swap,
      );
      expect(
        releaseSplitHandle(
          drag: const Offset(-300, 0),
          screen: screen,
          onLeft: false,
          share: 2 / 3,
        ),
        SplitHandleRelease.swap,
      );
    });

    test('a short drag goes back', () {
      expect(
        releaseSplitHandle(
          drag: const Offset(120, 80),
          screen: screen,
          onLeft: true,
          share: 0.5,
        ),
        SplitHandleRelease.stay,
      );
      expect(
        releaseSplitHandle(
          drag: const Offset(-200, 0),
          screen: screen,
          onLeft: true,
          share: 0.5,
        ),
        SplitHandleRelease.stay,
      );
    });
  });

  group('placement', () {
    test('each window of a pair takes its half, dialogs their app\'s', () {
      final (left, right) = splitWindows((1, 'a'), (2, 'b'), share: 1 / 3);
      final dialog = phoneWindow(3, 'b', geometry: right.geometry);
      final placement = splitPlacement([left, right, dialog]);
      expect(placement[1]!.left, 0);
      expect(placement[1]!.right, closeTo(449 / 1357, 1e-9));
      expect(placement[2]!.left, closeTo(459 / 1357, 1e-9));
      expect(placement[2]!.right, 1);
      expect(placement[3], placement[2]);
    });

    test('windows outside Split View fill the width', () {
      final placement = splitPlacement([phoneWindow(1, 'a')]);
      expect(placement[1], (left: 0.0, right: 1.0));
    });

    test('a pair is both windows, left first, while neither is full '
        'screen', () {
      final (left, right) = splitWindows((5, 'a'), (3, 'b'));
      final open = {5: left, 3: right};
      final pair = splitPairOf(right, open)!;
      expect(pair.left, left);
      expect(pair.right, right);
      expect(pair.share, 0.5);
      expect(splitPairOf(phoneWindow(7, 'c'), open), isNull);
      expect(splitPairOf(left, {5: left}), isNull);
    });
  });
}
