import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/tokens.dart';

import '../../state/reference_shell_controller.dart';
import '../home_grid_geometry.dart';
import '../home_search.dart';
import '../window_application.dart';
import 'home_app_tile.dart';
import 'home_item_icon.dart';
import 'home_tiles.dart';
import 'launcher_icon.dart';

/// Opens an app from its icon, in global coordinates.
typedef HomeLaunchCallback = void Function(HomeGridItem app, Rect iconRect);

/// Brings an open window to the front from its icon, in global coordinates.
typedef HomeOpenWindowCallback = void Function(
  HomeSearchWindow window,
  Rect iconRect,
);

/// Sizes of the tablet's search, in logical pixels at the shell's scale.
abstract final class HomeSearchMetrics {
  static const double fieldHeight = 52;
  static const double fieldMaxWidth = 720;
  static const double contentMaxWidth = 960;
  static const double rowHeight = 64;
  static const double rowIcon = 44;
  static const double headerHeight = 44;
  static const double nameSize = 17;
  static const double titleSize = 15;
}

/// The phone's open windows, the one in front or last there first: what
/// the tablet's search lists. It follows the windows and the one in front.
final homeSearchWindowsProvider = Provider.autoDispose<List<DenialWindow>>((
  ref,
) {
  ref.watch(
    referenceShellProvider.select(
      (state) => (apps: state.deckApps, front: state.foregroundObjectId),
    ),
  );
  return ref.read(referenceShellProvider.notifier).appsMostRecentFirst;
});

/// The search catalog of what home shows now: the phone's open windows,
/// most recently in front first, and [apps], the apps on home.
HomeSearchCatalog homeSearchCatalog(
  BuildContext context,
  WidgetRef ref,
  Iterable<HomeGridItem> apps,
) {
  final windows = [
    for (final window in ref.watch(homeSearchWindowsProvider))
      _searchWindow(context, ref, window),
  ];
  final list = apps.toList(growable: false);
  return HomeSearchCatalog(
    windows: windows,
    apps: list,
    names: {for (final app in list) app.id: HomeAppTile.nameOf(context, app)},
    searchableText: {
      for (final app in list)
        if (app.localApp case final local?)
          app.id: [
            local.id,
            local.titleFor(context),
            ...local.categoriesFor(context),
          ].join(' ').toLowerCase(),
    },
  );
}

HomeSearchWindow _searchWindow(
  BuildContext context,
  WidgetRef ref,
  DenialWindow window,
) {
  final application = ref.watch(windowApplicationProvider(window.appId));
  final item = application.item;
  return HomeSearchWindow(
    window: window,
    appName: item != null
        ? HomeAppTile.nameOf(context, item)
        : application.name ?? localizedWindowTitle(context, window),
    app: item,
  );
}

/// The search field of the drawer and of the pull down: a glass pill with a
/// magnifier, the query and a clear button.
class HomeSearchField extends StatelessWidget {
  const HomeSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final VoidCallback? onTap;

