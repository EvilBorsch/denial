import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/rendering.dart';

import '../widgets/desktop_visibility_transition.dart';
import 'desktop_plugin_window_frame.dart';
import 'desktop_workspace.dart';

/// Publishes whether a window has finished moving into overview.
///
/// The position animation owns this signal so preview emphasis follows its
/// actual completion rather than a parallel timer that can drift or ignore an
/// interrupted transition.
class DesktopOverviewTransitionStatus
    extends InheritedNotifier<ValueNotifier<bool>> {
  const DesktopOverviewTransitionStatus({
    super.key,
    required ValueNotifier<bool> completed,
    required super.child,
  }) : super(notifier: completed);

  static bool completedOf(BuildContext context) {
    final status = context
        .dependOnInheritedWidgetOfExactType<DesktopOverviewTransitionStatus>();
    return status?.notifier?.value ?? true;
  }
}

/// Pointer interaction for a window preview in the desktop overview.
///
/// Overview previews retain the window's real layout size and use a paint
/// transform to fit it into the arranged overview frame. Pan deltas therefore
/// have to be measured in global coordinates: Flutter's local [DragUpdateDetails.delta]
/// is transformed back through the preview scale and would make a scaled-down
/// window move farther than the pointer.
///
/// In the screens overview of the full-screen apps layout a finger drags a
/// window only after a long press, so a touch can still tap; a mouse drags
/// at once, as in every overview.
class DesktopOverviewPreviewInteraction extends ConsumerStatefulWidget {
  const DesktopOverviewPreviewInteraction({
    super.key,
    required this.compositorRoutesInput,
    this.shellFrameMargins,
    required this.overviewActive,
    required this.overview,
    required this.desktopWidget,
    required this.dragging,
    this.selected = false,
    this.previewScale = 1.0,
    required this.label,
    required this.onTap,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  /// The compositor hands this window's input to the client itself, by its
  /// surfaces and their input regions. Only what no client takes, such as a
  /// click through a desktop pet's transparent part, reaches the shell.
  final bool compositorRoutesInput;

  /// The sides of the window where a plugin's frame takes the pointer. The
  /// compositor gives those to the shell, so they are not let through.
  final EdgeInsets? shellFrameMargins;
  final bool overviewActive;
  final bool overview;
  final bool desktopWidget;
  final bool dragging;
  final bool selected;

  /// How much the overview shrinks the window: the selection ring is drawn
  /// inside the window, so its width is divided by this to stay four logical
  /// pixels wide on screen.
  final double previewScale;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final Widget child;

  @override
  ConsumerState<DesktopOverviewPreviewInteraction> createState() =>
      _DesktopOverviewPreviewInteractionState();
}

class _DesktopOverviewPreviewInteractionState
    extends ConsumerState<DesktopOverviewPreviewInteraction> {
  static const Set<PointerDeviceKind> _pointerDevices = <PointerDeviceKind>{
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  static const double _emphasizedScale = 1.018;
  static const double _selectionRingWidth = 4.0;

  bool _hovered = false;
  Offset? _lastGlobalDragPosition;

  @override
  void didUpdateWidget(covariant DesktopOverviewPreviewInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.overview && !widget.desktopWidget) || widget.dragging) {
      _hovered = false;
    }
    if (!widget.overview) {
      _lastGlobalDragPosition = null;
    }
  }

  void _setHovered(bool hovered) {
    if ((!widget.overview && !widget.desktopWidget) || _hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  void _startDrag(DragStartDetails details) => _startAt(details.globalPosition);

  void _updateDrag(DragUpdateDetails details) =>
      _moveTo(details.globalPosition);

  void _startAt(Offset globalPosition) {
    _lastGlobalDragPosition = globalPosition;
    widget.onDragStart();
  }

  void _moveTo(Offset globalPosition) {
    final previousPosition = _lastGlobalDragPosition;
    _lastGlobalDragPosition = globalPosition;
    if (previousPosition != null) {
      widget.onDragUpdate(globalPosition - previousPosition);
    }
  }

  Widget _gestures({
    required bool screensOverview,
    required bool interactive,
    required Widget child,
  }) {
    if (screensOverview) {
      return _screensGestures(interactive: interactive, child: child);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: interactive ? widget.onTap : null,
      onPanStart: widget.overview ? _startDrag : null,
      onPanUpdate: widget.overview ? _updateDrag : null,
      onPanEnd: widget.overview ? (_) => _endDrag() : null,
      onPanCancel: widget.overview ? _cancelDrag : null,
      child: child,
    );
  }

  /// A mouse pans at once; a finger presses long first.
  Widget _screensGestures({required bool interactive, required Widget child}) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) =>
                  recognizer.onTap = interactive ? widget.onTap : null,
            ),
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(supportedDevices: _pointerDevices),
              (recognizer) => recognizer
                ..onStart = _startDrag
                ..onUpdate = _updateDrag
                ..onEnd = ((_) => _endDrag())
                ..onCancel = _cancelDrag,
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                supportedDevices: const <PointerDeviceKind>{
                  PointerDeviceKind.touch,
                },
              ),
              (recognizer) => recognizer
                ..onLongPressStart = ((details) =>
                    _startAt(details.globalPosition))
                ..onLongPressMoveUpdate = ((details) =>
                    _moveTo(details.globalPosition))
                ..onLongPressEnd = ((_) => _endDrag())
                ..onLongPressCancel = _cancelDrag,
            ),
      },
      child: child,
    );
  }

  void _endDrag() {
    _lastGlobalDragPosition = null;
    widget.onDragEnd();
  }

  void _cancelDrag() {
    _lastGlobalDragPosition = null;
    widget.onDragCancel();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.overviewActive &&
        widget.overview &&
        event.buttons == kMiddleMouseButton) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewTransitionCompleted =
        DesktopOverviewTransitionStatus.completedOf(context);
    final hovered =
        (widget.overview || widget.desktopWidget) &&
        !widget.dragging &&
        _hovered;
    final emphasized = widget.overview
        ? overviewTransitionCompleted && (widget.selected || hovered)
        : hovered;
    final interactive =
        (widget.overviewActive && widget.overview) ||
        (!widget.overviewActive && widget.desktopWidget);
    final screensOverview =
        widget.overview &&
        ref.watch(
          desktopWorkspaceProvider.select(
            (state) => state.overview?.workspaces?.screens != null,
          ),
        );
    // Outside the overview a client window's preview has nothing to do with
    // the pointer. Whatever reaches the shell inside it belongs to the shell
    // below, such as the top bar under a window that lets clicks through.
    return DesktopFrameMarginsHitTest(
      enabled: widget.compositorRoutesInput && !interactive,
      margins: widget.shellFrameMargins,
      child: _preview(
        context,
        interactive,
        emphasized,
        screensOverview: screensOverview,
      ),
    );
  }

  Widget _preview(
    BuildContext context,
    bool interactive,
    bool emphasized, {
    required bool screensOverview,
  }) {
    return Semantics(
      button: interactive,
      selected: widget.overview ? widget.selected : null,
      label: interactive ? widget.label : null,
      child: MouseRegion(
        cursor: interactive ? ShellMouseCursors.link : ShellMouseCursors.normal,
        onEnter: interactive ? (_) => _setHovered(true) : null,
        onExit: interactive ? (_) => _setHovered(false) : null,
        child: Listener(
          onPointerDown: _handlePointerDown,
          child: _gestures(
            screensOverview: screensOverview,
            interactive: interactive,
            child: AnimatedScale(
              duration: Motion.tile,
              curve: emphasized
                  ? Motion.md3EmphasizedDecelerate
                  : Motion.md3EmphasizedAccelerate,
              scale: emphasized ? _emphasizedScale : 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  IgnorePointer(
                    child: DesktopVisibilityFade(
                      // The ring keeps its shape and fades by opacity: the
                      // compositor then draws the one recorded ring at each
                      // step of the fade, while the window moves, instead of
                      // a new window-sized picture every frame. Unselected,
                      // nothing is painted at all.
                      child: AnimatedOpacity(
                        duration: Motion.tile,
                        curve: Motion.standard,
                        opacity: widget.selected ? 1.0 : 0.0,
                        child: CustomPaint(
                          painter: _SelectionRingPainter(
                            color: context.shellTheme.accent,
                            width:
                                _selectionRingWidth /
                                widget.previewScale.clamp(0.05, 4.0),
                            radius: context.shellTheme.windowRadius,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The selection ring: a rounded stroke inside the preview's edge, as a
/// uniform [Border] with a radius paints it.
///
/// It is drawn in four bands (top and bottom with the corners, then the two
/// sides), each clipped to its own part. The ring's paint region is then
/// those bands rather than the whole window, and the compositor blends only
/// them, not the transparent inside.
class _SelectionRingPainter extends CustomPainter {
  const _SelectionRingPainter({
    required this.color,
    required this.width,
    required this.radius,
  });

  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0 || size.isEmpty) return;
    final ring = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(width / 2),
      Radius.circular(math.max(0.0, radius - width / 2)),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    // The corners reach as far in as the radius, the sides only the width;
    // the bands take a little more for the inner edge's antialiasing.
    const fringe = 2.0;
    final band = math.min(math.max(radius, width) + fringe, size.height / 2);
    final side = math.min(width + fringe, size.width / 2);
    final bands = [
      Rect.fromLTRB(0, 0, size.width, band),
      Rect.fromLTRB(0, size.height - band, size.width, size.height),
      Rect.fromLTRB(0, band, side, size.height - band),
      Rect.fromLTRB(size.width - side, band, size.width, size.height - band),
    ];
    for (final rect in bands) {
      if (rect.isEmpty) continue;
      canvas
        ..save()
        // Hard clips meet without a seam or a pixel blended twice.
        ..clipRect(rect, doAntiAlias: false)
        ..drawRRect(ring, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_SelectionRingPainter oldDelegate) =>
      color != oldDelegate.color ||
      width != oldDelegate.width ||
      radius != oldDelegate.radius;
}

/// How much a window laid out in [layout] is shrunk to show in [shown].
double desktopPreviewScale(Rect shown, Rect layout) {
  if (layout.width <= 0 || layout.height <= 0) return 1.0;
  final scale = shown.width / layout.width;
  final vertical = shown.height / layout.height;
  return scale < vertical ? scale : vertical;
}
