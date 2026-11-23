import 'dart:math' as math;

import 'package:denial_flutter_sdk/models.dart' show DenialScreenSide;
import 'package:flutter/widgets.dart';

import 'desktop_workspace_overview_layout.dart';

/// One window considered by the screens overview of the full-screen apps
/// layout.
@immutable
class DesktopScreensOverviewItem {
  const DesktopScreensOverviewItem({
    required this.objectId,
    required this.frame,
    required this.z,
    required this.screen,
    required this.screenRect,
    required this.appId,
    required this.title,
    this.floating = false,
    this.minimized = false,
  });

  final int objectId;

  /// The window's real frame in scene coordinates; on another screen it
  /// lies beside the output.
  final Rect frame;

  /// Recency: the most recently focused window has the highest value.
  final int z;

  /// One-based place of the window's screen in the strip, 0 for none.
  final int screen;
  final Rect? screenRect;
  final String appId;
  final String title;
  final bool floating;
  final bool minimized;
}

/// A card of the screens overview: one screen, or a stack of screens that
/// each hold a single window of the same app.
@immutable
class DesktopScreenCard {
  const DesktopScreenCard({
    required this.geometry,
    required this.screens,
    required this.objectIds,
    required this.tiles,
    required this.frontObjectId,
    required this.appId,
    required this.title,
  });

  /// Where the card is and how its screen projects into it. The card's id
  /// is `geometry.workspaceId`, its one-based place in the overview.
  final DesktopWorkspaceOverviewCard geometry;

  /// The strip places of its screens, ascending: one, or the stack's.
  final List<int> screens;

  /// Every window drawn on the card, the most recent first.
  final List<int> objectIds;

  /// The tiles of a single screen (floating windows excluded); for a stack,
  /// the front window alone.
  final List<int> tiles;

  /// The most recently focused window: tapping the card goes to it.
  final int frontObjectId;
  final String appId;
  final String title;

  int get id => geometry.workspaceId;
  bool get stacked => screens.length > 1;
}

/// A gap before, between or after the cards. A window dropped there gets a
/// screen of its own at that place in the strip.
@immutable
class DesktopScreenGap {
  const DesktopScreenGap({
    required this.rect,
    required this.targetObjectId,
    required this.before,
    required this.position,
  });

  final Rect rect;

  /// A tile of the screen the new screen goes next to.
  final int targetObjectId;
  final bool before;

  /// The strip place the new screen takes, counted before the move: it goes
  /// in front of the screen now at [position] (one past the last for the
  /// end of the strip).
  final int position;
}

@immutable
class DesktopScreensOverviewArrangement {
  const DesktopScreensOverviewArrangement({
    required this.cards,
    required this.gaps,
    required this.shelf,
    required this.frames,
    required this.currentCardId,
  });

  static const empty = DesktopScreensOverviewArrangement(
    cards: <DesktopScreenCard>[],
    gaps: <DesktopScreenGap>[],
    shelf: Rect.zero,
    frames: <int, Rect>{},
    currentCardId: null,
  );

  final List<DesktopScreenCard> cards;
  final List<DesktopScreenGap> gaps;
  final Rect shelf;
  final Map<int, Rect> frames;

  /// The card of the screen on the output now.
  final int? currentCardId;

