import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../launcher/home_grid_geometry.dart';
import '../launcher/widgets/home_item_icon.dart';
import '../launcher/widgets/home_tiles.dart';
import '../launcher/widgets/launcher_icon.dart';
import '../launcher/window_application.dart';
import 'shell_search_backend.dart';

// The shell's one search UI (eb19): a field and, under it, the apps and the
// open windows the backend finds. With nothing typed it shows the apps
// started last and every app, a scrollable grid as in Launchpad. The search
// over the desktop (bare Super, Super+S, Alt+F, four fingers up) shows it on
// a glass panel for the pointer and the keyboard; the tablet's app drawer
// and pull-down search show it over the wallpaper, sized for fingers.

/// Where the search is shown, which sets its sizes and colours.
enum ShellSearchStyle {
  /// On a panel over the desktop, for the pointer and the keyboard.
  desktop,

  /// Over the tablet's wallpaper, for fingers.
  touch,
}

/// The search's sizes, in logical pixels at the shell's scale (the tablet
/// panel is 1357×960).
@immutable
class ShellSearchMetrics {
  const ShellSearchMetrics._({
    required this.fieldHeight,
    required this.fieldMaxWidth,
    required this.fieldTextSize,
    required this.headerExtent,
    required this.headerTextSize,
    required this.tileExtent,
    required this.minTileWidth,
    required this.tileSpacing,
    required this.tileGap,
    required this.iconSize,
    required this.nameSize,
    required this.rowHeight,
    required this.rowIcon,
    required this.rowTitleSize,
    required this.rowDetailSize,
    required this.contentMaxWidth,
    required this.sidePadding,
  });

  static const desktop = ShellSearchMetrics._(
    fieldHeight: 48,
    fieldMaxWidth: double.infinity,
    fieldTextSize: 18,
    headerExtent: 34,
    headerTextSize: 13,
    tileExtent: 108,
    minTileWidth: 104,
    tileSpacing: 6,
    tileGap: 6,
    iconSize: 56,
    nameSize: 12,
    rowHeight: 56,
    rowIcon: 34,
    rowTitleSize: 16,
    rowDetailSize: 13,
    contentMaxWidth: double.infinity,
    sidePadding: 4,
  );

  static const touch = ShellSearchMetrics._(
    fieldHeight: 52,
    fieldMaxWidth: 720,
    fieldTextSize: 19,
    headerExtent: 44,
    headerTextSize: 15,
    tileExtent: HomeGridLayout.minTileHeight,
    minTileWidth: 0,
    tileSpacing: 18,
    tileGap: HomeGridLayout.gridGap,
    iconSize: 0,
    nameSize: 17,
    rowHeight: 64,
    rowIcon: 44,
    rowTitleSize: 15,
    rowDetailSize: 15,
    contentMaxWidth: 960,
    sidePadding: 20,
  );

  static ShellSearchMetrics of(ShellSearchStyle style) => switch (style) {
    ShellSearchStyle.desktop => desktop,
    ShellSearchStyle.touch => touch,
  };

  final double fieldHeight;
  final double fieldMaxWidth;
  final double fieldTextSize;
  final double headerExtent;
  final double headerTextSize;

  /// A grid tile's height.
  final double tileExtent;

  /// The narrowest a tile gets before the grid drops a column (desktop).
  final double minTileWidth;

  /// Between grid rows.
  final double tileSpacing;

  /// Between grid columns.
  final double tileGap;
  final double iconSize;
  final double nameSize;
  final double rowHeight;
  final double rowIcon;
  final double rowTitleSize;
  final double rowDetailSize;

  /// Rows and headers keep to this width in the middle (touch).
  final double contentMaxWidth;
  final double sidePadding;
}

/// What a surface does with a chosen result. [iconRect] is where the
/// result's icon is, in global coordinates; for Enter, the field's
/// magnifier.
typedef ShellSearchAppCallback = void Function(
  ShellSearchApp app,
  Rect iconRect,
);
typedef ShellSearchWindowCallback = void Function(
  ShellSearchOpenWindow window,
  Rect iconRect,
);

/// One search's state: the query, the keyboard's place in the results and
/// what the keys do. The surface that shows the search owns it.
class ShellSearchSession extends ChangeNotifier {
  ShellSearchSession({String debugLabel = 'shell-search'}) {
    focus = FocusNode(debugLabel: debugLabel, onKeyEvent: _key);
    query.addListener(_queryChanged);
  }

  final TextEditingController query = TextEditingController();
  late final FocusNode focus;

  /// Esc with nothing typed: the surface closes.
  VoidCallback? onDismiss;

  /// Enter: the surface acts on [target].
  void Function(ShellSearchTarget target, Rect iconRect)? onActivate;

  /// Sends the typed prompt to T3 Code AI (`full-access` in `~`).
  void Function(String prompt)? onAskAi;

  bool _aiMode = false;

  /// When true, Enter sends directly to T3 Code AI instead of launching an app.
  bool get aiMode => _aiMode;

  void setAiMode(bool value) {
    if (_aiMode == value) return;
    _aiMode = value;
    notifyListeners();
  }

