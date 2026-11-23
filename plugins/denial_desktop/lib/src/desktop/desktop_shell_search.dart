import 'dart:async';
import 'dart:math' as math;

import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/shell_plugin_services.dart' show DesktopApplicationIcon;
import 'desktop_application_catalog.dart';
import 'desktop_workspace.dart';

/// One entry of the shell search's results: an open window to go to, or an
/// app to start.
sealed class DesktopSearchEntry {
  const DesktopSearchEntry();
}

final class DesktopSearchWindowEntry extends DesktopSearchEntry {
  const DesktopSearchWindowEntry(this.window);
  final ShellSearchWindow window;

  @override
  bool operator ==(Object other) =>
      other is DesktopSearchWindowEntry && other.window == window;

  @override
  int get hashCode => window.hashCode;
}

final class DesktopSearchApplicationEntry extends DesktopSearchEntry {
  const DesktopSearchApplicationEntry(this.application);
  final LauncherApplication application;

  @override
  bool operator ==(Object other) =>
      other is DesktopSearchApplicationEntry &&
      other.application.id == application.id;

  @override
  int get hashCode => application.id.hashCode;
}

/// The search's results as the overview and the search over the desktop
/// list them: matching windows, then matching apps, each best first.
///
/// [entries] are what the list shows and the arrows step through; the
/// first of them is [ShellSearchResults.first], what Enter acts on before
/// anything is chosen. [windowIds] holds every matching window, also those
/// the list leaves out.
@immutable
class DesktopSearchListing {
  const DesktopSearchListing._(this.results, this.entries, this.windowIds);

  factory DesktopSearchListing(
    ShellSearchResults results, {
    int maxWindows = maximumWindows,
  }) {
    final searching = normalizeShellSearchText(results.query).isNotEmpty;
    return DesktopSearchListing._(
      results,
      List.unmodifiable(<DesktopSearchEntry>[
        if (searching)
          for (final window in results.windows.take(maxWindows))
            DesktopSearchWindowEntry(window),
        for (final application in results.applications)
          DesktopSearchApplicationEntry(application),
      ]),
      searching
          ? Set.unmodifiable({for (final window in results.windows) window.id})
          : const <int>{},
    );
  }

  static final empty = DesktopSearchListing(
    const ShellSearchResults(query: '', windows: [], applications: []),
  );

  /// The windows the list shows at most; apps are bounded by the search.
  static const int maximumWindows = 8;

  final ShellSearchResults results;
  final List<DesktopSearchEntry> entries;
  final Set<int> windowIds;

  /// Whether something was typed: with nothing typed there are no results
  /// and nothing is dimmed.
  bool get searching => normalizeShellSearchText(results.query).isNotEmpty;

  int get windowCount => entries.whereType<DesktopSearchWindowEntry>().length;

  /// [selected] kept inside the list; 0, the best result, by default.
  int clampSelection(int selected) =>
      entries.isEmpty ? 0 : selected.clamp(0, entries.length - 1).toInt();
}

/// The open windows the search looks through, the most recently used first,
/// each named by its app as the catalog knows it.
List<ShellSearchWindow> desktopSearchWindows({
  required Iterable<DenialWindow> windows,
  required Map<int, DesktopWindowPlacement> placements,
  required DesktopApplicationCatalog catalog,
  required String Function(DenialWindow window) titleOf,
}) {
  final ordered = windows.toList(growable: false)
    ..sort((left, right) {
      final leftZ = placements[left.objectId]?.z ?? -1;
      final rightZ = placements[right.objectId]?.z ?? -1;
      return rightZ.compareTo(leftZ);
    });
  return List.unmodifiable([
    for (final window in ordered)
      ShellSearchWindow(
        id: window.objectId,
        appId: window.appId,
        appName: catalog.nameForWindow(window.appId) ?? window.appId,
        title: titleOf(window),
      ),
  ]);
}

/// The open app windows of the desktop, which the shell's search and the
/// overview's labels show.
final desktopSearchWindowsProvider = Provider<List<DenialWindow>>(
  (ref) => ref.watch(
    referenceShellProvider.select((state) => state.desk.openAppWindows),
  ),
);

/// Sizes of the search's field and list, in logical pixels, for the
/// tablet's panel (1357×960 logical at scale 2.5) and larger monitors.
abstract final class DesktopSearchMetrics {
  static const double fieldHeight = 48.0;
  static const double fieldMaxWidth = 600.0;
  static const double rowHeight = 56.0;
  static const double headerHeight = 32.0;
  static const double listPadding = 8.0;
  static const double iconSize = 34.0;
  static const double fieldTextSize = 18.0;
  static const double titleTextSize = 16.0;
  static const double detailTextSize = 13.0;
}

