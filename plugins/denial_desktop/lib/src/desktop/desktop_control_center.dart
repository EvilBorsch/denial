import 'dart:math' as math;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/widgets.dart';

import 'desktop_panel_transition.dart';
import 'desktop_workspace.dart';

/// Where the desktop presentation's control center sits and how it moves.
///
/// The control center is Denial's dashboard (notifications, quick settings,
/// the mobile view button), opened by the control-center icon and the clock
/// at the trailing end of the system bar, as macOS's Control Center is. It
/// rests under that end of the bar and slides out from under the bar: down
/// from a top bar, up from a bottom bar, sideways from a bar on a side. With
/// the bar hidden it drops from the top right of the screen.
///
/// Only its size and edge distance come from the settings
/// (`overlays.dashboard.width`, `height` and `margin`). Their anchor and
/// hover trigger belong to the side panel the dashboard was before eb19:
/// a pointer resting at a screen edge never opens the control center, so the
/// hover trigger of older settings files has no effect here.
@immutable
class DesktopControlCenterGeometry {
  const DesktopControlCenterGeometry({
    required this.panel,
    required this.reveal,
    required this.entryDirection,
    required this.entryGap,
    required this.swipe,
  });

  /// The panel at rest, in scene coordinates.
  final Rect panel;

  /// What the panel shows through while it moves: the panel's extent from
  /// the bar's edge of the work area to the panel's far side. The panel is
  /// clipped to it, so it comes out from under the bar instead of crossing
  /// the bar's controls.
  final Rect reveal;

  /// Toward the bar: the panel enters from there and leaves that way.
  final Offset entryDirection;

  /// Distance between the bar's edge of the work area and the panel at rest.
  /// The panel travels its own extent plus this, so it starts fully hidden.
  final double entryGap;

  /// Where a finger swipes in from the bar's screen edge to open the control
  /// center: along the panel, up to the trailing corner of the screen, as
  /// the top-right corner opens Control Center on an iPad. Touch only; a
  /// pointer never opens it from an edge.
  final DesktopPanelSwipe? swipe;

