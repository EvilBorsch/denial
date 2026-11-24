import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/desktop_workspace.dart';
import '../launcher/home_icon_locator.dart' show launcherAppIdentity;
import '../state/reference_shell_controller.dart';

// The shell's one search backend (eb19).
//
// Every search of the shell goes through this file: the search over the
// desktop that a bare Super, Super+S, Alt+F and four fingers up open, the
// overview's search (open windows only), and the tablet's app drawer and
// pull-down search. It holds the one model of the apps the shell can start
// ([ShellSearchIndex]), the one model of the open windows
// ([ShellSearchOpenWindow]), and the one matcher and ranking
// ([ShellSearchBackend.search], which runs the SDK's [searchShell]). No other
// code filters apps or windows by what was typed;
// test/search/one_search_guard_test.dart fails when some does.

/// One app the shell can start, as all of its searches know it.
@immutable
class ShellSearchApp {
  const ShellSearchApp._({
    required this.id,
    required this.name,
    required this.searchableText,
    required this.item,
    required this._windowIdentities,
  });

  /// The launcher's id of the app, as its history records it:
  /// [desktopApplicationRecentId] or [localApplicationRecentId].
  final String id;

  /// The app's name in the shell's language.
  final String name;

  /// Lower-case words the search also matches: the app id, categories,
  /// keywords and the untranslated name.
  final String searchableText;

  /// The app as home knows it: its icon, and what the tablet launches.
  final HomeGridItem item;

  /// The app ids its windows carry, as [launcherAppIdentity] compares them.
  final Set<String> _windowIdentities;

  DesktopApp? get desktopApp => item.app;
  LocalFlutterApplication? get localApp => item.localApp;

  /// Whether a window of [appId] belongs to this app.
  bool ownsWindow(String appId) =>
      _windowIdentities.contains(launcherAppIdentity(appId));

  @override
  String toString() => 'ShellSearchApp($id, "$name")';
}

/// Every app the shell can start, by name: the apps on home, folders opened,
/// and the shell's own apps.
@immutable
class ShellSearchIndex {
  ShellSearchIndex._(this.apps)
    : _byId = {for (final app in apps) app.id: app},
      _matchable = List.unmodifiable([
        for (final app in apps)
          LauncherApplication(
            id: app.id,
            name: app.name,
            searchableText: app.searchableText,
          ),
      ]);

  static final empty = ShellSearchIndex._(const []);

  /// Builds the index of [homeApps] (home's apps, folders opened) and
  /// [localApps] (the shell's own apps, also those home does not show).
  factory ShellSearchIndex.build({
    required Iterable<HomeGridItem> homeApps,
    required Iterable<LocalFlutterApplication> localApps,
    required AppLauncher launcher,
    required String Function(LocalFlutterApplication app) titleOf,
    required List<String> Function(LocalFlutterApplication app) categoriesOf,
  }) {
    final apps = <String, ShellSearchApp>{};
    void addLocal(LocalFlutterApplication local, HomeGridItem item) {
      final id = localApplicationRecentId(local.id);
      final title = titleOf(local);
      apps.putIfAbsent(
        id,
        () => ShellSearchApp._(
          id: id,
          name: title,
          searchableText: [
            local.id,
            title,
            ...categoriesOf(local),
          ].join(' ').toLowerCase(),
          item: item,
          windowIdentities: {launcherAppIdentity(local.id)},
        ),
      );
    }

    for (final item in homeApps) {
      if (item.app case final desktop?) {
        final id = desktopApplicationRecentId(desktop.id);
        apps.putIfAbsent(
          id,
          () => ShellSearchApp._(
            id: id,
            name: desktop.name,
            searchableText: desktop.searchableText,
            item: item,
            windowIdentities: {
              for (final appId in launcher.expectedWindowAppIds(desktop))
                launcherAppIdentity(appId),
            },
          ),
        );
      } else if (item.localApp case final local?) {
        addLocal(local, item);
      }
    }
    for (final local in localApps) {
      addLocal(local, HomeGridItem.localApp(local));
    }
    final sorted = apps.values.toList()
      ..sort(
        (a, b) =>
            normalizeShellSearchText(a.name)
                .compareTo(normalizeShellSearchText(b.name)),
      );
    return ShellSearchIndex._(List.unmodifiable(sorted));
  }

  /// Every app, by name.
  final List<ShellSearchApp> apps;
  final Map<String, ShellSearchApp> _byId;
  final List<LauncherApplication> _matchable;

  /// Every app as the SDK's launcher contract describes it, for a launcher
  /// plugin.
  List<LauncherApplication> get launcherApplications => _matchable;

  ShellSearchApp? operator [](String id) => _byId[id];

  /// The app whose windows carry [appId], or null when none of the index
  /// opens such windows.
  ShellSearchApp? appOfWindow(String appId) {
    for (final app in apps) {
      if (app.ownsWindow(appId)) {
        return app;
      }
    }
    return null;
  }

