import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/tokens.dart';

import '../home_search.dart';
import 'home_app_tile.dart';
import 'home_search_view.dart';

/// Every app on home, folders opened, by name, in a full-screen glass sheet
/// that rises from the bottom as [openness] goes from 0 to 1, with a search
/// field on top. Typing in it lists the matching open windows and apps
/// instead ([HomeSearchResults]). Pulled down from the top of its list, it
/// follows the finger up and down until the finger lifts, and [onDrag] and
/// [onDragEnd] report it.
class HomeAppDrawer extends ConsumerStatefulWidget {
  const HomeAppDrawer({
    super.key,
    required this.openness,
    required this.apps,
    required this.columns,
    required this.onLaunch,
    required this.onOpenWindow,
    required this.onDrag,
    required this.onDragEnd,
    this.keyboardInset = 0,
  });

  final Animation<double> openness;
  final Iterable<HomeGridItem> apps;
  final int columns;

  /// Opens an app from its icon, in global coordinates.
  final HomeLaunchCallback onLaunch;

  /// Brings a window found by the search to the front.
  final HomeOpenWindowCallback onOpenWindow;

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
  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'home drawer search');

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
    _query.addListener(_queryChanged);
    _focus.addListener(_focusChanged);
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
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _shownQuery = '';

  void _queryChanged() {
    if (_query.text == _shownQuery) return;
    setState(() => _shownQuery = _query.text);
  }

  void _focusChanged() => setState(() {});

  /// Closed, the drawer forgets its search, and the keyboard goes with the
  /// field's focus.
  void _opennessChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _focus.unfocus();
    _query.clear();
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
      _focus.unfocus();
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

  /// Enter acts on the best match: a window comes to the front, an app
  /// starts. The icon it grows from is the field's start.
  void _submit(HomeSearchMatches matches) {
    final from = _fieldIconRect();
    switch (matches.first) {
      case final HomeSearchWindow window:
        widget.onOpenWindow(window, from);
      case final HomeGridItem app:
        widget.onLaunch(app, from);
    }
  }

  final _field = GlobalKey();

  Rect _fieldIconRect() {
    final field = globalRectOf(_field);
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
    final query = _shownQuery;
    final searching = query.trim().isNotEmpty;
    final HomeSearchMatches? matches;
    if (searching) {
      matches = homeSearchCatalog(context, ref, widget.apps).search(query);
    } else {
      matches = null;
    }
    final names = {
      for (final app in widget.apps)
        app: HomeAppTile.nameOf(context, app).toLowerCase(),
    };
    final apps = names.keys.toList()
      ..sort((a, b) => names[a]!.compareTo(names[b]!));
    final listPadding = EdgeInsets.only(
      top: 16,
      bottom: padding.bottom + 72 + widget.keyboardInset,
    );
    final Widget list = matches != null
        ? HomeSearchResults(
            key: const ValueKey('home drawer results'),
            matches: matches,
            columns: widget.columns,
            onLaunch: widget.onLaunch,
            onOpenWindow: widget.onOpenWindow,
            controller: _scroll,
            physics: _physics,
            padding: listPadding,
          )
        : GridView.builder(
            key: const ValueKey('home drawer apps'),
            controller: _scroll,
            physics: _physics,
            padding: listPadding.add(
              const EdgeInsets.symmetric(horizontal: 20),
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.columns,
              mainAxisExtent: HomeGridLayout.minTileHeight,
              mainAxisSpacing: 18,
              crossAxisSpacing: HomeGridLayout.gridGap,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) => HomeLaunchTile(
              key: ValueKey(apps[index].id),
              app: apps[index],
              onLaunch: widget.onLaunch,
            ),
          );
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
        active: _focus.hasFocus,
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
                      child: HomeSearchField(
                        key: _field,
                        controller: _query,
                        focusNode: _focus,
                        onSubmitted: () {
                          if (matches != null) _submit(matches);
                        },
                      ),
                    ),
                    Expanded(child: list),
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
