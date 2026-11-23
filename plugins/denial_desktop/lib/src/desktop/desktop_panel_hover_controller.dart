import 'dart:async';

/// Coordinates hover-driven panel dismissal with the panel's entrance motion.
///
/// Only a panel the pointer opened by entering its hot edge closes when the
/// pointer leaves it again. A panel opened by a key, a gesture, a click or a
/// finger stays open until it is dismissed: the pointer passing over and out
/// of it, or the compositor ending the shell's mouse lifecycle (a pointer
/// device going away), leaves it open, as Launchpad does on macOS.
///
/// Leaving an edge trigger while the panel is still entering records a pending
/// close instead of starting the ordinary hover timer. The timer begins only
/// once the transition reports completion, giving the pointer the full
/// [closeDelay] to enter the settled panel. Later exits use the same delay.
class DesktopPanelHoverController {
  DesktopPanelHoverController({
    required this.onClose,
    this.closeDelay = const Duration(milliseconds: 220),
  });

  final void Function() onClose;
  final Duration closeDelay;

  Timer? _closeTimer;
  bool _opening = false;
  bool _closePending = false;
  bool _disposed = false;
  bool _openedByHover = false;

  /// Whether leaving the open panel closes it: the pointer opened it.
  bool get dismissesOnHoverExit => _openedByHover;

  /// A closed panel starts opening. [byHover]: the pointer opened it by
  /// entering its hot edge.
  void beginOpening({required bool byHover}) {
    if (_disposed) {
      return;
    }
    _opening = true;
    _openedByHover = byHover;
    cancelClose();
  }

  void openingCompleted() {
    if (_disposed || !_opening) {
      return;
    }
    _opening = false;
    if (!_closePending) {
      return;
    }
    _closePending = false;
    _startCloseTimer(closeDelay);
  }

  void cancelClose() {
    if (_disposed) {
      return;
    }
    _closePending = false;
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  void scheduleClose() {
    if (_disposed || !_openedByHover) {
      return;
    }
    _closeTimer?.cancel();
    _closeTimer = null;
    if (_opening) {
      _closePending = true;
      return;
    }
    _closePending = false;
    _startCloseTimer(closeDelay);
  }

  void reset() {
    if (_disposed) {
      return;
    }
    _opening = false;
    _openedByHover = false;
    cancelClose();
  }

  void _startCloseTimer(Duration delay) {
    _closeTimer = Timer(delay, () {
      _closeTimer = null;
      if (!_disposed) {
        onClose();
      }
    });
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _closePending = false;
    _closeTimer?.cancel();
    _closeTimer = null;
  }
}