  /// The apps of [recentIds] (the launcher's history, newest first) that the
  /// index has, at most [max].
  List<ShellSearchApp> recent(List<String> recentIds, {int max = 8}) {
    final seen = <String>{};
    return List.unmodifiable(
      [
        for (final id in recentIds)
          if (_byId[id] case final app? when seen.add(app.id)) app,
      ].take(max < 0 ? 0 : max),
    );
  }
}

/// Builds the index again only when home, the shell's own apps, the
/// launcher or the locale change.
class ShellSearchIndexCache {
  List<HomeGridItem?>? _slots;
  LocalFlutterApplicationRegistry? _registry;
  AppLauncher? _launcher;
  Locale? _locale;
  ShellSearchIndex _index = ShellSearchIndex.empty;

  /// The index for what [ref] sees now; call it from a build method.
  ShellSearchIndex resolve(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(
      homeGridControllerProvider.select((state) => state.asData?.value.slots),
    );
    final registry = ref.watch(localFlutterApplicationRegistryProvider);
    final launcher = ref.watch(appLauncherProvider);
    final locale = Localizations.maybeLocaleOf(context);
    if (identical(_slots, slots) &&
        identical(_registry, registry) &&
        identical(_launcher, launcher) &&
        _locale == locale) {
      return _index;
    }
    _slots = slots;
    _registry = registry;
    _launcher = launcher;
    _locale = locale;
    return _index = ShellSearchIndex.build(
      homeApps: HomeGridLayout.appsIn(slots ?? const <HomeGridItem?>[]),
      localApps: registry.applications,
      launcher: launcher,
      titleOf: (app) => app.titleFor(context),
      categoriesOf: (app) => app.categoriesFor(context),
    );
  }
}

/// One open window, as all of the shell's searches know it.
@immutable
class ShellSearchOpenWindow {
  const ShellSearchOpenWindow({
    required this.window,
    required this.app,
    required this.appName,
    required this.title,
  });

  final DenialWindow window;

  /// The app the window belongs to; null for an app the index does not have.
  final ShellSearchApp? app;

  /// The app's name; for an app the index does not have, the window's title
  /// or else its app id.
  final String appName;

  /// The window's title in the shell's language.
  final String title;

  int get id => window.objectId;

  ShellSearchWindow get _matchable => ShellSearchWindow(
    id: window.objectId,
    appId: window.appId,
    appName: appName,
    title: title,
  );

  @override
  bool operator ==(Object other) =>
      other is ShellSearchOpenWindow &&
      other.window == window &&
      identical(other.app, app) &&
      other.appName == appName &&
      other.title == title;

  @override
  int get hashCode => Object.hash(window, app, appName, title);
}

/// [windows] (most recently used first) as the searches know them.
List<ShellSearchOpenWindow> shellSearchOpenWindows(
  Iterable<DenialWindow> windows, {
  required ShellSearchIndex index,
  required String Function(DenialWindow window) titleOf,
}) => List.unmodifiable([
  for (final window in windows)
    _openWindow(window, index.appOfWindow(window.appId), titleOf(window)),
]);

ShellSearchOpenWindow _openWindow(
  DenialWindow window,
  ShellSearchApp? app,
  String title,
) => ShellSearchOpenWindow(
  window: window,
  app: app,
  appName: app?.name ?? (title.isNotEmpty ? title : window.appId),
  title: title,
);

/// The desktop's open app windows, the one used last first: what the
/// searches over the desktop look through.
final shellSearchDeskWindowsProvider = Provider<List<DenialWindow>>((ref) {
  final windows = ref.watch(
    referenceShellProvider.select((state) => state.desk.openAppWindows),
  );
  // Only the order of use matters here, not every move of a window.
  ref.watch(
    desktopWorkspaceProvider.select(
      (state) => _zOrderKey(state.placements, windows),
    ),
  );
  return shellSearchMostRecentFirst(
    windows,
    ref.read(desktopWorkspaceProvider).placements,
  );
});

/// The desktop's [windows], the one used last (highest in [placements])
/// first.
List<DenialWindow> shellSearchMostRecentFirst(
  Iterable<DenialWindow> windows,
  Map<int, DesktopWindowPlacement> placements,
) => List.unmodifiable(
  windows.toList(growable: false)..sort((left, right) {
    final leftZ = placements[left.objectId]?.z ?? -1;
    final rightZ = placements[right.objectId]?.z ?? -1;
    return rightZ.compareTo(leftZ);
  }),
);

String _zOrderKey(
  Map<int, DesktopWindowPlacement> placements,
  List<DenialWindow> windows,
) => [
  for (final window in windows)
    '${window.objectId}:${placements[window.objectId]?.z ?? -1}',
].join(',');

/// The phone's open windows, the one in front or last there first: what the
/// tablet's searches look through.
final shellSearchPhoneWindowsProvider =
    Provider.autoDispose<List<DenialWindow>>((ref) {
      ref.watch(
        referenceShellProvider.select(
          (state) => (apps: state.deckApps, front: state.foregroundObjectId),
        ),
      );
      return ref.read(referenceShellProvider.notifier).appsMostRecentFirst;
    });

/// What a search looks through.
enum ShellSearchScope {
  /// Apps to start, then open windows: the one search (Super, Super+S,
  /// Alt+F, four fingers up, the tablet's drawer and pull down).
  appsAndWindows,