  /// The control center on the output that hosts the system bar.
  ///
  /// [configured] supplies the size and edge distance; its anchor and hover
  /// trigger are ignored. Without a display layout (a shell running without
  /// the compositor) the canvas is the output and the bar is hidden.
  static DesktopControlCenterGeometry? resolve({
    required Size viewSize,
    required DisplayLayout? displayLayout,
    required ShellPopupPlacement configured,
  }) {
    final canvas = Offset.zero & viewSize;
    final output = displayLayout?.systemBarOutput;
    final outputRect = (output?.logicalRect ?? canvas).intersect(canvas);
    if (outputRect.isEmpty) {
      return null;
    }
    final bar = output == null || displayLayout == null
        ? Rect.zero
        : displayLayout.systemBarRectFor(output).intersect(outputRect);
    final side = bar.isEmpty
        ? SystemBarSide.hidden
        : displayLayout!.systemBarSide;
    // The output minus the bar only: the panel's far edge lines up with the
    // bar's trailing card, whatever padding maximized windows keep.
    final workArea = switch (side) {
      SystemBarSide.top => Rect.fromLTRB(
        outputRect.left,
        bar.bottom,
        outputRect.right,
        outputRect.bottom,
      ),
      SystemBarSide.bottom => Rect.fromLTRB(
        outputRect.left,
        outputRect.top,
        outputRect.right,
        bar.top,
      ),
      SystemBarSide.left => Rect.fromLTRB(
        bar.right,
        outputRect.top,
        outputRect.right,
        outputRect.bottom,
      ),
      SystemBarSide.right => Rect.fromLTRB(
        outputRect.left,
        outputRect.top,
        bar.left,
        outputRect.bottom,
      ),
      SystemBarSide.hidden => outputRect,
    };
    if (workArea.isEmpty) {
      return null;
    }
    final anchor = switch (side) {
      SystemBarSide.bottom => ShellPopupAnchor.bottomRight,
      SystemBarSide.left => ShellPopupAnchor.bottomLeft,
      SystemBarSide.right => ShellPopupAnchor.bottomRight,
      SystemBarSide.top || SystemBarSide.hidden => ShellPopupAnchor.topRight,
    };
    final panel = configured
        .copyWith(anchor: anchor, hoverTriggerEnabled: false)
        .resolve(workArea);
    if (panel.isEmpty) {
      return null;
    }
    final swipeWidth = math.min(
      DesktopMetrics.panelSwipeWidth,
      outputRect.shortestSide,
    );
    final (
      Rect reveal,
      Offset entry,
      double gap,
      Rect swipeRect,
      InputEdge edge,
    ) = switch (side) {
      SystemBarSide.bottom => (
        Rect.fromLTRB(panel.left, panel.top, panel.right, workArea.bottom),
        const Offset(0, 1),
        workArea.bottom - panel.bottom,
        Rect.fromLTRB(
          panel.left,
          outputRect.bottom - swipeWidth,
          outputRect.right,
          outputRect.bottom,
        ),
        InputEdge.bottom,
      ),
      SystemBarSide.left => (
        Rect.fromLTRB(workArea.left, panel.top, panel.right, panel.bottom),
        const Offset(-1, 0),
        panel.left - workArea.left,
        Rect.fromLTRB(
          outputRect.left,
          panel.top,
          outputRect.left + swipeWidth,
          outputRect.bottom,
        ),
        InputEdge.left,
      ),
      SystemBarSide.right => (
        Rect.fromLTRB(panel.left, panel.top, workArea.right, panel.bottom),
        const Offset(1, 0),
        workArea.right - panel.right,
        Rect.fromLTRB(
          outputRect.right - swipeWidth,
          panel.top,
          outputRect.right,
          outputRect.bottom,
        ),
        InputEdge.right,
      ),
      SystemBarSide.top || SystemBarSide.hidden => (
        Rect.fromLTRB(panel.left, workArea.top, panel.right, panel.bottom),
        const Offset(0, -1),
        panel.top - workArea.top,
        Rect.fromLTRB(
          panel.left,
          outputRect.top,
          outputRect.right,
          outputRect.top + swipeWidth,
        ),
        InputEdge.top,
      ),
    };
    final swipe = swipeRect.intersect(outputRect);
    return DesktopControlCenterGeometry(
      panel: panel,
      reveal: reveal,
      entryDirection: entry,
      entryGap: math.max(0.0, gap),
      swipe: swipe.isEmpty ? null : (rect: swipe, edge: edge),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopControlCenterGeometry &&
      other.panel == panel &&
      other.reveal == reveal &&
      other.entryDirection == entryDirection &&
      other.entryGap == entryGap &&
      other.swipe == swipe;

  @override
  int get hashCode =>
      Object.hash(panel, reveal, entryDirection, entryGap, swipe);
}

/// The control center's motion: it slides out from under the system bar and
/// back. One translation of an already painted panel per frame: no layout,
/// no rebuild of the panel, and the panel's one glass backdrop, clipped to
/// [DesktopControlCenterGeometry.reveal].
abstract final class DesktopControlCenterMotion {
  static const Duration open = Duration(milliseconds: 280);
  static const Duration close = Duration(milliseconds: 200);
  static const Curve openCurve = Curves.easeOutCubic;
  static const Curve closeCurve = Curves.easeInCubic;
}

/// Lays out and animates the control center in its reveal rectangle; place
/// it with `Positioned.fromRect(rect: geometry.reveal)`.
class DesktopControlCenter extends StatelessWidget {
  const DesktopControlCenter({
    super.key,
    required this.geometry,
    required this.visible,
    required this.durationScale,
    required this.child,
    this.onOpened,
  });

  final DesktopControlCenterGeometry geometry;
  final bool visible;
  final double durationScale;
  final VoidCallback? onOpened;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: geometry.panel.shift(-geometry.reveal.topLeft),
            child: DesktopPanelTransition(
              key: const ValueKey<String>('desktop-dashboard-panel'),
              inputDebugLabel: 'Desktop dashboard',
              keyboardPolicy: ShellKeyboardPolicy.capture,
              maintainState: true,
              prebuild: true,
              visible: visible,
              entryDirection: geometry.entryDirection,
              entryDistance: geometry.entryGap,
              durationScale: durationScale,
              openingDuration: DesktopControlCenterMotion.open,
              closingDuration: DesktopControlCenterMotion.close,
              curve: DesktopControlCenterMotion.openCurve,
              reverseCurve: DesktopControlCenterMotion.closeCurve,
              onOpened: onOpened,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