  void toggleAiMode() {
    if (typing && onAskAi != null) {
      askAi();
      return;
    }
    setAiMode(!_aiMode);
    focusSoon();
  }

  void askAi() {
    final text = query.text.trim();
    if (text.isEmpty) {
      setAiMode(true);
      focusSoon();
      return;
    }
    onAskAi?.call(text);
  }

  /// Where the field's magnifier is, for Enter's [onActivate].
  Rect Function()? fieldIconRect;

  /// A key pressed while nothing is typed, before the search's own: the
  /// overview moves between its windows with the arrows. True when taken.
  bool Function(LogicalKeyboardKey key)? onKeyWithoutQuery;

  /// Enter while nothing is typed: the overview goes to its chosen window.
  VoidCallback? onSubmitWithoutQuery;

  String _shownQuery = '';

  /// The result the arrows chose; null for the default, the best one.
  String? _chosen;

  /// The results as last laid out: their keys in order, in rows.
  List<(String, ShellSearchTarget)> _targets = const [];
  List<List<int>> _rows = const [];
  String? _defaultKey;
  int _columns = 1;

  /// The result Enter acts on, as its key ('a:', 'r:' or 'w:' and the id).
  String? get highlighted => _chosen ?? _defaultKey;

  /// The result the arrows chose, as its key; null before they do.
  String? get chosen => _chosen;

  /// Something is typed.
  bool get typing => _shownQuery.trim().isNotEmpty;

  void _queryChanged() {
    if (query.text == _shownQuery) {
      return;
    }
    _shownQuery = query.text;
    // A new query starts again at its best result.
    _chosen = null;
    notifyListeners();
  }

  /// Empties the query and puts the keyboard into the field once it is laid
  /// out.
  void start({bool focusField = true}) {
    if (query.text.isNotEmpty) {
      query.clear();
    }
    _chosen = null;
    _aiMode = false;
    if (focusField) {
      focusSoon();
    }
  }

