import 'dart:async';

import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/tokens.dart';

import '../../search/shell_search_backend.dart';
import '../../search/shell_search_view.dart';
import '../../t3_code/t3_code_controller.dart';

/// Search over home, pulled down from the middle of home as on iPadOS: a
/// glass sheet that comes down from the top as [openness] goes from 0 to 1,
/// with the shell's one search sized for fingers, as in the app drawer.
/// Before anything is typed it shows the apps started last and every app;
/// typing finds apps, then open windows.
///
/// Once open, its field takes the focus, which brings up the on-screen
/// keyboard. Pulled up from the end of its list, or from its field, it
/// follows the finger until the finger lifts, and [onDrag] and [onDragEnd]
/// report it; a tap on empty space or on Cancel closes it ([onClose]).
class HomeSearchSheet extends ConsumerStatefulWidget {
  const HomeSearchSheet({
    super.key,
    required this.openness,
    required this.columns,
    required this.onLaunch,
    required this.onOpenWindow,
    required this.onClose,
    required this.onDrag,
    required this.onDragEnd,
    this.keyboardInset = 0,
    this.aiEnabled = true,
  });

  final Animation<double> openness;
  final int columns;
  final ShellSearchAppCallback onLaunch;
  final ShellSearchWindowCallback onOpenWindow;
  final VoidCallback onClose;

  /// Downward travel, in logical pixels.
  final ValueChanged<double> onDrag;

  /// The release's downward velocity, in logical pixels per second.
  final ValueChanged<double> onDragEnd;

  /// How much of the bottom the on-screen keyboard covers.
  final double keyboardInset;
  final bool aiEnabled;

  @override
  ConsumerState<HomeSearchSheet> createState() => _HomeSearchSheetState();
}

class _HomeSearchSheetState extends ConsumerState<HomeSearchSheet> {
  final _scroll = ScrollController();
  late final ShellSearchSession _session =
      ShellSearchSession(debugLabel: 'home search')
        ..onActivate = _activate
        ..onDismiss = _dismiss
        ..onAskAi = _askAi
        ..fieldIconRect = _fieldIconRect;
  final _field = GlobalKey();

  int? _pointer;
  bool _pulling = false;
  double _upward = 0;
  late VelocityTracker _velocity;
  static const double _pullSlop = 12;

  late final _physics = _SheetPushPhysics(pulling: () => _pulling);

  @override
  void initState() {
    super.initState();
    _session.focus.addListener(_focusChanged);
    widget.openness.addStatusListener(_opennessChanged);
  }

  @override
  void didUpdateWidget(covariant HomeSearchSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.openness, widget.openness)) {
      oldWidget.openness.removeStatusListener(_opennessChanged);
      widget.openness.addStatusListener(_opennessChanged);
    }
  }

  @override
  void dispose() {
    widget.openness.removeStatusListener(_opennessChanged);
    _scroll.dispose();
    _session.focus.removeListener(_focusChanged);
    _session.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  /// Esc with nothing typed closes the search, as Cancel does.
  void _dismiss() => widget.onClose();

  void _askAi(String prompt) {
    widget.onClose();
    unawaited(
      ref.read(t3CodeControllerProvider.notifier).sendTextPrompt(prompt),
    );
  }

  /// Open, the field takes the focus and the keyboard comes up; on the way
  /// out the keyboard goes, and closed the search starts afresh.
  void _opennessChanged(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        if (!_pulling) _session.focus.requestFocus();
      case AnimationStatus.reverse:
        _session.focus.unfocus();
      case AnimationStatus.dismissed:
        _session.focus.unfocus();
        _session.start(focusField: false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      case AnimationStatus.forward:
        break;
    }
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _upward = 0;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _velocity.addPosition(event.timeStamp, event.position);
    _upward -= event.delta.dy;
    if (!_pulling &&
        event.delta.dy < 0 &&
        _upward > _pullSlop &&
        (!_scroll.hasClients ||
            _scroll.position.pixels >= _scroll.position.maxScrollExtent)) {
      _pulling = true;
      _session.focus.unfocus();
    }
    if (_pulling) widget.onDrag(event.delta.dy);
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (!_pulling) return;
    _pulling = false;
    widget.onDragEnd(
      event is PointerUpEvent ? _velocity.getVelocity().pixelsPerSecond.dy : 0,
    );
  }

  /// Enter acts on the best match from the field's magnifier.
  void _activate(ShellSearchTarget target, Rect from) {
    switch (target) {
      case ShellSearchAppTarget(:final app):
        widget.onLaunch(app, from);
      case ShellSearchWindowTarget(:final window):
        widget.onOpenWindow(window, from);
    }
  }

  Rect _fieldIconRect() {
    final field = shellSearchGlobalRect(_field.currentContext);
    return Rect.fromLTWH(
      field.left + 12,
      field.top + (field.height - 36) / 2,
      36,
      36,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return AnimatedBuilder(
      animation: widget.openness,
      builder: (context, sheet) {
        final openness = widget.openness.value;
        return Offstage(
          offstage: openness == 0,
          child: FractionalTranslation(
            translation: Offset(0, openness - 1),
            child: sheet,
          ),
        );
      },
      child: ShellInputRegion(
        debugLabel: 'home search',
        active: _session.focus.hasFocus,
        pointerPolicy: ShellPointerPolicy.none,
        keyboardPolicy: ShellKeyboardPolicy.capture,
        child: Semantics(
          container: true,
          label: context.l10n.homeSearchSemantics,
          child: ShellBackdropBlur(
            separateChild: true,
            blur: theme.effectivePanelOpacity < 1.0,
            borderRadius: BorderRadius.zero,
            child: ColoredBox(
              color: ShellMediaColors.darkness.withValues(alpha: 0.55),
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: GestureDetector(
                  // Taps that no row, tile or field takes: empty space.
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                  child: Column(
                    children: [
                      SizedBox(height: padding.top + 56),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: ListenableBuilder(
                                listenable: _session,
                                builder: (context, _) {
                                  return ShellSearchField(
                                    key: _field,
                                    style: ShellSearchStyle.touch,
                                    controller: _session.query,
                                    focusNode: _session.focus,
                                    hint: context.l10n.homeSearchHint,
                                    onSubmitted: _session.submit,
                                    aiMode: _session.aiMode,
                                    onAskAi: widget.aiEnabled
                                        ? _session.toggleAiMode
                                        : null,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            _CancelButton(onTap: widget.onClose),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ShellSearchResults(
                          session: _session,
                          style: ShellSearchStyle.touch,
                          windows: ShellSearchWindows.phone,
                          columns: widget.columns,
                          onLaunchApp: widget.onLaunch,
                          onOpenWindow: widget.onOpenWindow,
                          controller: _scroll,
                          physics: _physics,
                          padding: EdgeInsets.only(
                            top: 16,
                            bottom: padding.bottom + 48 + widget.keyboardInset,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: ShellSearchMetrics.touch.fieldHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                context.l10n.commonCancel,
                style: TextStyle(
                  color: ShellMediaColors.lightForeground,
                  fontSize: ShellSearchMetrics.touch.nameSize,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The list's scrolling, held still while the finger pushes the sheet up.
class _SheetPushPhysics extends ClampingScrollPhysics {
  const _SheetPushPhysics({required this.pulling, super.parent});

  final bool Function() pulling;

  @override
  _SheetPushPhysics applyTo(ScrollPhysics? ancestor) =>
      _SheetPushPhysics(pulling: pulling, parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      pulling() ? 0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => pulling() ? null : super.createBallisticSimulation(position, velocity);
}
