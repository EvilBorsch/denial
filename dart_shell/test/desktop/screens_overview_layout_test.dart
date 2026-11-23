import 'package:denial_desktop/src/desktop/desktop_screens_overview_layout.dart';
import 'package:denial_flutter_sdk/models.dart' show DenialScreenSide;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _bounds = Rect.fromLTWH(0, 0, 2000, 1250);
const _width = 2000.0;
const _height = 1200.0;
const _gap = 8.0;

/// Screen [index] of a strip whose current screen is [current].
Rect _screen(int index, {int current = 1}) =>
    Rect.fromLTWH((index - current) * (_width + _gap), 50, _width, _height);

DesktopScreensOverviewItem _window(
  int id,
  int screen, {
  String app = 'app',
  int? z,
  Rect? frame,
  bool floating = false,
  bool minimized = false,
}) => DesktopScreensOverviewItem(
  objectId: id,
  frame: frame ?? _screen(screen),
  z: z ?? id,
  screen: minimized ? 0 : screen,
  screenRect: minimized ? null : _screen(screen),
  appId: app,
  title: '$app $id',
  floating: floating,
  minimized: minimized,
);

/// Two windows splitting screen [screen] in halves, left [left].
List<DesktopScreensOverviewItem> _split(int left, int right, int screen) {
  final rect = _screen(screen);
  final half = (rect.width - _gap) / 2;
  return [
    _window(
      left,
      screen,
      app: 'files',
      frame: Rect.fromLTWH(rect.left, rect.top, half, rect.height),
    ),
    _window(
      right,
      screen,
      app: 'terminal',
      frame: Rect.fromLTWH(
        rect.left + half + _gap,
        rect.top,
        half,
        rect.height,
      ),
    ),
  ];
}