  void focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) {
        return;
      }
      focus.requestFocus();
      query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: query.text.length,
      );
    });
  }

  void clear() {
    query.clear();
    focus.requestFocus();
  }

  /// The result Enter acts on; null when there is none.
  ShellSearchTarget? get highlightedTarget {
    final key = highlighted;
    for (final (candidate, target) in _targets) {
      if (candidate == key) {
        return target;
      }
    }
    return null;
  }

  /// Enter: the chosen result, the best one unless the arrows chose another.
  void submit() {
    if (_aiMode && typing && onAskAi != null) {
      askAi();
      return;
    }
    if (!typing && onSubmitWithoutQuery != null) {
      onSubmitWithoutQuery!();
      return;
    }
    final key = highlighted;
    for (final (candidate, target) in _targets) {
      if (candidate == key) {
        onActivate?.call(target, fieldIconRect?.call() ?? Rect.zero);
        return;
      }
    }
  }

  void _layout({
    required List<(String, ShellSearchTarget)> targets,
    required List<List<int>> rows,
    required String? defaultKey,
    required int columns,
  }) {
    _targets = targets;
    _rows = rows;
    _defaultKey = defaultKey;
    _columns = columns;
    if (_chosen != null && !targets.any((target) => target.$1 == _chosen)) {
      _chosen = null;
    }
  }

  int? get _highlightedIndex {
    final key = highlighted;
    if (key == null) {
      return null;
    }
    final index = _targets.indexWhere((target) => target.$1 == key);
    return index < 0 ? null : index;
  }

  void _choose(int index) {
    if (_targets.isEmpty) {
      return;
    }
    final key = _targets[index.clamp(0, _targets.length - 1)].$1;
    if (key != _chosen) {
      _chosen = key;
      notifyListeners();
    }
  }

  void _step(int delta) {
    final current = _highlightedIndex;
    _choose(current == null ? 0 : current + delta);
  }

  void _stepRow(int delta) {
    if (_rows.isEmpty) {
      return;
    }
    final current = _highlightedIndex;
    if (current == null) {
      _choose(0);
      return;
    }
    final row = _rows.indexWhere((row) => row.contains(current));
    final int next = (row + delta).clamp(0, _rows.length - 1).toInt();
    if (next == row) {
      return;
    }
    final int column = _rows[row].indexOf(current) % math.max(1, _columns);
    final target = _rows[next];
    _choose(target[math.min(column, target.length - 1).toInt()]);
  }

  /// Up and Down (and Tab) step through the results; Left and Right too
  /// while nothing is typed, else they stay with the text. Esc clears the
  /// query, then closes.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        (shift || ctrl) &&
        typing &&
        onAskAi != null) {
      askAi();
      return KeyEventResult.handled;
    }
    // Enter submits through the field (onSubmitted), as typed text does.
    if (!typing &&
        key != LogicalKeyboardKey.escape &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter &&
        (onKeyWithoutQuery?.call(key) ?? false)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (event is! KeyDownEvent) {
        return KeyEventResult.handled;
      }
      if (query.text.isNotEmpty) {
        query.clear();
      } else {
        onDismiss?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _stepRow(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _stepRow(-1);
    } else if (key == LogicalKeyboardKey.tab) {
      _step(shift ? -1 : 1);
    } else if (!typing && key == LogicalKeyboardKey.arrowRight) {
      _step(1);
    } else if (!typing && key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    query
      ..removeListener(_queryChanged)
      ..dispose();
    focus.dispose();
    super.dispose();
  }
}

/// The search field: a magnifier, the query and a button that clears it.
class ShellSearchField extends StatelessWidget {
  const ShellSearchField({
    super.key,
    required this.style,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    this.onClear,
    this.onAskAi,
    this.aiMode = false,
    this.elevated = false,
  });

  final ShellSearchStyle style;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onAskAi;
  final bool aiMode;

  /// Desktop: drawn on its own over the overview, with a glass of its own;
  /// inside a panel it is a well of that panel.
  final bool elevated;

  static final List<TextInputFormatter> _inputFormatters =
      List<TextInputFormatter>.unmodifiable(<TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u001F\u007F]')),
      ]);

  @override
  Widget build(BuildContext context) => switch (style) {
    ShellSearchStyle.desktop => _desktop(context),
    ShellSearchStyle.touch => _touch(context),
  };

  void _clear() {
    if (onClear case final clear?) {
      clear();
    } else {
      controller.clear();
    }
  }

  Widget _desktop(BuildContext context) {
    const metrics = ShellSearchMetrics.desktop;
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final radius = BorderRadius.circular(metrics.fieldHeight / 2);
    final textStyle = theme.text.base.copyWith(
      fontSize: metrics.fieldTextSize,
      height: 1.2,
      decoration: TextDecoration.none,
    );
    Widget field = SizedBox(
      height: metrics.fieldHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              aiMode ? Icons.auto_awesome_rounded : Icons.search_rounded,
              size: 24,
              color: aiMode ? theme.accentPalette.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, child) => Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    if (controller.text.isEmpty)
                      IgnorePointer(
                        child: Text(
                          aiMode ? 'Спросить T3 Code AI...' : hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(color: colors.textTertiary),
                        ),
                      ),
                    child!,
                  ],
                ),
                child: EditableText(
                  controller: controller,
                  focusNode: focusNode,
                  mouseCursor: ShellMouseCursors.text,
                  maxLines: 1,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  // Keep the focus on submit: the surface stays open when
                  // Enter finds nothing.
                  onEditingComplete: () {},
                  onSubmitted: (_) => onSubmitted(),
                  style: textStyle.copyWith(color: colors.textPrimary),
                  cursorColor: theme.accentPalette.primary,
                  backgroundCursorColor: colors.textSecondary,
                  selectionColor: theme.accentPalette.selection,
                  inputFormatters: _inputFormatters,
                ),
              ),
            ),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.text.isEmpty
                  ? const SizedBox.shrink()
                  : Semantics(
                      button: true,
                      label: l10n.desktopClearSearch,
                      child: MouseRegion(
                        cursor: ShellMouseCursors.link,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _clear,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 8),
                            child: Icon(
                              Icons.cancel_rounded,
                              size: 22,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            if (onAskAi != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Semantics(
                  button: true,
                  label: 'Спросить T3 Code AI',
                  child: MouseRegion(
                    cursor: ShellMouseCursors.link,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAskAi,
                      child: AnimatedContainer(
                        duration: Motion.pill,
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(
                          color: aiMode
                              ? theme.accentPalette.primary
                              : theme.accentPalette.container,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.accentPalette.primary.withValues(
                              alpha: aiMode ? 0.9 : 0.45,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 15,
                              color: aiMode
                                  ? Colors.white
                                  : theme.accentPalette.onContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'AI',
                              style: TextStyle(
                                color: aiMode
                                    ? Colors.white
                                    : theme.accentPalette.onContainer,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    field = DecoratedBox(
      decoration: BoxDecoration(
        color: elevated
            ? theme.panelColor(colors.panelBackground)
            : theme.cardColor(colors.surfaceContainerHigh),
        borderRadius: radius,
        border: Border.all(
          color: aiMode ? theme.accentPalette.primary : colors.hairline,
        ),
      ),
      child: field,
    );
    if (elevated) {
      field = ShellBackdropBlur(
        blur: theme.effectivePanelOpacity < 1.0,
        borderRadius: radius,
        blendMode: BlendMode.srcOver,
        child: field,
      );
    }
    return Semantics(textField: true, label: hint, child: field);
  }

  static const TextStyle _touchStyle = TextStyle(
    color: ShellMediaColors.lightForeground,
    fontSize: 19,
    height: 1.2,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  /// A tap on the pill around the text, its icon included, is a tap on the
  /// field: the line of text alone is too thin a target for a finger.
  void _tapField() => focusNode.context
      ?.findAncestorStateOfType<EditableTextState>()
      ?.requestKeyboard();

  Widget _touch(BuildContext context) {
    const metrics = ShellSearchMetrics.touch;
    final l10n = context.l10n;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: metrics.fieldMaxWidth),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tapField,
        child: SizedBox(
          height: metrics.fieldHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x2effffff),
              border: Border.all(color: ShellMediaColors.lightOutline),
              borderRadius: BorderRadius.circular(metrics.fieldHeight / 2),
            ),
            child: Row(
              children: [
                const SizedBox(width: 18),
                Icon(
                  aiMode ? Icons.auto_awesome_rounded : Icons.search_rounded,
                  size: 26,
                  color: aiMode
                      ? context.shellTheme.accentPalette.primary
                      : ShellMediaColors.lightForegroundSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    type: MaterialType.transparency,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: 1,
                      style: _touchStyle,
                      cursorColor: ShellMediaColors.lightForeground,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: _inputFormatters,
                      onSubmitted: (_) => onSubmitted(),
                      decoration: InputDecoration.collapsed(
                        hintText: aiMode ? 'Спросить T3 Code AI...' : hint,
                        hintStyle: _touchStyle.copyWith(
                          color: ShellMediaColors.lightForegroundTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : Semantics(
                          button: true,
                          label: l10n.homeSearchClear,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _clear,
                            child: SizedBox(
                              width: metrics.fieldHeight - 6,
                              height: metrics.fieldHeight,
                              child: const Icon(
                                Icons.cancel_rounded,
                                size: 24,
                                color:
                                    ShellMediaColors.lightForegroundSecondary,
                              ),
                            ),
                          ),
                        ),
                ),
                if (onAskAi != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8, start: 4),
                    child: Semantics(
                      button: true,
                      label: 'Спросить T3 Code AI',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onAskAi,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            color: aiMode
                                ? context.shellTheme.accentPalette.primary
                                : const Color(0x38FFFFFF),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: aiMode
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : ShellMediaColors.lightOutline,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 17,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'AI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which open windows a search looks through.
enum ShellSearchWindows {
  /// The desktop's (the desktop presentation).
  desk,

  /// The phone's (the tablet presentation).
  phone,
}

/// The open windows a search over [source] looks through, as the backend
/// models them. Call it from a build method.
List<ShellSearchOpenWindow> watchShellSearchWindows(
  BuildContext context,
  WidgetRef ref,
  ShellSearchWindows source,
  ShellSearchIndex index,
) => shellSearchOpenWindows(
  ref.watch(switch (source) {
    ShellSearchWindows.desk => shellSearchDeskWindowsProvider,
    ShellSearchWindows.phone => shellSearchPhoneWindowsProvider,
  }),
  index: index,
  titleOf: (window) => localizedWindowTitle(context, window),
);

/// The one search's results under its field: with something typed the
/// matching apps (a grid, best first) and then the matching open windows;
/// with nothing typed the apps started last and every app by name.
///
/// It asks [shellSearchBackendProvider] for them and shows what it answers,
/// as it answers it. A query typed rebuilds this list, not its tiles.
class ShellSearchResults extends ConsumerStatefulWidget {
  const ShellSearchResults({
    super.key,
    required this.session,
    required this.style,
    required this.windows,
    required this.onLaunchApp,
    required this.onOpenWindow,
    this.columns,
    this.controller,
    this.physics,
    this.padding = EdgeInsets.zero,
    this.active = true,
  });

  final ShellSearchSession session;
  final ShellSearchStyle style;
  final ShellSearchWindows windows;
  final ShellSearchAppCallback onLaunchApp;
  final ShellSearchWindowCallback onOpenWindow;

  /// The grid's columns; by default as many as fit.
  final int? columns;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final EdgeInsets padding;

  /// Whether the surface is shown: a hidden one keeps its tiles but looks
  /// at no windows.
  final bool active;

  @override
  ConsumerState<ShellSearchResults> createState() => _ShellSearchResultsState();
}

class _ShellSearchResultsState extends ConsumerState<ShellSearchResults> {
  final ShellSearchIndexCache _indexCache = ShellSearchIndexCache();
  ScrollController? _ownScroll;
  ScrollController get _scroll =>
      widget.controller ?? (_ownScroll ??= ScrollController());

  /// Tiles and rows by key, built once each: typing reorders them without
  /// building them again.
  final Map<String, Widget> _items = {};
  ShellSearchIndex? _itemsIndex;
  ShellSearchStyle? _itemsStyle;

  /// Where each laid-out result's row starts and how tall it is, for
  /// keeping the chosen one in view.
  final Map<String, (double, double)> _rowSpans = {};
  String? _revealed;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  @override
  void didUpdateWidget(covariant ShellSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _ownScroll?.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) {
      return;
    }
    final typed = widget.session.query.text;
    setState(() {});
    if (typed != _lastQuery) {
      // A new query shows its best results from the top.
      _revealed = null;
      if (_scroll.hasClients &&
          _scroll.position.pixels != _scroll.position.minScrollExtent) {
        _scroll.jumpTo(_scroll.position.minScrollExtent);
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  String _lastQuery = '';

  void _reveal() {
    final key = widget.session.highlighted;
    if (!mounted || key == null || key == _revealed || !_scroll.hasClients) {
      return;
    }
    _revealed = key;
    final span = _rowSpans[key];
    if (span == null) {
      return;
    }
    final (top, extent) = span;
    final position = _scroll.position;
    final metrics = ShellSearchMetrics.of(widget.style);
    double? target;
    if (top - metrics.headerExtent < position.pixels) {
      target = top - metrics.headerExtent;
    } else if (top + extent > position.pixels + position.viewportDimension) {
      target = top + extent - position.viewportDimension;
    }
    if (target == null) {
      return;
    }
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(clamped);
    } else {
      unawaited(
        _scroll.animateTo(
          clamped,
          duration: Motion.tile,
          curve: Motion.standard,
        ),
      );
    }
  }

  void _launch(ShellSearchApp app, Rect iconRect) =>
      widget.onLaunchApp(app, iconRect);

  void _open(ShellSearchOpenWindow window, Rect iconRect) =>
      widget.onOpenWindow(window, iconRect);

  Widget _appTile(String key, ShellSearchApp app) =>
      _items[key] ??= switch (widget.style) {
        ShellSearchStyle.desktop => _DesktopAppTile(
          key: ValueKey(key),
          selectionKey: key,
          app: app,
          onLaunch: _launch,
        ),
        ShellSearchStyle.touch => _TouchAppTile(
          key: ValueKey(key),
          app: app,
          onLaunch: _launch,
        ),
      };

  Widget _windowRow(String key, ShellSearchOpenWindow window) {
    final cached = _items[key];
    if (cached is ShellSearchWindowRow && cached.window == window) {
      return cached;
    }
    return _items[key] = ShellSearchWindowRow(
      key: ValueKey(key),
      selectionKey: key,
      style: widget.style,
      window: window,
      onOpen: _open,
    );
  }

  int _columnsFor(double width) {
    if (widget.columns case final columns?) {
      return math.max(1, columns);
    }
    final metrics = ShellSearchMetrics.of(widget.style);
    return math.max(
      1,
      ((width + metrics.tileGap) / (metrics.minTileWidth + metrics.tileGap))
          .floor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final index = _indexCache.resolve(context, ref);
    if (!identical(index, _itemsIndex) || widget.style != _itemsStyle) {
      _items.clear();
      _itemsIndex = index;
      _itemsStyle = widget.style;
      if (widget.style == ShellSearchStyle.desktop) {
        warmAppIcons(context, [
          for (final app in index.apps)
            if (app.desktopApp case final desktop?) desktop.iconPath,
        ]);
      }
    }
    final backend = ref.watch(shellSearchBackendProvider);
    final query = session.query.text;
    _lastQuery = query;
    final typing = session.typing;
    // The windows matter only to what is typed, and only while shown.
    final windows = typing && widget.active
        ? watchShellSearchWindows(context, ref, widget.windows, index)
        : const <ShellSearchOpenWindow>[];
    final outcome = backend.search(
      query,
      scope: ShellSearchScope.appsAndWindows,
      index: index,
      windows: windows,
      recentIds: typing ? const [] : ref.watch(applicationRecentsProvider),
    );
    if (typing) {
      // Rows of windows that closed go; the others wait for the next query.
      final open = {for (final window in windows) 'w:${window.id}'};
      _items.removeWhere(
        (key, _) => key.startsWith('w:') && !open.contains(key),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _results(context, outcome, constraints.maxWidth),
    );
  }

  Widget _results(
    BuildContext context,
    ShellSearchOutcome outcome,
    double width,
  ) {
    final session = widget.session;
    final style = widget.style;
    final metrics = ShellSearchMetrics.of(style);
    final l10n = context.l10n;
    final gridWidth = width - metrics.sidePadding * 2;
    final columns = _columnsFor(gridWidth);
    final targets = <(String, ShellSearchTarget)>[];
    final rows = <List<int>>[];
    _rowSpans.clear();
    var top = widget.padding.top;
    final slivers = <Widget>[SliverPadding(padding: EdgeInsets.only(top: top))];

    void header(String title) {
      slivers.add(
        SliverToBoxAdapter(
          child: _SectionHeader(title: title, style: style),
        ),
      );
      top += metrics.headerExtent;
    }

    void grid(String prefix, List<ShellSearchApp> apps) {
      final keys = [for (final app in apps) '$prefix${app.id}'];
      final first = targets.length;
      for (final (index, app) in apps.indexed) {
        targets.add((keys[index], ShellSearchAppTarget(app)));
      }
      final rowCount = (apps.length + columns - 1) ~/ columns;
      for (var row = 0; row < rowCount; row += 1) {
        final start = first + row * columns;
        final end = math.min(first + apps.length, start + columns);
        rows.add([for (var index = start; index < end; index += 1) index]);
        final rowTop = top + row * (metrics.tileExtent + metrics.tileSpacing);
        for (var index = start; index < end; index += 1) {
          _rowSpans[targets[index].$1] = (rowTop, metrics.tileExtent);
        }
      }
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: metrics.sidePadding),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: metrics.tileExtent,
              mainAxisSpacing: metrics.tileSpacing,
              crossAxisSpacing: metrics.tileGap,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _appTile(keys[index], apps[index]),
              childCount: apps.length,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) {
                  return null;
                }
                final index = keys.indexOf(key.value);
                return index < 0 ? null : index;
              },
            ),
          ),
        ),
      );
      top +=
          rowCount * metrics.tileExtent +
          math.max(0, rowCount - 1) * metrics.tileSpacing;
    }

    void windowList(List<ShellSearchOpenWindow> windows) {
      final keys = [for (final window in windows) 'w:${window.id}'];
      for (final (index, window) in windows.indexed) {
        rows.add([targets.length]);
        _rowSpans[keys[index]] = (
          top + index * metrics.rowHeight,
          metrics.rowHeight,
        );
        targets.add((keys[index], ShellSearchWindowTarget(window)));
      }
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _Centered(
              style: style,
              child: _windowRow(keys[index], windows[index]),
            ),
            childCount: windows.length,
          ),
        ),
      );
      top += windows.length * metrics.rowHeight;
    }

    if (outcome.searching) {
      if (outcome.isEmpty) {
        slivers.add(SliverToBoxAdapter(child: _NothingFound(style: style)));
      }
      if (outcome.apps.isNotEmpty) {
        header(l10n.homeSearchApps);
        grid('a:', outcome.apps);
      }
      if (outcome.windows.isNotEmpty) {
        header(l10n.homeSearchWindows);
        windowList(outcome.windows);
      }
    } else {
      final recent = outcome.recentApps.take(columns).toList(growable: false);
      if (recent.isNotEmpty) {
        header(l10n.homeSearchRecentApps);
        grid('r:', recent);
        top += metrics.tileSpacing;
        slivers.add(
          SliverToBoxAdapter(child: SizedBox(height: metrics.tileSpacing)),
        );
      }
      if (outcome.apps.isNotEmpty) {
        header(l10n.shellSearchAllApps);
        grid('a:', outcome.apps);
      }
    }
    slivers.add(
      SliverPadding(padding: EdgeInsets.only(bottom: widget.padding.bottom)),
    );

    final first = outcome.first;
    String? defaultKey;
    if (first != null) {
      for (final (key, target) in targets) {
        if (target == first) {
          defaultKey = key;
          break;
        }
      }
    }
    session._layout(
      targets: targets,
      rows: rows,
      defaultKey: defaultKey,
      columns: columns,
    );
    return _Highlight(
      highlighted: style == ShellSearchStyle.desktop
          ? session.highlighted
          : null,
      child: CustomScrollView(
        controller: _scroll,
        physics: widget.physics,
        slivers: slivers,
      ),
    );
  }
}

/// The overview's results: the open windows the backend found for what is
/// typed ([ShellSearchScope.openWindows]), one row each, best first.
class ShellSearchWindowResults extends StatefulWidget {
  const ShellSearchWindowResults({
    super.key,
    required this.session,
    required this.outcome,
    required this.onOpenWindow,
  });

  final ShellSearchSession session;
  final ShellSearchOutcome outcome;
  final ShellSearchWindowCallback onOpenWindow;

  static const double padding = 8;

  /// The list's height for [outcome], within [maxHeight].
  static double heightFor(ShellSearchOutcome outcome, double maxHeight) {
    const metrics = ShellSearchMetrics.desktop;
    final rows = outcome.windows.isEmpty ? 1 : outcome.windows.length;
    final content = outcome.windows.isEmpty
        ? metrics.rowHeight
        : metrics.headerExtent + rows * metrics.rowHeight;
    return math.min(maxHeight, content + padding * 2);
  }

  @override
  State<ShellSearchWindowResults> createState() =>
      _ShellSearchWindowResultsState();
}

class _ShellSearchWindowResultsState extends State<ShellSearchWindowResults> {
  final ScrollController _scroll = ScrollController();
  final Map<int, ShellSearchWindowRow> _rows = {};

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  @override
  void didUpdateWidget(covariant ShellSearchWindowResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _reveal() {
    final key = widget.session.highlighted;
    if (!mounted || key == null || !_scroll.hasClients) {
      return;
    }
    const metrics = ShellSearchMetrics.desktop;
    final index = widget.outcome.windows.indexWhere(
      (window) => 'w:${window.id}' == key,
    );
    if (index < 0) {
      return;
    }
    final top =
        ShellSearchWindowResults.padding +
        metrics.headerExtent +
        index * metrics.rowHeight;
    final position = _scroll.position;
    double? target;
    if (top - metrics.headerExtent < position.pixels) {
      target = top - metrics.headerExtent;
    } else if (top + metrics.rowHeight >
        position.pixels + position.viewportDimension) {
      target = top + metrics.rowHeight - position.viewportDimension;
    }
    if (target == null) {
      return;
    }
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(clamped);
    } else {
      unawaited(
        _scroll.animateTo(
          clamped,
          duration: Motion.tile,
          curve: Motion.standard,
        ),
      );
    }
  }

  void _open(ShellSearchOpenWindow window, Rect iconRect) =>
      widget.onOpenWindow(window, iconRect);

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    final session = widget.session;
    final windows = outcome.windows;
    final targets = [
      for (final window in windows)
        ('w:${window.id}', ShellSearchWindowTarget(window)),
    ];
    final first = outcome.first;
    session._layout(
      targets: targets,
      rows: [
        for (var index = 0; index < targets.length; index += 1) [index],
      ],
      defaultKey: first is ShellSearchWindowTarget
          ? 'w:${first.window.id}'
          : null,
      columns: 1,
    );
    if (windows.isEmpty) {
      return _NothingFound(style: ShellSearchStyle.desktop);
    }
    _rows.removeWhere((id, _) => !windows.any((window) => window.id == id));
    return _Highlight(
      highlighted: session.highlighted,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(
          vertical: ShellSearchWindowResults.padding,
          horizontal: 8,
        ),
        children: [
          _SectionHeader(
            title: context.l10n.homeSearchWindows,
            style: ShellSearchStyle.desktop,
          ),
          for (final window in windows)
            _rows[window.id] = switch (_rows[window.id]) {
              final row? when row.window == window => row,
              _ => ShellSearchWindowRow(
                key: ValueKey('w:${window.id}'),
                selectionKey: 'w:${window.id}',
                style: ShellSearchStyle.desktop,
                window: window,
                onOpen: _open,
              ),
            },
        ],
      ),
    );
  }
}

/// Which result the keyboard is on; each tile depends only on its own key,
/// so moving the choice rebuilds two tiles.
class _Highlight extends InheritedModel<String> {
  const _Highlight({required this.highlighted, required super.child});

  final String? highlighted;

  static bool of(BuildContext context, String key) =>
      InheritedModel.inheritFrom<_Highlight>(
        context,
        aspect: key,
      )?.highlighted ==
      key;

  @override
  bool updateShouldNotify(_Highlight oldWidget) =>
      oldWidget.highlighted != highlighted;

  @override
  bool updateShouldNotifyDependent(
    _Highlight oldWidget,
    Set<String> dependencies,
  ) =>
      dependencies.contains(oldWidget.highlighted) ||
      dependencies.contains(highlighted);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.style});

  final String title;
  final ShellSearchStyle style;

  @override
  Widget build(BuildContext context) {
    final metrics = ShellSearchMetrics.of(style);
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: switch (style) {
        ShellSearchStyle.desktop => context.shellTheme.text.base.copyWith(
          fontSize: metrics.headerTextSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: context.shellColors.textSecondary,
          decoration: TextDecoration.none,
        ),
        ShellSearchStyle.touch => TextStyle(
          color: ShellMediaColors.lightForegroundSecondary,
          fontSize: metrics.headerTextSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          decoration: TextDecoration.none,
        ),
      },
    );
    return _Centered(
      style: style,
      child: SizedBox(
        height: metrics.headerExtent,
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
            child: text,
          ),
        ),
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.style});

  final ShellSearchStyle style;

  @override
  Widget build(BuildContext context) {
    final metrics = ShellSearchMetrics.of(style);
    return Padding(
      padding: EdgeInsets.only(
        top: style == ShellSearchStyle.touch ? 48 : 16,
        bottom: 16,
      ),
      child: Text(
        context.l10n.homeSearchNoResults,
        textAlign: TextAlign.center,
        style: switch (style) {
          ShellSearchStyle.desktop => context.shellTheme.text.base.copyWith(
            fontSize: metrics.rowTitleSize,
            color: context.shellColors.textSecondary,
            decoration: TextDecoration.none,
          ),
          ShellSearchStyle.touch => TextStyle(
            color: ShellMediaColors.lightForegroundSecondary,
            fontSize: metrics.nameSize,
            letterSpacing: 0,
            decoration: TextDecoration.none,
          ),
        },
      ),
    );
  }
}