  /// Open windows only: the overview's search.
  openWindows,
}

/// What Enter or a tap acts on: an app to start (or to switch to, when it
/// runs), or an open window to go to.
sealed class ShellSearchTarget {
  const ShellSearchTarget();
}

final class ShellSearchAppTarget extends ShellSearchTarget {
  const ShellSearchAppTarget(this.app);
  final ShellSearchApp app;

  @override
  bool operator ==(Object other) =>
      other is ShellSearchAppTarget && other.app.id == app.id;

  @override
  int get hashCode => app.id.hashCode;
}

final class ShellSearchWindowTarget extends ShellSearchTarget {
  const ShellSearchWindowTarget(this.window);
  final ShellSearchOpenWindow window;

  @override
  bool operator ==(Object other) =>
      other is ShellSearchWindowTarget && other.window.id == window.id;

  @override
  int get hashCode => window.id.hashCode;
}

/// A search's answer.
@immutable
class ShellSearchOutcome {
  const ShellSearchOutcome({
    required this.query,
    required this.scope,
    required this.apps,
    required this.windows,
    this.recentApps = const [],
  });

  static const empty = ShellSearchOutcome(
    query: '',
    scope: ShellSearchScope.appsAndWindows,
    apps: [],
    windows: [],
  );

  /// The query as typed.
  final String query;
  final ShellSearchScope scope;

  /// Something typed: the matching apps, best first. Nothing typed: every
  /// app, by name. None in [ShellSearchScope.openWindows].
  final List<ShellSearchApp> apps;

  /// Something typed: the matching open windows, best first. Nothing typed:
  /// every open window in [ShellSearchScope.openWindows], none otherwise.
  final List<ShellSearchOpenWindow> windows;

  /// Nothing typed: the apps started last, newest first.
  final List<ShellSearchApp> recentApps;

  /// Whether something was typed.
  bool get searching => normalizeShellSearchText(query).isNotEmpty;

  bool get isEmpty => apps.isEmpty && windows.isEmpty;

  /// What Enter acts on before the arrows choose: the best app, else the
  /// best window. Nothing while nothing is typed.
  ShellSearchTarget? get first {
    if (!searching) {
      return null;
    }
    if (apps.isNotEmpty) {
      return ShellSearchAppTarget(apps.first);
    }
    if (windows.isNotEmpty) {
      return ShellSearchWindowTarget(windows.first);
    }
    return null;
  }
}

/// The one matcher and ranking of the shell's searches.
class ShellSearchBackend {
  const ShellSearchBackend();

  /// The most apps a search lists: a few screens of the grid.
  static const int maximumApps = 48;

  /// The most windows a search lists.
  static const int maximumWindows = 12;

  /// The most recent apps shown before anything is typed.
  static const int maximumRecentApps = 8;

  /// Searches [index] and [windows] (most recently used first) for [query]
  /// within [scope]. Every word of the query must match a word of the app's
  /// or window's names; see [searchShell] for the ranking, the `ё`, the other
  /// keyboard layout and the English names of translated apps.
  ShellSearchOutcome search(
    String query, {
    required ShellSearchScope scope,
    required ShellSearchIndex index,
    required List<ShellSearchOpenWindow> windows,
    List<String> recentIds = const [],
    int maxRecentApps = maximumRecentApps,
  }) {
    final apps = scope == ShellSearchScope.appsAndWindows
        ? index._matchable
        : const <LauncherApplication>[];
    if (normalizeShellSearchText(query).isEmpty) {
      return ShellSearchOutcome(
        query: query,
        scope: scope,
        apps: scope == ShellSearchScope.appsAndWindows ? index.apps : const [],
        windows: scope == ShellSearchScope.openWindows
            ? List.unmodifiable(windows.take(maximumWindows))
            : const [],
        recentApps: scope == ShellSearchScope.appsAndWindows
            ? index.recent(recentIds, max: maxRecentApps)
            : const [],
      );
    }
    final byId = {for (final window in windows) window.id: window};
    final results = searchShell(
      query,
      windows: [for (final window in windows) window._matchable],
      applications: apps,
      maxApplications: maximumApps,
    );
    return ShellSearchOutcome(
      query: query,
      scope: scope,
      apps: List.unmodifiable([
        for (final app in results.applications) ?index[app.id],
      ]),
      windows: List.unmodifiable(
        [for (final window in results.windows) ?byId[window.id]]
            .take(maximumWindows),
      ),
    );
  }

  /// The window of [app] used last among [windows] (most recent first), or
  /// null when the app has none open: choosing a running app switches to
  /// it, as on a Mac.
  DenialWindow? openWindowOf(
    ShellSearchApp app,
    Iterable<DenialWindow> windows,
  ) {
    for (final window in windows) {
      if (app.ownsWindow(window.appId)) {
        return window;
      }
    }
    return null;
  }
}

/// The shell's one search backend. Tests replace it to check that every
/// search surface shows what it answers, and only that.
final shellSearchBackendProvider = Provider<ShellSearchBackend>(
  (ref) => const ShellSearchBackend(),
);
