/// Split View in the tablet (mobile) presentation: two apps side by side on
/// the phone's screen, as on iPadOS. deniald holds the pairs and sizes the
/// two windows (`wayland_frontend/split_view.rs`); the shell draws them,
/// the divider between them and the handles on top of them.
library;

import 'dart:ui' show Offset, Rect, Size;

import 'package:denial_flutter_sdk/models.dart';

/// The shares of the width the divider rests at, for the left app.
const List<double> splitViewShares = <double>[1 / 3, 1 / 2, 2 / 3];

/// The share a new pair starts at.
const double splitViewStartShare = 1 / 2;

/// A divider let go nearer an edge than this share of the width sends the
/// app on that side out of the pair: the other fills the screen.
const double splitViewDismissShare = 0.12;

/// How far a fling of the divider carries it, in seconds of its speed.
const double _dividerProjection = 0.12;

/// Two phone windows in Split View, left first, and the left one's share.
typedef SplitPair = ({DenialWindow left, DenialWindow right, double share});

/// The pair [window] is in, when both windows are open among [open] and
/// neither fills the screen (a full-screen one shows alone until it leaves
/// full screen).
SplitPair? splitPairOf(DenialWindow? window, Map<int, DenialWindow> open) {
  final partnerId = window?.splitViewPartnerObjectId;
  if (window == null || partnerId == null) return null;
  final partner = open[partnerId];
  if (partner == null ||
      partner.splitViewPartnerObjectId != window.objectId ||
      window.fullscreen ||
      partner.fullscreen) {
    return null;
  }
  final windowFirst = window.geometryX <= partner.geometryX;
  return (
    left: windowFirst ? window : partner,
    right: windowFirst ? partner : window,
    share: window.splitViewRatio,
  );
}

/// Where Split View draws each of [windows], the windows of one card or one
/// screen: its horizontal span as shares of the pair's width, by object id.
/// Windows outside Split View fill the width.
Map<int, ({double left, double right})> splitPlacement(
  List<DenialWindow> windows,
) {
  Rect? span;
  for (final window in windows) {
    final geometry = window.geometry;
    if (!window.inSplitView || geometry == null) continue;
    span = span?.expandToInclude(geometry) ?? geometry;
  }
  return {
    for (final window in windows)
      window.objectId: switch ((span, window.geometry)) {
        (final span?, final geometry?) when span.width > 0 => (
          left: ((geometry.left - span.left) / span.width).clamp(0.0, 1.0),
          right: ((geometry.right - span.left) / span.width).clamp(0.0, 1.0),
        ),
        _ => (left: 0.0, right: 1.0),
      },
  };
}

/// Where a divider let go comes to rest.
sealed class SplitDividerRelease {
  const SplitDividerRelease();
}

/// The divider rests at [share] of the width.
final class SplitDividerRests extends SplitDividerRelease {
  const SplitDividerRests(this.share);
  final double share;

  @override
  bool operator ==(Object other) =>
      other is SplitDividerRests && other.share == share;

  @override
  int get hashCode => share.hashCode;

  @override
  String toString() => 'SplitDividerRests($share)';
}

/// The app on the left ([leftLeaves]) or on the right leaves the pair; the
/// other fills the screen.
final class SplitDividerCloses extends SplitDividerRelease {
  const SplitDividerCloses({required this.leftLeaves});
  final bool leftLeaves;

  @override
  bool operator ==(Object other) =>
      other is SplitDividerCloses && other.leftLeaves == leftLeaves;

  @override
  int get hashCode => leftLeaves.hashCode;

  @override
  String toString() => 'SplitDividerCloses(leftLeaves: $leftLeaves)';
}

/// The divider let go at [share] of the width, moving at [velocity] shares
/// per second: a fling carries it on a little. It rests at the nearest of
/// [splitViewShares], or, near an edge, closes that side.
SplitDividerRelease releaseSplitDivider(double share, {double velocity = 0}) {
  final projected = share + velocity * _dividerProjection;
  if (projected < splitViewDismissShare) {
    return const SplitDividerCloses(leftLeaves: true);
  }
  if (projected > 1 - splitViewDismissShare) {
    return const SplitDividerCloses(leftLeaves: false);
  }
  var nearest = splitViewShares.first;
  for (final candidate in splitViewShares) {
    if ((candidate - projected).abs() < (nearest - projected).abs()) {
      nearest = candidate;
    }
  }
  return SplitDividerRests(nearest);
}

/// What a window dragged by its handle does when let go.
enum SplitHandleRelease {
  /// Back to its place.
  stay,

  /// The two apps change sides.
  swap,

  /// It leaves the pair and fills the screen in front.
  fullScreen,
}

/// A handle pulled down more than this share of the screen's height takes
/// its window out of the pair.
const double splitHandleFullScreenShare = 0.25;

/// The window on the left ([onLeft]) or right, dragged by its handle by
/// [drag] on a [screen] whose divider is at [share], was let go.
SplitHandleRelease releaseSplitHandle({
  required Offset drag,
  required Size screen,
  required bool onLeft,
  required double share,
}) {
  if (screen.isEmpty) return SplitHandleRelease.stay;
  if (drag.dy > screen.height * splitHandleFullScreenShare) {
    return SplitHandleRelease.fullScreen;
  }
  // The window's middle crossed into the other half.
  final half = onLeft ? share / 2 : (1 + share) / 2;
  final middle = half + drag.dx / screen.width;
  final crossed = onLeft ? middle > share : middle < share;
  return crossed ? SplitHandleRelease.swap : SplitHandleRelease.stay;
}