  static const TextStyle _style = TextStyle(
    color: ShellMediaColors.lightForeground,
    fontSize: 19,
    height: 1.2,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: HomeSearchMetrics.fieldMaxWidth,
      ),
      child: SizedBox(
        height: HomeSearchMetrics.fieldHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x2effffff),
            border: Border.all(color: ShellMediaColors.lightOutline),
            borderRadius: BorderRadius.circular(
              HomeSearchMetrics.fieldHeight / 2,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              const Icon(
                Icons.search_rounded,
                size: 26,
                color: ShellMediaColors.lightForegroundSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          controller.clear(),
                    },
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: 1,
                      style: _style,
                      cursorColor: ShellMediaColors.lightForeground,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      enableSuggestions: false,
                      onTap: onTap,
                      onSubmitted: (_) => onSubmitted(),
                      decoration: InputDecoration.collapsed(
                        hintText: l10n.homeSearchHint,
                        hintStyle: _style.copyWith(
                          color: ShellMediaColors.lightForegroundTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox(width: 18)
                    : Semantics(
                        button: true,
                        label: l10n.homeSearchClear,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: controller.clear,
                          child: const SizedBox(
                            width: HomeSearchMetrics.fieldHeight,
                            height: HomeSearchMetrics.fieldHeight,
                            child: Icon(
                              Icons.cancel_rounded,
                              size: 24,
                              color: ShellMediaColors.lightForegroundSecondary,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search results as one scroll view: matching open windows as rows, then
/// matching apps as home tiles. Before anything is typed, the open windows
/// and [recentApps], the pull down's suggestions.
class HomeSearchResults extends StatelessWidget {
  const HomeSearchResults({
    super.key,
    required this.matches,
    required this.columns,
    required this.onLaunch,
    required this.onOpenWindow,
    this.recentApps = const <HomeGridItem>[],
    this.controller,
    this.physics,
    this.padding = EdgeInsets.zero,
  });

  final HomeSearchMatches matches;
  final int columns;
  final HomeLaunchCallback onLaunch;
  final HomeOpenWindowCallback onOpenWindow;
  final List<HomeGridItem> recentApps;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typed = matches.query.trim().isNotEmpty;
    final apps = typed ? matches.apps : recentApps;
    return CustomScrollView(
      controller: controller,
      physics: physics,
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: padding.top)),
        if (typed && matches.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Text(
                l10n.homeSearchNoResults,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ShellMediaColors.lightForegroundSecondary,
                  fontSize: HomeSearchMetrics.nameSize,
                  letterSpacing: 0,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        if (matches.windows.isNotEmpty) ...[
          _header(l10n.homeSearchWindows),
          SliverList.builder(
            itemCount: matches.windows.length,
            itemBuilder: (context, index) => _Centered(
              child: HomeSearchWindowRow(
                key: ValueKey(matches.windows[index].window.objectId),
                entry: matches.windows[index],
                onOpen: onOpenWindow,
              ),
            ),
          ),
        ],
        if (apps.isNotEmpty) ...[
          _header(typed ? l10n.homeSearchApps : l10n.homeSearchRecentApps),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: HomeGridLayout.minTileHeight,
                mainAxisSpacing: 18,
                crossAxisSpacing: HomeGridLayout.gridGap,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => HomeLaunchTile(
                  key: ValueKey(apps[index].id),
                  app: apps[index],
                  onLaunch: onLaunch,
                ),
                childCount: apps.length,
              ),
            ),
          ),
        ],
        SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
      ],
    );
  }

  Widget _header(String title) => SliverToBoxAdapter(
    child: _Centered(
      child: SizedBox(
        height: HomeSearchMetrics.headerHeight,
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: ShellMediaColors.lightForegroundSecondary,
                fontSize: HomeSearchMetrics.titleSize,
                fontWeight: FontWeight.w600,
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

/// Keeps rows and headers to a readable width in the middle of the panel.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: HomeSearchMetrics.contentMaxWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    ),
  );
}

/// One open window in the results: its app's icon, the app's name and the
/// window's title. A tap brings it to the front.
class HomeSearchWindowRow extends StatefulWidget {
  const HomeSearchWindowRow({
    super.key,
    required this.entry,
    required this.onOpen,
  });

  final HomeSearchWindow entry;
  final HomeOpenWindowCallback onOpen;

  @override
  State<HomeSearchWindowRow> createState() => _HomeSearchWindowRowState();
}

class _HomeSearchWindowRowState extends State<HomeSearchWindowRow> {
  final _icon = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final window = entry.window;
    final title = localizedWindowTitle(context, window);
    final app = entry.app;
    final showsTitle = title.isNotEmpty && title != entry.appName;
    return Semantics(
      button: true,
      label: showsTitle
          ? context.l10n.commonTitleAndSubtitle(entry.appName, title)
          : entry.appName,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(entry, globalRectOf(_icon)),
        child: SizedBox(
          height: HomeSearchMetrics.rowHeight,
          child: Row(
            children: [
              const SizedBox(width: 12),
              SizedBox.square(
                key: _icon,
                dimension: HomeSearchMetrics.rowIcon,
                child: app != null
                    ? HomeItemIcon(item: app)
                    : _WindowAppIcon(appId: window.appId),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ShellMediaColors.lightForeground,
                        fontSize: HomeSearchMetrics.nameSize,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: 0,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (showsTitle)
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ShellMediaColors.lightForegroundSecondary,
                          fontSize: HomeSearchMetrics.titleSize,
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

/// The icon of a window's app that home does not have.
class _WindowAppIcon extends ConsumerWidget {
  const _WindowAppIcon({required this.appId});

  final String appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(appId));
    return LauncherIcon(iconPath: application.iconPath, icon: application.icon);
  }
}

/// Where [key]'s widget is, in global logical coordinates; empty when it is
/// not laid out.
Rect globalRectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

/// An app as a home tile that starts it on a tap, in the drawer and in
/// search results.
class HomeLaunchTile extends StatelessWidget {
  const HomeLaunchTile({super.key, required this.app, required this.onLaunch});

  final HomeGridItem app;
  final HomeLaunchCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final rect = MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
        onLaunch(app, HomeTileMetrics.iconRectIn(rect));
      },
      child: RepaintBoundary(child: HomeGridItemCard(item: app)),
    );
  }
}
