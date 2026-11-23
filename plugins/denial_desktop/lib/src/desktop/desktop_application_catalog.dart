import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:flutter/widgets.dart';

/// The apps the desktop's launcher and search offer, by launcher id
/// ([desktopApplicationRecentId], [localApplicationRecentId]).
@immutable
class DesktopApplicationCatalog {
  const DesktopApplicationCatalog({
    required this.applications,
    required this.desktopApps,
    required this.localApps,
    required this._windowNames,
  });

  static const empty = DesktopApplicationCatalog(
    applications: <LauncherApplication>[],
    desktopApps: <String, DesktopApp>{},
    localApps: <String, LocalFlutterApplication>{},
    windowNames: <String, String>{},
  );

  final List<LauncherApplication> applications;
  final Map<String, DesktopApp> desktopApps;
  final Map<String, LocalFlutterApplication> localApps;

  /// App names by the app ids their windows carry, lower case.
  final Map<String, String> _windowNames;

  /// The name of the app whose windows carry [appId], or null when no app
  /// of the catalog opens such windows.
  String? nameForWindow(String appId) =>
      _windowNames[appId.trim().toLowerCase()];
}

/// Builds the catalog again only when the home grid, the local apps or the
/// locale change.
class DesktopApplicationCatalogCache {
  List<HomeGridItem?>? _slots;
  LocalFlutterApplicationRegistry? _registry;
  AppLauncher? _launcher;
  Locale? _locale;
  DesktopApplicationCatalog _catalog = DesktopApplicationCatalog.empty;

  DesktopApplicationCatalog resolve(
    BuildContext context, {
    required List<HomeGridItem?>? slots,
    required LocalFlutterApplicationRegistry registry,
    required AppLauncher launcher,
  }) {
    final locale = Localizations.maybeLocaleOf(context);
    if (identical(_slots, slots) &&
        identical(_registry, registry) &&
        identical(_launcher, launcher) &&
        _locale == locale) {
      return _catalog;
    }
    _slots = slots;
    _registry = registry;
    _launcher = launcher;
    _locale = locale;
    final desktopApps = <String, DesktopApp>{
      for (final app in HomeGridLayout.appsIn(
        slots ?? const <HomeGridItem?>[],
      ).map((item) => item.app).whereType<DesktopApp>())
        desktopApplicationRecentId(app.id): app,
    };
    final localApps = <String, LocalFlutterApplication>{
      for (final app in registry.applications)
        localApplicationRecentId(app.id): app,
    };
    final windowNames = <String, String>{};
    for (final app in desktopApps.values) {
      for (final appId in launcher.expectedWindowAppIds(app)) {
        windowNames.putIfAbsent(appId.trim().toLowerCase(), () => app.name);
      }
    }
    for (final app in localApps.values) {
      windowNames[app.id.trim().toLowerCase()] = app.titleFor(context);
    }
    return _catalog = DesktopApplicationCatalog(
      applications: List.unmodifiable([
        for (final entry in desktopApps.entries)
          LauncherApplication(
            id: entry.key,
            name: entry.value.name,
            searchableText: entry.value.searchableText,
          ),
        for (final entry in localApps.entries)
          LauncherApplication(
            id: entry.key,
            name: entry.value.titleFor(context),
            searchableText: [
              entry.value.id,
              entry.value.titleFor(context),
              ...entry.value.categoriesFor(context),
            ].join(' ').toLowerCase(),
          ),
      ]),
      desktopApps: Map.unmodifiable(desktopApps),
      localApps: Map.unmodifiable(localApps),
      windowNames: Map.unmodifiable(windowNames),
    );
  }
}
