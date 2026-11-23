import 'package:flutter/foundation.dart';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/models.dart';

/// One open window as the tablet's search lists it.
@immutable
class HomeSearchWindow {
  const HomeSearchWindow({
    required this.window,
    required this.appName,
    this.app,
  });

  final DenialWindow window;

  /// The app's name from home, or the window's own name for an app home
  /// does not have.
  final String appName;

  /// The app's home item, for its icon; null when home does not have it.
  final HomeGridItem? app;
}

/// What the tablet's search, in the app drawer and on a pull down over home,
/// searches: the phone's open windows and every app on home. It runs the
/// shell's shared search ([searchShell]), so it finds what the desktop's
/// overview and search overlay find.
@immutable
class HomeSearchCatalog {
  HomeSearchCatalog({
    required List<HomeSearchWindow> windows,
    required List<HomeGridItem> apps,
    required Map<String, String> names,
    Map<String, String> searchableText = const {},
  }) : windows = List.unmodifiable(windows),
       apps = List.unmodifiable(apps),
       _names = Map.unmodifiable(names),
       _searchable = Map.unmodifiable(searchableText);

  /// Open windows, most recently in front first.
  final List<HomeSearchWindow> windows;

  /// Every app on home, folders opened.
  final List<HomeGridItem> apps;

  /// Each app's display name, by home item id.
  final Map<String, String> _names;

  /// Each app's other searchable words (categories, keywords), by home
  /// item id.
  final Map<String, String> _searchable;

  /// The most apps a search lists; more would need a scroll for nothing.
  static const int maxApplications = 24;

  String nameOf(HomeGridItem app) => _names[app.id] ?? '';

  /// The windows and apps matching [query], best first. An empty query
  /// matches every window and no app.
  HomeSearchMatches search(String query) {
    final windowsById = {
      for (final entry in windows) entry.window.objectId: entry,
    };
    final appsById = {for (final app in apps) app.id: app};
    final results = searchShell(
      query,
      windows: [
        for (final entry in windows)
          ShellSearchWindow(
            id: entry.window.objectId,
            appId: entry.window.appId,
            appName: entry.appName,
            title: entry.window.title,
          ),
      ],
      applications: [
        for (final app in apps)
          LauncherApplication(
            id: app.id,
            name: nameOf(app),
            searchableText:
                _searchable[app.id] ?? app.app?.searchableText ?? '',
          ),
      ],
      maxApplications: maxApplications,
    );
    return HomeSearchMatches(
      query: query,
      windows: [for (final window in results.windows) ?windowsById[window.id]],
      apps: [for (final app in results.applications) ?appsById[app.id]],
      first: switch (results.first) {
        ShellSearchWindowHit(:final window) => windowsById[window.id],
        ShellSearchApplicationHit(:final application) =>
          appsById[application.id],
        null => null,
      },
    );
  }

  /// The apps started most recently, newest first, as [recentIds] (the
  /// launcher's history, `desktop:` and `local:` ids) lists them: what the
  /// pull down suggests before anything is typed.
  List<HomeGridItem> recentApps(List<String> recentIds, {int max = 8}) {
    final byRecentId = <String, HomeGridItem>{
      for (final app in apps)
        if (app.app case final desktop?)
          desktopApplicationRecentId(desktop.id): app
        else if (app.localApp case final local?)
          localApplicationRecentId(local.id): app,
    };
    final seen = <String>{};
    return [
      for (final id in recentIds)
        if (byRecentId[id] case final app? when seen.add(app.id)) app,
    ].take(max).toList(growable: false);
  }
}

/// A search's results, mapped back to windows and home apps.
@immutable
class HomeSearchMatches {
  const HomeSearchMatches({
    required this.query,
    required this.windows,
    required this.apps,
    required this.first,
  });

  final String query;
  final List<HomeSearchWindow> windows;
  final List<HomeGridItem> apps;

  /// What the keyboard's Enter acts on: a [HomeSearchWindow] to go to or a
  /// [HomeGridItem] to start; none for an empty query.
  final Object? first;

  bool get isEmpty => windows.isEmpty && apps.isEmpty;
}