/// Keeps rows and headers to a readable width in the middle (touch).
class _Centered extends StatelessWidget {
  const _Centered({required this.style, required this.child});

  final ShellSearchStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = ShellSearchMetrics.of(style);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.sidePadding),
          child: child,
        ),
      ),
    );
  }
}

/// Where [context]'s widget is, in global logical coordinates; empty when it
/// is not laid out.
Rect shellSearchGlobalRect(BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return Rect.zero;
  }
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

/// An app in the tablet's grid, as home draws it. A tap starts it, out of
/// its icon.
class _TouchAppTile extends StatelessWidget {
  const _TouchAppTile({super.key, required this.app, required this.onLaunch});

  final ShellSearchApp app;
  final ShellSearchAppCallback onLaunch;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onLaunch(
      app,
      HomeTileMetrics.iconRectIn(shellSearchGlobalRect(context)),
    ),
    child: HomeGridItemCard(item: app.item),
  );
}

/// An app in the desktop's grid: its icon and name. A click starts it; the
/// keyboard's choice and the pointer light it up.
class _DesktopAppTile extends StatefulWidget {
  const _DesktopAppTile({
    super.key,
    required this.selectionKey,
    required this.app,
    required this.onLaunch,
  });

  final String selectionKey;
  final ShellSearchApp app;
  final ShellSearchAppCallback onLaunch;