  DesktopScreenCard? cardFor(int id) {
    for (final card in cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  DesktopScreenCard? cardOfWindow(int objectId) {
    for (final card in cards) {
      if (card.objectIds.contains(objectId)) {
        return card;
      }
    }
    return null;
  }
}

/// What dropping a dragged window at a point of the screens overview does.
sealed class DesktopScreensDrop {
  const DesktopScreensDrop({
    required this.targetObjectId,
    required this.highlight,
  });

  final int targetObjectId;

  /// Where the window will land, in overview coordinates.
  final Rect highlight;
}

/// Join the screen of [targetObjectId], taking [side] of that tile.
final class DesktopScreensJoin extends DesktopScreensDrop {
  const DesktopScreensJoin({
    required super.targetObjectId,
    required super.highlight,
    required this.side,
  });

  final DenialScreenSide side;

  @override
  bool operator ==(Object other) =>
      other is DesktopScreensJoin &&
      other.targetObjectId == targetObjectId &&
      other.side == side &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(targetObjectId, side, highlight);

  @override
  String toString() => 'DesktopScreensJoin($targetObjectId, $side)';
}

/// A screen of its own just [before] or after the screen of
/// [targetObjectId].
final class DesktopScreensMove extends DesktopScreensDrop {
  const DesktopScreensMove({
    required super.targetObjectId,
    required super.highlight,
    required this.before,
  });

  final bool before;

  @override
  bool operator ==(Object other) =>
      other is DesktopScreensMove &&
      other.targetObjectId == targetObjectId &&
      other.before == before &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(targetObjectId, before, highlight);

  @override
  String toString() => 'DesktopScreensMove($targetObjectId, before: $before)';
}

class _Screen {
  _Screen(this.index, this.rect);

  final int index;
  final Rect rect;
  final List<DesktopScreensOverviewItem> tiles = <DesktopScreensOverviewItem>[];
  final List<DesktopScreensOverviewItem> floats =
      <DesktopScreensOverviewItem>[];

  List<DesktopScreensOverviewItem> get windows => <DesktopScreensOverviewItem>[
    ...tiles,
    ...floats,
  ];

  /// A screen of one app window alone, which may join its app's stack.
  bool get single => tiles.length == 1 && floats.isEmpty;
}

/// Lays out the screens overview: one card per screen in strip order, with
/// the screens that each show a single window of one app collapsed into a
/// stack where the first of them is. Split screens are always cards of
/// their own. Every card is a true-to-layout miniature of its screen at one
/// shared scale; minimized windows sit on a shelf below, as in the
/// workspace overview.
abstract final class DesktopScreensOverviewLayout {
  static const double maximumScale = 0.55;
  static const double labelExtent = 34.0;

  /// The narrowest a gap's drop zone gets, however close the cards are.
  static const double minimumGapZone = 32.0;

  /// How far each window behind a stack's front window peeks out.
  static const double stackStep = 10.0;

  /// The stacks drawn behind the front window, at most.
  static const int stackDepth = 2;

  static DesktopScreensOverviewArrangement arrange({
    required Rect bounds,
    required List<DesktopScreensOverviewItem> items,
    Set<String> expandedApps = const <String>{},
    int? currentScreen,
  }) {
    if (bounds.isEmpty) {
      return DesktopScreensOverviewArrangement.empty;
    }
    final padding = (math.min(bounds.width, bounds.height) * 0.035)
        .clamp(16.0, 44.0)
        .toDouble();
    var area = bounds.deflate(padding);
    if (area.isEmpty) {
      return DesktopScreensOverviewArrangement.empty;
    }
    final gap = (math.min(area.width, area.height) * 0.035)
        .clamp(16.0, 40.0)
        .toDouble();
    final frames = <int, Rect>{};

    final minimized = items
        .where((item) => item.minimized)
        .map(
          (item) => DesktopWorkspaceOverviewItem(
            objectId: item.objectId,
            frame: item.frame,
            z: item.z,
            workspaceId: 1,
            minimized: true,
          ),
        )
        .toList(growable: false);
    var shelf = Rect.zero;
    if (minimized.isNotEmpty) {
      final shelfHeight = (area.height * 0.16).clamp(72.0, 168.0).toDouble();
      final shelfBounds = Rect.fromLTRB(
        area.left,
        area.bottom - shelfHeight,
        area.right,
        area.bottom,
      );
      shelf = DesktopWorkspaceOverviewLayout.arrangeShelf(
        minimized..sort((left, right) => right.z.compareTo(left.z)),
        shelfBounds,
        frames,
      );
      area = Rect.fromLTRB(
        area.left,
        area.top,
        area.right,
        math.max(area.top, shelfBounds.top - gap),
      );
    }

    final screens = <int, _Screen>{};
    final loose = <DesktopScreensOverviewItem>[];
    for (final item in items) {
      if (item.minimized) {
        continue;
      }
      final rect = item.screenRect;
      if (item.screen <= 0 || rect == null || rect.isEmpty) {
        loose.add(item);
        continue;
      }
      final screen = screens.putIfAbsent(
        item.screen,
        () => _Screen(item.screen, rect),
      );
      (item.floating ? screen.floats : screen.tiles).add(item);
    }
    if (screens.isEmpty) {
      return DesktopScreensOverviewArrangement(
        cards: const <DesktopScreenCard>[],
        gaps: const <DesktopScreenGap>[],
        shelf: shelf,
        frames: frames,
        currentCardId: null,
      );
    }
    final ordered = screens.values.toList(growable: false)
      ..sort((left, right) => left.index.compareTo(right.index));
    // Windows on no screen (above every screen, such as pinned ones) show
    // over the current screen.
    final current = screens[currentScreen] ?? ordered.first;
    current.floats.addAll(loose);

    final singlesByApp = <String, List<_Screen>>{};
    for (final screen in ordered) {
      if (screen.single) {
        singlesByApp
            .putIfAbsent(screen.tiles.single.appId, () => <_Screen>[])
            .add(screen);
      }
    }
    // Each card's screens, in strip order of the card's first screen.
    final groups = <List<_Screen>>[];
    for (final screen in ordered) {
      final app = screen.single ? screen.tiles.single.appId : null;
      final stack = app == null ? null : singlesByApp[app];
      if (stack != null && stack.length > 1 && !expandedApps.contains(app)) {
        if (identical(stack.first, screen)) {
          groups.add(stack);
        }
        continue;
      }
      groups.add(<_Screen>[screen]);
    }

    final sourceWidth = ordered
        .map((screen) => screen.rect.width)
        .reduce(math.max);
    final sourceHeight = ordered
        .map((screen) => screen.rect.height)
        .reduce(math.max);
    final inset = DesktopWorkspaceOverviewLayout.cardInset;
    final grid = _bestGrid(
      count: groups.length,
      area: area,
      gap: gap,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      inset: inset,
    );
    if (grid == null) {
      return DesktopScreensOverviewArrangement(
        cards: const <DesktopScreenCard>[],
        gaps: const <DesktopScreenGap>[],
        shelf: shelf,
        frames: frames,
        currentCardId: null,
      );
    }
    final scale = grid.scale;
    final cardWidth = sourceWidth * scale + inset * 2.0;
    final cardHeight = sourceHeight * scale + inset * 2.0;
    final cellHeight = cardHeight + labelExtent;
    final gridWidth = grid.columns * cardWidth + gap * (grid.columns - 1);
    final gridHeight = grid.rows * cellHeight + gap * (grid.rows - 1);
    final origin = area.center - Offset(gridWidth / 2.0, gridHeight / 2.0);

    final cards = <DesktopScreenCard>[];
    int? currentCardId;
    for (var index = 0; index < groups.length; index += 1) {
      final row = index ~/ grid.columns;
      final column = index % grid.columns;
      final inRow = math.min(grid.columns, groups.length - row * grid.columns);
      final centering = (grid.columns - inRow) * (cardWidth + gap) / 2.0;
      final rect = Rect.fromLTWH(
        origin.dx + centering + column * (cardWidth + gap),
        origin.dy + row * (cellHeight + gap) + labelExtent,
        cardWidth,
        cardHeight,
      );
      final group = groups[index];
      final windows = <DesktopScreensOverviewItem>[
        for (final screen in group) ...screen.windows,
      ]..sort((left, right) => right.z.compareTo(left.z));
      final front = group.length > 1
          ? windows.first
          : (List<DesktopScreensOverviewItem>.of(group.single.tiles)
                      ..sort((left, right) => right.z.compareTo(left.z)))
                    .firstOrNull ??
                windows.first;
      final frontScreen = group.firstWhere(
        (screen) => screen.windows.contains(front),
      );
      final source = frontScreen.rect;
      final contentRect = Rect.fromCenter(
        center: rect.center,
        width: source.width * scale,
        height: source.height * scale,
      );
      final geometry = DesktopWorkspaceOverviewCard(
        workspaceId: index + 1,
        rect: rect,
        contentRect: contentRect,
        sourceRect: source,
        viewportRect: contentRect,
      );
      if (group.length == 1) {
        for (final window in windows) {
          frames[window.objectId] = geometry.project(window.frame);
        }
      } else {
        // The front window fills the card; the others stand behind it,
        // each a little higher and narrower, as a stack of cards.
        for (var depth = 0; depth < windows.length; depth += 1) {
          final window = windows[depth];
          final own = group.firstWhere(
            (screen) => screen.windows.contains(window),
          );
          final shown = math.min(depth, stackDepth).toDouble();
          frames[window.objectId] = geometry
              .project(window.frame.shift(source.topLeft - own.rect.topLeft))
              .deflate(stackStep * shown / 2.0)
              .shift(Offset(0.0, -stackStep * shown));
        }
      }
      if (group.contains(current)) {
        currentCardId = index + 1;
      }
      cards.add(
        DesktopScreenCard(
          geometry: geometry,
          screens: [for (final screen in group) screen.index],
          objectIds: [for (final window in windows) window.objectId],
          tiles: group.length == 1
              ? [for (final tile in group.single.tiles) tile.objectId]
              : <int>[front.objectId],
          frontObjectId: front.objectId,
          appId: front.appId,
          title: front.title,
        ),
      );
    }

    return DesktopScreensOverviewArrangement(
      cards: List<DesktopScreenCard>.unmodifiable(cards),
      gaps: List<DesktopScreenGap>.unmodifiable(
        _gaps(cards, ordered, columns: grid.columns, gap: gap),
      ),
      shelf: shelf,
      frames: frames,
      currentCardId: currentCardId,
    );
  }

  static List<DesktopScreenGap> _gaps(
    List<DesktopScreenCard> cards,
    List<_Screen> screens, {
    required int columns,
    required double gap,
  }) {
    final zone = math.max(gap, minimumGapZone);
    Rect zoneLeftOf(Rect card) => Rect.fromLTRB(
      card.left - gap / 2.0 - zone / 2.0,
      card.top,
      card.left - gap / 2.0 + zone / 2.0,
      card.bottom,
    );
    Rect zoneRightOf(Rect card) => Rect.fromLTRB(
      card.right + gap / 2.0 - zone / 2.0,
      card.top,
      card.right + gap / 2.0 + zone / 2.0,
      card.bottom,
    );
    int tileOf(int screen) {
      final found = screens.firstWhere(
        (candidate) => candidate.index == screen,
      );
      return (found.tiles.isNotEmpty ? found.tiles : found.floats)
          .first
          .objectId;
    }

    final gaps = <DesktopScreenGap>[];
    for (var index = 0; index < cards.length; index += 1) {
      final card = cards[index];
      final first = card.screens.first;
      gaps.add(
        DesktopScreenGap(
          rect: zoneLeftOf(card.geometry.rect),
          targetObjectId: tileOf(first),
          before: true,
          position: first,
        ),
      );
      final lastInRow = index % columns == columns - 1;
      if (lastInRow && index + 1 < cards.length) {
        final next = cards[index + 1].screens.first;
        gaps.add(
          DesktopScreenGap(
            rect: zoneRightOf(card.geometry.rect),
            targetObjectId: tileOf(next),
            before: true,
            position: next,
          ),
        );
      }
    }
    final last = screens.last;
    gaps.add(
      DesktopScreenGap(
        rect: zoneRightOf(cards.last.geometry.rect),
        targetObjectId: tileOf(last.index),
        before: false,
        position: last.index + 1,
      ),
    );
    return gaps;
  }

  /// What dropping [objectId] at [point] does: join the tile under it on
  /// its nearest side, or take a screen of its own in the gap under it.
  /// Null cancels: outside the cards and gaps, back on its own lone screen,
  /// onto itself, onto a screen with four tiles, or for a window that is no
  /// screen's tile.
  static DesktopScreensDrop? dropAt({
    required DesktopScreensOverviewArrangement arrangement,
    required Map<int, Rect> frames,
    required List<DesktopScreensOverviewItem> items,
    required int objectId,
    required Offset point,
  }) {
    DesktopScreensOverviewItem? dragged;
    for (final item in items) {
      if (item.objectId == objectId) {
        dragged = item;
      }
    }
    if (dragged == null ||
        dragged.floating ||
        dragged.minimized ||
        dragged.screen <= 0) {
      return null;
    }
    final ownTiles = [
      for (final item in items)
        if (item.screen == dragged.screen && !item.floating && !item.minimized)
          item.objectId,
    ];
    final alone = ownTiles.length == 1;

    for (final gap in arrangement.gaps) {
      if (!gap.rect.contains(point)) {
        continue;
      }
      if (alone &&
          (gap.position == dragged.screen ||
              gap.position == dragged.screen + 1)) {
        return null;
      }
      var target = gap.targetObjectId;
      if (target == objectId) {
        // The gap's screen is the dragged window's own split: any other
        // tile of it marks the same place.
        final others = [
          for (final tile in ownTiles)
            if (tile != objectId) tile,
        ];
        if (others.isEmpty) {
          return null;
        }
        target = others.first;
      }
      return DesktopScreensMove(
        targetObjectId: target,
        before: gap.before,
        highlight: gap.rect,
      );
    }

    DesktopScreenCard? card;
    for (final candidate in arrangement.cards) {
      if (candidate.geometry.rect.contains(point)) {
        card = candidate;
      }
    }
    if (card == null) {
      return null;
    }
    if (card.stacked) {
      if (card.objectIds.contains(objectId)) {
        return null;
      }
      final content = card.geometry.contentRect;
      final side = _nearestSide(content, point);
      return DesktopScreensJoin(
        targetObjectId: card.frontObjectId,
        side: side,
        highlight: _half(content, side),
      );
    }
    final tiles = card.tiles;
    final ownScreen = tiles.contains(objectId);
    if (ownScreen && alone) {
      return null;
    }
    if (!ownScreen && tiles.length >= 4) {
      return null;
    }
    int? target;
    var nearest = double.infinity;
    for (final tile in tiles) {
      final frame = frames[tile];
      if (tile == objectId || frame == null) {
        continue;
      }
      final distance = frame.contains(point)
          ? -1.0
          : (frame.center - point).distanceSquared;
      if (distance < nearest) {
        nearest = distance;
        target = tile;
      }
    }
    if (target == null) {
      return null;
    }
    final frame = frames[target]!;
    final side = _nearestSide(frame, point);
    return DesktopScreensJoin(
      targetObjectId: target,
      side: side,
      highlight: _half(frame, side),
    );
  }

  static DenialScreenSide _nearestSide(Rect rect, Offset point) {
    if (rect.width <= 0.0 || rect.height <= 0.0) {
      return DenialScreenSide.right;
    }
    final x = ((point.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final y = ((point.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    final distances = <(double, DenialScreenSide)>[
      (x, DenialScreenSide.left),
      (1.0 - x, DenialScreenSide.right),
      (y, DenialScreenSide.up),
      (1.0 - y, DenialScreenSide.down),
    ];
    return distances.reduce((best, next) => next.$1 < best.$1 ? next : best).$2;
  }

  static Rect _half(Rect rect, DenialScreenSide side) => switch (side) {
    DenialScreenSide.left => Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width / 2.0,
      rect.height,
    ),
    DenialScreenSide.right => Rect.fromLTWH(
      rect.center.dx,
      rect.top,
      rect.width / 2.0,
      rect.height,
    ),
    DenialScreenSide.up => Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      rect.height / 2.0,
    ),
    DenialScreenSide.down => Rect.fromLTWH(
      rect.left,
      rect.center.dy,
      rect.width,
      rect.height / 2.0,
    ),
  };

  static ({int columns, int rows, double scale})? _bestGrid({
    required int count,
    required Rect area,
    required double gap,
    required double sourceWidth,
    required double sourceHeight,
    required double inset,
  }) {
    if (sourceWidth <= 0.0 || sourceHeight <= 0.0) {
      return null;
    }
    ({int columns, int rows, double scale})? best;
    var bestEmpty = count;
    for (var columns = count; columns >= 1; columns -= 1) {
      final rows = (count / columns).ceil();
      final cellWidth = (area.width - gap * (columns - 1)) / columns;
      final cellHeight = (area.height - gap * (rows - 1)) / rows;
      final scale = math.min(
        maximumScale,
        math.min(
          (cellWidth - inset * 2.0) / sourceWidth,
          (cellHeight - labelExtent - inset * 2.0) / sourceHeight,
        ),
      );
      if (scale <= 0.0) {
        continue;
      }
      final empty = columns * rows - count;
      if (best == null ||
          scale > best.scale + 0.0001 ||
          ((scale - best.scale).abs() <= 0.0001 && empty < bestEmpty)) {
        best = (columns: columns, rows: rows, scale: scale);
        bestEmpty = empty;
      }
    }
    return best;
  }
}