/// The search field: a magnifier, the query and a button that clears it.
class DesktopSearchField extends StatelessWidget {
  const DesktopSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
    this.elevated = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final VoidCallback onClear;

  /// Drawn on its own over the overview, with a glass of its own; inside a
  /// panel it is a well of that panel.
  final bool elevated;

  static final List<TextInputFormatter> _inputFormatters =
      List<TextInputFormatter>.unmodifiable(<TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u001F\u007F]')),
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final radius = BorderRadius.circular(DesktopSearchMetrics.fieldHeight / 2);
    final textStyle = theme.text.base.copyWith(
      fontSize: DesktopSearchMetrics.fieldTextSize,
      height: 1.2,
      decoration: TextDecoration.none,
    );
    Widget field = SizedBox(
      height: DesktopSearchMetrics.fieldHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 24, color: colors.textSecondary),
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
                          l10n.desktopSearchWindowsAndApplications,
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
                  // Keep the focus on submit: the overview stays open when
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
                          onTap: onClear,
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
        border: Border.all(color: colors.hairline),
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
    return Semantics(
      textField: true,
      label: l10n.desktopSearchWindowsAndApplications,
      child: field,
    );
  }
}

/// The search's results: the matching windows, then the apps, each row the
/// app's icon, the window's title or the app's name, and a detail.
class DesktopSearchResultList extends StatefulWidget {
  const DesktopSearchResultList({
    super.key,
    required this.listing,
    required this.selected,
    required this.catalog,
    required this.onSelect,
    required this.onActivate,
  });

  final DesktopSearchListing listing;

  /// The index into [DesktopSearchListing.entries] Enter acts on.
  final int selected;
  final DesktopApplicationCatalog catalog;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onActivate;

  /// The list's height for [listing], within [maxHeight].
  static double heightFor(DesktopSearchListing listing, double maxHeight) {
    final windows = listing.windowCount;
    final apps = listing.entries.length - windows;
    final content = listing.entries.isEmpty
        ? DesktopSearchMetrics.rowHeight
        : (windows > 0 ? DesktopSearchMetrics.headerHeight : 0.0) +
              (apps > 0 ? DesktopSearchMetrics.headerHeight : 0.0) +
              listing.entries.length * DesktopSearchMetrics.rowHeight;
    return math.min(maxHeight, content + DesktopSearchMetrics.listPadding * 2);
  }

  @override
  State<DesktopSearchResultList> createState() =>
      _DesktopSearchResultListState();
}