  @override
  State<_DesktopAppTile> createState() => _DesktopAppTileState();
}

class _DesktopAppTileState extends State<_DesktopAppTile> {
  final _icon = GlobalKey();
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = _Highlight.of(context, widget.selectionKey);
    final theme = context.shellTheme;
    final colors = context.shellColors;
    const metrics = ShellSearchMetrics.desktop;
    final app = widget.app;
    final Widget icon;
    if (app.localApp case final local?) {
      icon = LauncherIcon(icon: local.icon);
    } else {
      icon = DeferredAppIcon(iconPath: app.desktopApp?.iconPath);
    }
    final lit = selected || _hovered;
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.desktopLaunchApplication(app.name),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: ShellMouseCursors.link,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              widget.onLaunch(app, shellSearchGlobalRect(_icon.currentContext)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // The idle colour keeps the accent's hue, so the change never
              // passes through grey.
              color: lit
                  ? theme.accentPalette.primary.withValues(
                      alpha: selected ? 0.24 : 0.12,
                    )
                  : theme.accentPalette.primary.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(theme.chipRadius + 4),
              border: selected
                  ? Border.all(
                      color: theme.accentPalette.primary.withValues(alpha: 0.7),
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
              child: Column(
                children: [
                  SizedBox.square(
                    key: _icon,
                    dimension: metrics.iconSize,
                    child: icon,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.text.base.copyWith(
                      fontSize: metrics.nameSize,
                      height: 1.15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: colors.textPrimary,
                      decoration: TextDecoration.none,
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

/// One open window among the results: its app's icon, its title and its
/// app's name. A click or tap goes to it.
class ShellSearchWindowRow extends StatefulWidget {
  const ShellSearchWindowRow({
    super.key,
    required this.selectionKey,
    required this.style,
    required this.window,
    required this.onOpen,
  });

  final String selectionKey;
  final ShellSearchStyle style;
  final ShellSearchOpenWindow window;
  final ShellSearchWindowCallback onOpen;

  @override
  State<ShellSearchWindowRow> createState() => _ShellSearchWindowRowState();
}

class _ShellSearchWindowRowState extends State<ShellSearchWindowRow> {
  final _icon = GlobalKey();

  void _tap() =>
      widget.onOpen(widget.window, shellSearchGlobalRect(_icon.currentContext));

  Widget _iconOf(ShellSearchOpenWindow window) {
    final app = window.app;
    if (app != null) {
      return widget.style == ShellSearchStyle.touch
          ? HomeItemIcon(item: app.item)
          : LauncherIcon.of(app.item);
    }
    return _UnknownAppIcon(appId: window.window.appId);
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    final title = window.title.isEmpty ? window.appName : window.title;
    final detail = window.title.isEmpty || window.title == window.appName
        ? null
        : window.appName;
    return switch (widget.style) {
      ShellSearchStyle.desktop => _desktop(context, title, detail),
      ShellSearchStyle.touch => _touch(context, title, detail),
    };
  }

  Widget _desktop(BuildContext context, String title, String? detail) {
    final selected = _Highlight.of(context, widget.selectionKey);
    final theme = context.shellTheme;
    final colors = context.shellColors;
    const metrics = ShellSearchMetrics.desktop;
    final textStyle = theme.text.base.copyWith(decoration: TextDecoration.none);
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.desktopActivateWindow(title),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: ShellMouseCursors.link,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Container(
            height: metrics.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? theme.accentPalette.primary.withValues(alpha: 0.22)
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(theme.chipRadius),
            ),
            child: Row(
              children: [
                SizedBox.square(
                  key: _icon,
                  dimension: metrics.rowIcon,
                  child: _iconOf(widget.window),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle.copyWith(
                          fontSize: metrics.rowTitleSize,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontSize: metrics.rowDetailSize,
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.keyboard_return_rounded,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _touch(BuildContext context, String title, String? detail) {
    const metrics = ShellSearchMetrics.touch;
    final window = widget.window;
    // On the tablet the app's name leads, the window's title follows.
    final name = window.appName;
    final subtitle = window.title.isNotEmpty && window.title != name
        ? window.title
        : null;
    return Semantics(
      button: true,
      label: subtitle == null
          ? name
          : context.l10n.commonTitleAndSubtitle(name, subtitle),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: SizedBox(
          height: metrics.rowHeight,
          child: Row(
            children: [
              const SizedBox(width: 12),
              SizedBox.square(
                key: _icon,
                dimension: metrics.rowIcon,
                child: _iconOf(window),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ShellMediaColors.lightForeground,
                        fontSize: metrics.nameSize,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: 0,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ShellMediaColors.lightForegroundSecondary,
                          fontSize: metrics.rowDetailSize,
                          height: 1.25,
                          letterSpacing: 0,
                          decoration: TextDecoration.none,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon of a window's app that the index does not have.
class _UnknownAppIcon extends ConsumerWidget {
  const _UnknownAppIcon({required this.appId});

  final String appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(appId));
    return LauncherIcon(iconPath: application.iconPath, icon: application.icon);
  }
}
