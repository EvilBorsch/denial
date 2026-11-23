import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/rendering.dart';

import '../widgets/desktop_visibility_transition.dart';
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
    required this.overviewActive,
    required this.overview,
    required this.desktopWidget,
    required this.dragging,
    this.selected = false,
    required this.label,
    required this.onTap,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.child,
  });

  final bool overviewActive;
  final bool overview;
  final bool desktopWidget;
  final bool dragging;
  final bool selected;
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
                      child: AnimatedContainer(
                        duration: Motion.tile,
                        curve: Motion.standard,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: context.shellTheme.accent.withValues(
                              alpha: widget.selected ? 1.0 : 0.0,
                            ),
                            width: widget.selected ? 2.0 : 0.0,
                          ),
                          borderRadius: BorderRadius.circular(
                            context.shellTheme.windowRadius,
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
