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

/// Every app, in a full-screen glass sheet that rises from the bottom as
/// [openness] goes from 0 to 1: the shell's one search sized for fingers
/// ([ShellSearchStyle.touch]). With nothing typed it shows the apps started
/// last and every app by name; typing finds apps, then open windows.
/// Pulled down from the top of its list, it follows the finger up and down
/// until the finger lifts, and [onDrag] and [onDragEnd] report it.
class HomeAppDrawer extends ConsumerStatefulWidget {
  const HomeAppDrawer({
    super.key,
    required this.openness,
    required this.columns,
    required this.onLaunch,
    required this.onOpenWindow,
    required this.onDrag,
    required this.onDragEnd,
    this.keyboardInset = 0,
  });

  final Animation<double> openness;
  final int columns;

  /// Opens an app from its icon, in global coordinates.
  final ShellSearchAppCallback onLaunch;

  /// Brings a window found by the search to the front.
  final ShellSearchWindowCallback onOpenWindow;

  /// Downward travel, in logical pixels.
  final ValueChanged<double> onDrag;

  /// The release's downward velocity, in logical pixels per second.
  final ValueChanged<double> onDragEnd;

  /// How much of the bottom the on-screen keyboard covers.
  final double keyboardInset;

  @override
  ConsumerState<HomeAppDrawer> createState() => _HomeAppDrawerState();
}

class _HomeAppDrawerState extends ConsumerState<HomeAppDrawer> {
  final _scroll = ScrollController();
  late final ShellSearchSession _session =
      ShellSearchSession(debugLabel: 'home drawer search')
        ..onActivate = _activate
        ..fieldIconRect = _fieldIconRect;

  /// The finger that moves the list, or the sheet once it pulls.
  int? _pointer;

  /// The list was at its top and the finger moved down: the finger holds
  /// the sheet, and the list stays still, until it lifts.
  bool _pulling = false;
  late VelocityTracker _velocity;

  /// A finger must move this far down before it pulls the sheet, so a tap
  /// on the field or a tile that wobbles does not.
  static const double _pullSlop = 12;
  double _downward = 0;

  late final _physics = _SheetPullPhysics(pulling: () => _pulling);

  @override
  void initState() {
    super.initState();
    _session.focus.addListener(_focusChanged);
    widget.openness.addStatusListener(_opennessChanged);
  }

  @override
  void didUpdateWidget(covariant HomeAppDrawer oldWidget) {
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

  /// Closed, the drawer forgets its search, and the keyboard goes with the
  /// field's focus.
  void _opennessChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _session.focus.unfocus();
    _session.start(focusField: false);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downward = 0;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _velocity.addPosition(event.timeStamp, event.position);
    _downward += event.delta.dy;
    if (!_pulling &&
        event.delta.dy > 0 &&
        _downward > _pullSlop &&
        (!_scroll.hasClients ||
            _scroll.position.pixels <= _scroll.position.minScrollExtent)) {
      _pulling = true;
      // Pulled away, the drawer takes the keyboard with it.
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

  /// Enter acts on the best match: an app starts, a window comes to the
  /// front. The icon it grows from is the field's start.
  void _activate(ShellSearchTarget target, Rect from) {
    switch (target) {
      case ShellSearchAppTarget(:final app):
        widget.onLaunch(app, from);
      case ShellSearchWindowTarget(:final window):
        widget.onOpenWindow(window, from);
    }
  }

  final _field = GlobalKey();

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
        // No fade: glass under an opacity layer has nothing to blur. Closed,
        // it paints nothing, yet a finger that pulled it down holds it.
        return Offstage(
          offstage: openness == 0,
          child: FractionalTranslation(
            translation: Offset(0, 1 - openness),
            child: sheet,
          ),
        );
      },
      child: ShellInputRegion(
        debugLabel: 'home drawer search',
        // Typed keys, the software keyboard's too, go to the field.
        active: _session.focus.hasFocus,
        pointerPolicy: ShellPointerPolicy.none,
        keyboardPolicy: ShellKeyboardPolicy.capture,
        child: Semantics(
          container: true,
          label: context.l10n.homeDrawerSemantics,
          child: ShellBackdropBlur(
            separateChild: true,
            blur: theme.effectivePanelOpacity < 1.0,
            borderRadius: BorderRadius.zero,
            // Dark like the wallpaper under home: the labels are white.
            child: ColoredBox(
              color: ShellMediaColors.darkness.withValues(alpha: 0.55),
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: Column(
                  children: [
                    SizedBox(height: padding.top + 56),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ShellSearchField(
                        key: _field,
                        style: ShellSearchStyle.touch,
                        controller: _session.query,
                        focusNode: _session.focus,
                        hint: context.l10n.homeSearchHint,
                        onSubmitted: _session.submit,
                      ),
                    ),
                    Expanded(
                      child: ShellSearchResults(
                        session: _session,
                        style: ShellSearchStyle.touch,
                        windows: ShellSearchWindows.phone,
                        columns: widget.columns,
                        controller: _scroll,
                        physics: _physics,
                        padding: EdgeInsets.only(
                          top: 16,
                          bottom: padding.bottom + 72 + widget.keyboardInset,
                        ),
                        onLaunchApp: widget.onLaunch,
                        onOpenWindow: widget.onOpenWindow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The list's scrolling, held still while the finger pulls the sheet. A
/// list shorter than the screen still takes the drag.
class _SheetPullPhysics extends ClampingScrollPhysics {
  const _SheetPullPhysics({required this.pulling, super.parent});

  final bool Function() pulling;

  @override
  _SheetPullPhysics applyTo(ScrollPhysics? ancestor) =>
      _SheetPullPhysics(pulling: pulling, parent: buildParent(ancestor));

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