class _DesktopSearchResultListState extends State<DesktopSearchResultList> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant DesktopSearchResultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        !identical(oldWidget.listing, widget.listing)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _offsetOf(int index) {
    final windows = widget.listing.windowCount;
    var top = DesktopSearchMetrics.listPadding;
    if (windows > 0) {
      top += DesktopSearchMetrics.headerHeight;
    }
    if (index >= windows) {
      top += DesktopSearchMetrics.headerHeight;
    }
    return top + index * DesktopSearchMetrics.rowHeight;
  }

  /// Keeps the selected row in view as the arrows move it.
  void _reveal() {
    if (!mounted || !_scroll.hasClients || widget.listing.entries.isEmpty) {
      return;
    }
    final position = _scroll.position;
    final top = _offsetOf(widget.selected);
    final bottom = top + DesktopSearchMetrics.rowHeight;
    double? target;
    if (top - DesktopSearchMetrics.headerHeight < position.pixels) {
      target = top - DesktopSearchMetrics.headerHeight;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
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

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final l10n = context.l10n;
    if (listing.entries.isEmpty) {
      return SizedBox(
        height: DesktopSearchMetrics.rowHeight,
        child: Center(
          child: Text(
            l10n.desktopSearchNoResults,
            style: context.shellTheme.text.base.copyWith(
              fontSize: DesktopSearchMetrics.titleTextSize,
              color: context.shellColors.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      );
    }
    final windows = listing.windowCount;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        vertical: DesktopSearchMetrics.listPadding,
      ),
      children: [
        for (var index = 0; index < listing.entries.length; index += 1) ...[
          if (index == 0 && windows > 0)
            _SectionHeader(l10n.desktopSearchWindowsSection),
          if (index == windows)
            _SectionHeader(l10n.desktopSearchApplicationsSection),
          _ResultRow(
            key: ValueKey<DesktopSearchEntry>(listing.entries[index]),
            entry: listing.entries[index],
            catalog: widget.catalog,
            selected: index == widget.selected,
            onHover: () => widget.onSelect(index),
            onTap: () => widget.onActivate(index),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: DesktopSearchMetrics.headerHeight,
    child: Padding(
      padding: const EdgeInsetsDirectional.only(start: 20, end: 20, top: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: context.shellTheme.text.base.copyWith(
            fontSize: DesktopSearchMetrics.detailTextSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: context.shellColors.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.entry,
    required this.catalog,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final DesktopSearchEntry entry;
  final DesktopApplicationCatalog catalog;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final (title, detail, icon, label) = switch (entry) {
      DesktopSearchWindowEntry(:final window) => (
        window.title.isEmpty ? window.appName : window.title,
        window.title.isEmpty ? null : window.appName,
        DesktopApplicationIcon(appId: window.appId),
        l10n.desktopActivateWindow(
          window.title.isEmpty ? window.appName : window.title,
        ),
      ),
      DesktopSearchApplicationEntry(:final application) => (
        application.name,
        null,
        desktopCatalogIcon(
          context,
          catalog,
          application.id,
          size: DesktopSearchMetrics.iconSize,
        ),
        l10n.desktopLaunchApplication(application.name),
      ),
    };
    final textStyle = theme.text.base.copyWith(decoration: TextDecoration.none);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: ShellMouseCursors.link,
        onHover: (_) {
          if (!selected) {
            onHover();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.tile,
              curve: Motion.standard,
              height: DesktopSearchMetrics.rowHeight,
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
                    dimension: DesktopSearchMetrics.iconSize,
                    child: icon,
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
                            fontSize: DesktopSearchMetrics.titleTextSize,
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
                              fontSize: DesktopSearchMetrics.detailTextSize,
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
      ),
    );
  }
}

/// The icon of the catalog app [id]: a local Flutter app's own, else its
/// desktop entry's.
Widget desktopCatalogIcon(
  BuildContext context,
  DesktopApplicationCatalog catalog,
  String id, {
  double? size,
}) {
  if (catalog.localApps[id] case final app?) {
    return Icon(
      app.icon,
      size: size,
      color: context.shellTheme.accentPalette.primary,
    );
  }
  return DeferredAppIcon(iconPath: catalog.desktopApps[id]?.iconPath);
}

/// Asks the open screens overview to put the keyboard into its search
/// field: the search key pressed while the overview is open.
final desktopOverviewSearchFocusProvider =
    NotifierProvider<DesktopSearchFocusRequests, int>(
      DesktopSearchFocusRequests.new,
    );

class DesktopSearchFocusRequests extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state += 1;
}

/// The search over the desktop (the search key, Alt+F in the Mac preset):
/// the monitor it is open on, or null while it is closed.
final desktopSearchOverlayProvider =
    NotifierProvider<DesktopSearchOverlayController, int?>(
      DesktopSearchOverlayController.new,
    );

class DesktopSearchOverlayController extends Notifier<int?> {
  @override
  int? build() => null;

  void open(int monitorId) => state = monitorId;

  void close() => state = null;
}

/// What the shell's search keys do; see [DesktopSearchHost.handleSearchKey].
enum DesktopSearchKey { next, previous, clearOrDismiss }

/// The shared behaviour of the shell's search surfaces: the query, the
/// results, the selection, the keys and what choosing a result does. The
/// screens overview and the search over the desktop each mix it in and draw
/// the same field and list.
mixin DesktopSearchHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final TextEditingController searchController = TextEditingController();
  late final FocusNode searchFocusNode = FocusNode(
    debugLabel: 'desktop-search',
    onKeyEvent: handleSearchKey,
  );
  final DesktopApplicationCatalogCache _searchCatalogCache =
      DesktopApplicationCatalogCache();
  DesktopApplicationCatalog searchCatalog = DesktopApplicationCatalog.empty;
  int _searchSelected = 0;
  DesktopSearchListing _searchListing = DesktopSearchListing.empty;
  String? _listedQuery;
  List<ShellSearchWindow>? _listedWindows;
  List<LauncherApplication>? _listedApplications;

  /// The results as last built; see [resolveSearch].
  DesktopSearchListing get searchListing => _searchListing;

  /// The selected entry, kept inside the list.
  int get searchSelected => _searchListing.clampSelection(_searchSelected);

  /// Goes to the open window [objectId] and closes the surface.
  void activateSearchWindow(int objectId);

  /// Starts the catalog app [id] and closes the surface.
  void launchSearchApplication(String id);

  /// Closes the surface.
  void dismissSearch();

  /// Arrows and Enter with nothing typed; the overview moves between its
  /// windows with them. False leaves the key to the field.
  bool handleKeyWithoutQuery(LogicalKeyboardKey key) => false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(_searchQueryChanged);
  }

  @override
  void dispose() {
    searchController
      ..removeListener(_searchQueryChanged)
      ..dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  void _searchQueryChanged() {
    if (searchController.text == _listedQuery) {
      return;
    }
    // A new query starts again at its best result.
    setState(() => _searchSelected = 0);
  }

  /// Empties the query and puts the keyboard into the field once it is
  /// laid out.
  void startSearch() {
    if (searchController.text.isNotEmpty) {
      searchController.clear();
    }
    _searchSelected = 0;
    focusSearch();
  }

  void focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        searchFocusNode.requestFocus();
        searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: searchController.text.length,
        );
      }
    });
  }

  /// Builds the results for the query from the open windows and the
  /// catalog, again only when one of them changed.
  DesktopSearchListing resolveSearch(BuildContext context) {
    searchCatalog = _searchCatalogCache.resolve(
      context,
      slots: ref.watch(
        homeGridControllerProvider.select((state) => state.asData?.value.slots),
      ),
      registry: ref.watch(localFlutterApplicationRegistryProvider),
      launcher: ref.watch(appLauncherProvider),
    );
    final windows = ref.watch(desktopSearchWindowsProvider);
    final placements = ref.watch(
      desktopWorkspaceProvider.select((state) => state.placements),
    );
    final query = searchController.text;
    final searchWindows = desktopSearchWindows(
      windows: windows,
      placements: placements,
      catalog: searchCatalog,
      titleOf: (window) => localizedWindowTitle(context, window),
    );
    final listedWindows = _listedWindows;
    if (query == _listedQuery &&
        identical(searchCatalog.applications, _listedApplications) &&
        listedWindows != null &&
        _sameWindows(listedWindows, searchWindows)) {
      return _searchListing;
    }
    _listedQuery = query;
    _listedWindows = searchWindows;
    _listedApplications = searchCatalog.applications;
    return _searchListing = DesktopSearchListing(
      searchShell(
        query,
        windows: searchWindows,
        applications: searchCatalog.applications,
      ),
    );
  }

  static bool _sameWindows(
    List<ShellSearchWindow> left,
    List<ShellSearchWindow> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  /// The open app window [objectId], or null when it has closed.
  DenialWindow? searchWindowOf(int objectId) {
    for (final window in ref.read(desktopSearchWindowsProvider)) {
      if (window.objectId == objectId) {
        return window;
      }
    }
    return null;
  }

  void selectSearchEntry(int index) {
    if (index != _searchSelected) {
      setState(() => _searchSelected = index);
    }
  }

  void _moveSearchSelection(int delta) {
    final listing = _searchListing;
    if (listing.entries.isEmpty) {
      return;
    }
    selectSearchEntry(listing.clampSelection(searchSelected + delta));
  }

  /// Acts on entry [index]: goes to the window or starts the app.
  void activateSearchEntry(int index) {
    final entries = _searchListing.entries;
    if (index < 0 || index >= entries.length) {
      return;
    }
    switch (entries[index]) {
      case DesktopSearchWindowEntry(:final window):
        activateSearchWindow(window.id);
      case DesktopSearchApplicationEntry(:final application):
        launchSearchApplication(application.id);
    }
  }

  /// Enter: the selected result, the best one unless the arrows chose
  /// another. With nothing typed it is the surface's own.
  void submitSearch() {
    if (!_searchListing.searching) {
      handleKeyWithoutQuery(LogicalKeyboardKey.enter);
      return;
    }
    activateSearchEntry(searchSelected);
  }

  void clearSearch() {
    searchController.clear();
    searchFocusNode.requestFocus();
  }

  /// Up and Down (and Tab) step through the results; Esc clears the query,
  /// then closes. Left and Right stay with the field's text.
  KeyEventResult handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final searching = searchController.text.isNotEmpty;
    // Enter submits through the field (onSubmitted), as typed text does.
    if (!searching &&
        key != LogicalKeyboardKey.escape &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter &&
        handleKeyWithoutQuery(key)) {
      return KeyEventResult.handled;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final action = switch (key) {
      LogicalKeyboardKey.arrowDown => DesktopSearchKey.next,
      LogicalKeyboardKey.arrowUp => DesktopSearchKey.previous,
      LogicalKeyboardKey.tab =>
        shift ? DesktopSearchKey.previous : DesktopSearchKey.next,
      LogicalKeyboardKey.escape =>
        event is KeyDownEvent ? DesktopSearchKey.clearOrDismiss : null,
      _ => null,
    };
    switch (action) {
      case DesktopSearchKey.next:
        _moveSearchSelection(1);
        return KeyEventResult.handled;
      case DesktopSearchKey.previous:
        _moveSearchSelection(-1);
        return KeyEventResult.handled;
      case DesktopSearchKey.clearOrDismiss:
        if (searching) {
          searchController.clear();
        } else {
          dismissSearch();
        }
        return KeyEventResult.handled;
      case null:
        return KeyEventResult.ignored;
    }
  }
}