void main() {
  test(
    'one card per screen in strip order, each a miniature of its screen',
    () {
      final items = [
        _window(1, 1, app: 'firefox'),
        ..._split(2, 3, 2),
        _window(4, 3, app: 'settings'),
      ];
      final arrangement = DesktopScreensOverviewLayout.arrange(
        bounds: _bounds,
        items: items,
        currentScreen: 2,
      );
      expect(arrangement.cards.map((card) => card.screens), [
        [1],
        [2],
        [3],
      ]);
      expect(arrangement.currentCardId, 2);
      final cards = arrangement.cards;
      // Cards read left to right and share one scale.
      expect(
        cards[0].geometry.rect.left,
        lessThan(cards[1].geometry.rect.left),
      );
      expect(cards[1].geometry.scale, closeTo(cards[2].geometry.scale, 1e-9));
      // A split card shows both halves of its screen in place.
      final left = arrangement.frames[2]!;
      final right = arrangement.frames[3]!;
      final content = cards[1].geometry.contentRect;
      expect(left.left, closeTo(content.left, 1e-6));
      expect(right.right, closeTo(content.right, 1e-6));
      expect(left.right, lessThan(right.left));
      expect(cards[1].tiles, [2, 3]);
      // Labels: the most recent window of the card names it.
      expect(cards[1].frontObjectId, 3);
      expect(cards[1].appId, 'terminal');
    },
  );

  test(
    'single-window screens of one app collapse into a stack where the first is',
    () {
      final items = [
        _window(1, 1, app: 'firefox', z: 5),
        _window(2, 2, app: 'settings'),
        _window(3, 3, app: 'firefox', z: 9),
        ..._split(4, 5, 4),
        _window(6, 5, app: 'firefox', z: 1),
      ];
      final arrangement = DesktopScreensOverviewLayout.arrange(
        bounds: _bounds,
        items: items,
      );
      expect(arrangement.cards.map((card) => card.screens), [
        [1, 3, 5],
        [2],
        [4],
      ]);
      final stack = arrangement.cards.first;
      expect(stack.stacked, isTrue);
      // Tapping the stack goes to the most recently focused of its windows.
      expect(stack.frontObjectId, 3);
      expect(stack.objectIds, [3, 1, 6]);
      // The windows behind the front one peek out above it.
      expect(arrangement.frames[1]!.top, lessThan(arrangement.frames[3]!.top));
      expect(arrangement.frames[3], stack.geometry.contentRect);

      // Expanded, the stack's screens are cards of their own again.
      final expanded = DesktopScreensOverviewLayout.arrange(
        bounds: _bounds,
        items: items,
        expandedApps: const {'firefox'},
      );
      expect(expanded.cards.map((card) => card.screens), [
        [1],
        [2],
        [3],
        [4],
        [5],
      ]);
    },
  );

  test('a lone window of an app does not stack, nor does a split screen', () {
    final arrangement = DesktopScreensOverviewLayout.arrange(
      bounds: _bounds,
      items: [
        _window(1, 1, app: 'files'),
        ..._split(2, 3, 2),
        _window(4, 3, app: 'terminal'),
      ],
    );
    expect(arrangement.cards.every((card) => !card.stacked), isTrue);
  });

  test(
    'floating windows show over their screen, minimized ones on the shelf',
    () {
      final dialog = Rect.fromLTWH(_screen(2).left + 800, 400, 400, 300);
      final arrangement = DesktopScreensOverviewLayout.arrange(
        bounds: _bounds,
        items: [
          _window(1, 1),
          _window(2, 2, app: 'calc-host'),
          _window(3, 2, app: 'calculator', frame: dialog, floating: true),
          _window(4, 1, minimized: true),
        ],
      );
      expect(arrangement.cards, hasLength(2));
      final card = arrangement.cards[1];
      expect(card.objectIds, containsAll(<int>[2, 3]));
      expect(card.tiles, [2]);
      expect(
        card.geometry.contentRect.contains(arrangement.frames[3]!.center),
        isTrue,
      );
      expect(arrangement.shelf.isEmpty, isFalse);
      expect(arrangement.shelf.contains(arrangement.frames[4]!.center), isTrue);
    },
  );

  group('dropping a dragged window', () {
    final items = [
      _window(1, 1, app: 'firefox'),
      ..._split(2, 3, 2),
      _window(4, 3, app: 'settings'),
    ];
    final arrangement = DesktopScreensOverviewLayout.arrange(
      bounds: _bounds,
      items: items,
    );

    DesktopScreensDrop? dropAt(int id, Offset point) =>
        DesktopScreensOverviewLayout.dropAt(
          arrangement: arrangement,
          frames: arrangement.frames,
          items: items,
          objectId: id,
          point: point,
        );

    test('joins a lone screen on the side of the card it lands on', () {
      final content = arrangement.cards[2].geometry.contentRect;
      for (final (point, side) in [
        (content.centerLeft + const Offset(4, 0), DenialScreenSide.left),
        (content.centerRight - const Offset(4, 0), DenialScreenSide.right),
        (content.topCenter + const Offset(0, 4), DenialScreenSide.up),
        (content.bottomCenter - const Offset(0, 4), DenialScreenSide.down),
      ]) {
        final drop = dropAt(1, point);
        expect(drop, isA<DesktopScreensJoin>(), reason: '$side');
        drop as DesktopScreensJoin;
        expect(drop.targetObjectId, 4);
        expect(drop.side, side);
        // The highlight is the half the window will take.
        expect(drop.highlight.contains(point), isTrue);
        expect(
          drop.highlight.width * drop.highlight.height,
          closeTo(content.width * content.height / 2, 1),
        );
      }
    });

    test('splits the tile it lands on in a split screen', () {
      final right = arrangement.frames[3]!;
      final drop = dropAt(1, right.bottomCenter - const Offset(0, 4));
      expect(drop, isA<DesktopScreensJoin>());
      drop as DesktopScreensJoin;
      expect(drop.targetObjectId, 3);
      expect(drop.side, DenialScreenSide.down);
      expect(
        drop.highlight,
        Rect.fromLTRB(right.left, right.center.dy, right.right, right.bottom),
      );
    });

    test('takes a screen of its own in a gap, in front of the next card', () {
      Offset gapBefore(int position) => arrangement.gaps
          .firstWhere((gap) => gap.position == position)
          .rect
          .center;
      // No gap's drop zone covers a card's miniature.
      for (final gap in arrangement.gaps) {
        for (final card in arrangement.cards) {
          expect(
            gap.rect.overlaps(card.geometry.contentRect.deflate(1)),
            isFalse,
          );
        }
      }
      expect(
        dropAt(2, gapBefore(3)),
        isA<DesktopScreensMove>()
            .having((drop) => drop.targetObjectId, 'target', 4)
            .having((drop) => drop.before, 'before', isTrue),
      );
      expect(
        dropAt(2, arrangement.gaps.last.rect.center),
        isA<DesktopScreensMove>()
            .having((drop) => drop.targetObjectId, 'target', 4)
            .having((drop) => drop.before, 'before', isFalse),
      );
      // Out of its own split into the gap before that split: the other tile
      // marks the place.
      expect(
        dropAt(2, gapBefore(2)),
        isA<DesktopScreensMove>()
            .having((drop) => drop.targetObjectId, 'target', 3)
            .having((drop) => drop.before, 'before', isTrue),
      );
    });

    test('reorders a single-window screen through a gap', () {
      final beforeFirst =
          arrangement.cards[0].geometry.rect.centerLeft - const Offset(10, 0);
      expect(
        dropAt(4, beforeFirst),
        isA<DesktopScreensMove>()
            .having((drop) => drop.targetObjectId, 'target', 1)
            .having((drop) => drop.before, 'before', isTrue),
      );
    });

    test('cancels where it came from, outside the cards, and onto itself', () {
      // Its own lone screen, and the gaps on both sides of it.
      expect(dropAt(1, arrangement.cards[0].geometry.rect.center), isNull);
      expect(
        dropAt(
          1,
          arrangement.cards[0].geometry.rect.centerLeft - const Offset(10, 0),
        ),
        isNull,
      );
      expect(
        dropAt(
          1,
          Offset(
            (arrangement.cards[0].geometry.rect.right +
                    arrangement.cards[1].geometry.rect.left) /
                2,
            arrangement.cards[0].geometry.rect.center.dy,
          ),
        ),
        isNull,
      );
      expect(dropAt(1, const Offset(1, 1)), isNull);
      // Within its own split it rearranges, but never onto itself only.
      final drop = dropAt(2, arrangement.frames[3]!.center);
      expect(
        drop,
        isA<DesktopScreensJoin>().having(
          (drop) => drop.targetObjectId,
          'target',
          3,
        ),
      );
    });

    test('refuses a fifth tile, and moves floating windows nowhere', () {
      final screen = _screen(2);
      final quarter = Size(
        (screen.width - _gap) / 2,
        (screen.height - _gap) / 2,
      );
      final full = [
        _window(1, 1),
        for (final (id, dx, dy) in [
          (2, 0.0, 0.0),
          (3, 1.0, 0.0),
          (5, 0.0, 1.0),
          (6, 1.0, 1.0),
        ])
          _window(
            id,
            2,
            app: 'q$id',
            frame: Rect.fromLTWH(
              screen.left + dx * (quarter.width + _gap),
              screen.top + dy * (quarter.height + _gap),
              quarter.width,
              quarter.height,
            ),
          ),
        _window(
          7,
          3,
          app: 'float',
          frame: Rect.fromLTWH(_screen(3).left + 100, 300, 300, 200),
          floating: true,
        ),
        _window(8, 3, app: 'host'),
      ];
      final quarters = DesktopScreensOverviewLayout.arrange(
        bounds: _bounds,
        items: full,
      );
      DesktopScreensDrop? drop(int id, Offset point) =>
          DesktopScreensOverviewLayout.dropAt(
            arrangement: quarters,
            frames: quarters.frames,
            items: full,
            objectId: id,
            point: point,
          );
      expect(drop(1, quarters.cards[1].geometry.contentRect.center), isNull);
      // A quarter still moves within its own screen.
      expect(drop(2, quarters.frames[6]!.center), isA<DesktopScreensJoin>());
      expect(drop(7, quarters.cards[0].geometry.contentRect.center), isNull);
    });
  });
}
