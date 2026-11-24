import 'dart:io';

import 'package:denial_desktop/src/desktop/desktop_overview_hub.dart';
import 'package:denial_desktop/src/desktop/desktop_overview_motion.dart';
import 'package:denial_desktop/src/desktop/desktop_search_overlay.dart';
import 'package:denial_desktop/src/desktop/desktop_shell_search.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_desktop/src/launcher/widgets/home_app_drawer.dart';
import 'package:denial_desktop/src/launcher/widgets/home_search_sheet.dart';
import 'package:denial_desktop/src/search/shell_search_backend.dart';
import 'package:denial_desktop/src/search/shell_search_view.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart' show DenialBridge;
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The owner's rule for eb19: ONE search backend. Every search surface of the
// shell takes its results from `shellSearchBackendProvider`
// (plugins/denial_desktop/lib/src/search/shell_search_backend.dart), and no
// other code matches apps or windows against what was typed. This file
// fails when a second matcher is introduced or used:
//
// 1. Each surface (the one search over the desktop, the overview's search,
//    the tablet's app drawer and its pull-down search) runs with a fake
//    backend that answers a query with results that do NOT match it, in an
//    order no ranking would give. The surface must show exactly those, in
//    that order, and Enter must act on the backend's first. A surface that
//    filtered or ranked by itself would drop or reorder them; one that went
//    around the backend would not show them at all. The fake also records
//    the scope each surface asks for: the overview asks for open windows
//    only.
// 2. The sources of the shell, its plugins and packages are scanned: only
//    the backend may call the SDK's matcher (searchShell and its text
//    helpers) or read an app's search words (searchableText), and no file
//    that deals with apps or windows may test a string against a query
//    (`.contains(query)`, `toLowerCase().contains(...)` and the like).

/// The checkout's root: tests run in dart_shell.
final _root = Directory.current.parent.path;

/// The one backend and the SDK matcher it runs.
const _backendFile =
    'plugins/denial_desktop/lib/src/search/shell_search_backend.dart';
const _matcherFile =
    'packages/denial_flutter_sdk/lib/src/launcher/shell_search.dart';

/// Where `searchableText` is defined rather than read.
const _searchWordsDefinitions = {
  'packages/denial_sdk/lib/src/applications/desktop_app.dart',
  'packages/denial_flutter_sdk/lib/launcher.dart',
};

/// Lines the query-matching pattern finds that are not searches, each with
/// why. Adding to this list needs the same justification.
const _notSearches = {
  // The desktop entry for an icon or window name: a file-name rule, not a
  // query typed by the user.
  'packages/denial_flutter_sdk/lib/src/launcher/repositories/'
          'desktop_apps_repository.dart':
      'requestedName.endsWith(normalized)',
};

Iterable<(String, List<String>)> _sources() sync* {
  for (final top in ['plugins', 'packages', 'dart_shell/lib']) {
    final dir = Directory(p.join(_root, top));
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = p.relative(entity.path, from: _root).replaceAll(r'\', '/');
      if (path.contains('/test/') ||
          path.contains('/integration_test/') ||
          path.contains('/.dart_tool/') ||
          path.contains('/l10n/generated/') ||
          !(path.contains('/lib/') || path.startsWith('dart_shell/lib'))) {
        continue;
      }
      yield (path, entity.readAsLinesSync());
    }
  }
}

/// Lines that are code: comments and doc comments are left out.
Iterable<(int, String)> _code(List<String> lines) sync* {
  for (final (index, line) in lines.indexed) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) {
      continue;
    }
    yield (index + 1, line);
  }
}

final _appOrWindowTypes = RegExp(
  r'\b(DesktopApp|LauncherApplication|HomeGridItem|LocalFlutterApplication|'
  r'DenialWindow|ShellSearchApp|ShellSearchOpenWindow|LaunchableApplication|'
  r'ApplicationWindow)\b',
);

final _queryMatch = RegExp(
  r'\.(contains|startsWith|endsWith|indexOf)\(\s*(query|normalizedQuery|'
  r'needle|search|term|typed|filter|q|text|lower|normalized)\b|'
  r'toLowerCase\(\)\.(contains|startsWith|indexOf)\(',
);

// The fake backend -----------------------------------------------------------

/// Answers every typed query with [apps] and [windows] as given, whatever
/// was typed, and records what it was asked.
class _FakeBackend extends ShellSearchBackend {
  _FakeBackend({required this.apps, required this.windows});

  /// App names and window ids to answer with, in this order.
  final List<String> apps;
  final List<int> windows;
  final asked = <(String, ShellSearchScope)>[];

  @override
  ShellSearchOutcome search(
    String query, {
    required ShellSearchScope scope,
    required ShellSearchIndex index,
    required List<ShellSearchOpenWindow> windows,
    List<String> recentIds = const [],
    int maxRecentApps = ShellSearchBackend.maximumRecentApps,
  }) {
    if (query.trim().isEmpty) {
      return super.search(
        query,
        scope: scope,
        index: index,
        windows: windows,
        recentIds: recentIds,
        maxRecentApps: maxRecentApps,
      );
    }
    asked.add((query, scope));
    return ShellSearchOutcome(
      query: query,
      scope: scope,
      apps: [
        for (final name in apps)
          index.apps.firstWhere((app) => app.name == name),
      ],
      windows: [
        for (final id in this.windows)
          windows.firstWhere((window) => window.id == id),
      ],
    );
  }
}

// What the surfaces look through ----------------------------------------------

DesktopApp _app(String id, String name) => DesktopApp(
  id: '$id.desktop',
  name: name,
  exec: id,
  desktopPath: '/usr/share/applications/$id.desktop',
  categories: const <String>[],
);

/// Screen [index] of the full-screen apps layout's strip, the first one
/// current: the tablet's work area, side by side.
Rect _screen(int index) =>
    Rect.fromLTWH((index - 1) * (1357.0 + 8.0), 32, 1357, 928);

/// A window on screen [id] of its own.
DenialWindow _window(int id, String appId, String title) => DenialWindow(
  objectId: id,
  objectKind: 'xdg_toplevel',
  surfaceId: id + 100,
  windowId: id + 200,
  textureId: id + 300,
  title: title,
  appId: appId,
  width: 1357,
  height: 928,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 1357,
  surfaceHeight: 928,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 1357,
  textureSourceHeight: 928,
  geometryX: _screen(id).left,
  geometryY: 32,
  geometryWidth: 1357,
  geometryHeight: 928,
  monitorId: 1,
  transform: 0,
  scale120: 120,
  layoutScreen: id,
  layoutScreenRect: _screen(id),
);

final _apps = [
  HomeGridItem.app(_app('firefox', 'Firefox')),
  HomeGridItem.app(_app('org.gnome.Nautilus', 'Files')),
  HomeGridItem.app(_app('org.gnome.Console', 'Console')),
  HomeGridItem.app(_app('org.gnome.Calculator', 'Calculator')),
];

final _windows = [
  _window(1, 'firefox', 'Mozilla Firefox'),
  _window(2, 'org.gnome.Nautilus', 'Documents'),
  _window(3, 'org.gnome.Console', 'pingv@pad: ~'),
];

class _Grid extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: <HomeGridItem?>[..._apps]);
}

class _Recents extends ApplicationRecentsController {
  @override
  List<String> build() => const [];
}

class _Bridge extends DenialBridge {}

const _view = Size(1357, 960);

/// A query no app or window matches.
const _nonsense = 'qqq';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  required ShellSearchBackend backend,
}) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      denialBridgeProvider.overrideWithValue(_Bridge()),
      homeGridControllerProvider.overrideWith(_Grid.new),
      applicationRecentsProvider.overrideWith(_Recents.new),
      shellSearchDeskWindowsProvider.overrideWithValue(_windows),
      shellSearchPhoneWindowsProvider.overrideWithValue(_windows),
      shellSearchBackendProvider.overrideWithValue(backend),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: DenialLocalizationScope(
        locale: const Locale('en'),
        child: MediaQuery(
          data: const MediaQueryData(size: _view),
          child: ShellTheme(
            data: const ShellThemeData(
              transparencyMode: ShellTransparencyMode.off,
              panelOpacity: 1,
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) =>
                        Stack(children: [Positioned.fill(child: child)]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
}

/// The apps the surface shows as found, in reading order, by their
/// desktop entry id: the tiles keyed 'a:' and the app's launcher id.
List<String> _shownApps(WidgetTester tester) {
  final tiles = find.byWidgetPredicate(
    (widget) => switch (widget.key) {
      ValueKey<String>(:final value) => value.startsWith('a:'),
      _ => false,
    },
  );
  final found =
      [
        for (final element in tiles.evaluate())
          (
            (element.widget.key! as ValueKey<String>).value.substring(
              'a:desktop:'.length,
            ),
            tester.getTopLeft(find.byWidget(element.widget)),
          ),
      ]..sort((a, b) {
        final byRow = a.$2.dy.compareTo(b.$2.dy);
        return byRow != 0 ? byRow : a.$2.dx.compareTo(b.$2.dx);
      });
  return [for (final (id, _) in found) id];
}

/// The window ids of the rows the surface shows, top to bottom.
List<int> _shownWindows(WidgetTester tester) {
  final rows = find.byType(ShellSearchWindowRow);
  final ids = [
    for (final row in tester.widgetList<ShellSearchWindowRow>(rows))
      row.window.id,
  ];
  final tops = {
    for (final (index, id) in ids.indexed)
      id: tester.getTopLeft(rows.at(index)).dy,
  };
  return ids..sort((a, b) => tops[a]!.compareTo(tops[b]!));
}

void main() {
  group('every search surface shows what the one backend answers', () {
    testWidgets('the one search over the desktop', (tester) async {
      // Calculator does not run: Enter starts it.
      final backend = _FakeBackend(apps: ['Calculator', 'Files'], windows: [3]);
      final launched = <String>[];
      final activated = <int>[];
      final container = await _pump(
        tester,
        DesktopSearchOverlay(
          viewSize: _view,
          displayLayout: null,
          onActivateWindow: (window) => activated.add(window.objectId),
          onLaunchApplication: (app) => launched.add(app.name),
          onLaunchLocalApplication: (app) => launched.add(app.title),
        ),
        backend: backend,
      );
      container.read(desktopSearchOverlayProvider.notifier).open(1);
      await tester.pump();
      await tester.pump();
      await _type(tester, _nonsense);

      expect(backend.asked, [(_nonsense, ShellSearchScope.appsAndWindows)]);
      expect(_shownApps(tester), [
        'org.gnome.Calculator.desktop',
        'org.gnome.Nautilus.desktop',
      ]);
      expect(_shownWindows(tester), [3]);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(launched, ['Calculator']);
      expect(activated, isEmpty);
    });

    testWidgets('the overview, over open windows only', (tester) async {
      final backend = _FakeBackend(apps: [], windows: [3, 1]);
      final activated = <int>[];
      final container = await _pump(
        tester,
        DesktopOverviewHub(
          onActivateWindow: (window) => activated.add(window.objectId),
          onDismiss: () {},
          onNavigate: (_) {},
          onActivateSelection: () {},
        ),
        backend: backend,
      );
      container
          .read(desktopWorkspaceProvider.notifier)
          .syncWindows(
            _windows,
            _view,
            1,
            snapshotSequence: 1,
            windowLayout: DesktopWindowLayout.screens,
          );
      container
          .read(desktopWorkspaceProvider.notifier)
          .openScreensOverview(
            monitorId: 1,
            bounds: DesktopOverviewHubMetrics.contentBounds(
              Rect.fromLTRB(0, 44, _view.width, _view.height),
            ),
            backgroundBounds: Offset.zero & _view,
            viewport: const Rect.fromLTWH(0, 32, 1357, 928),
            selectedObjectId: 2,
          );
      container.read(desktopOverviewMotionProvider).open(animate: false);
      await tester.pump();
      await tester.pump();
      await _type(tester, _nonsense);

      expect(backend.asked.last, (_nonsense, ShellSearchScope.openWindows));
      expect(
        backend.asked.every(
          (asked) => asked.$2 == ShellSearchScope.openWindows,
        ),
        isTrue,
      );
      expect(_shownWindows(tester), [3, 1]);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(activated, [3]);
    });

    testWidgets('the tablet\'s app drawer', (tester) async {
      final backend = _FakeBackend(apps: ['Console', 'Firefox'], windows: [2]);
      final launched = <String>[];
      await _pump(
        tester,
        HomeAppDrawer(
          openness: const AlwaysStoppedAnimation(1),
          columns: 6,
          onLaunch: (app, _) => launched.add(app.name),
          onOpenWindow: (_, _) {},
          onDrag: (_) {},
          onDragEnd: (_) {},
        ),
        backend: backend,
      );
      await _type(tester, _nonsense);

      expect(backend.asked, [(_nonsense, ShellSearchScope.appsAndWindows)]);
      expect(_shownApps(tester), [
        'org.gnome.Console.desktop',
        'firefox.desktop',
      ]);
      expect(_shownWindows(tester), [2]);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(launched, ['Console']);
    });

    testWidgets('the tablet\'s pull-down search', (tester) async {
      final backend = _FakeBackend(apps: [], windows: [2, 1]);
      final opened = <int>[];
      await _pump(
        tester,
        HomeSearchSheet(
          openness: const AlwaysStoppedAnimation(1),
          columns: 6,
          onLaunch: (_, _) {},
          onOpenWindow: (window, _) => opened.add(window.id),
          onClose: () {},
          onDrag: (_) {},
          onDragEnd: (_) {},
        ),
        backend: backend,
      );
      await _type(tester, _nonsense);

      expect(backend.asked, [(_nonsense, ShellSearchScope.appsAndWindows)]);
      expect(_shownApps(tester), isEmpty);
      expect(_shownWindows(tester), [2, 1]);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(opened, [2]);
    });

    testWidgets('the real backend finds nothing for the same query', (
      tester,
    ) async {
      await _pump(
        tester,
        HomeAppDrawer(
          openness: const AlwaysStoppedAnimation(1),
          columns: 6,
          onLaunch: (_, _) {},
          onOpenWindow: (_, _) {},
          onDrag: (_) {},
          onDragEnd: (_) {},
        ),
        backend: const ShellSearchBackend(),
      );
      await _type(tester, _nonsense);
      expect(find.text('Nothing found'), findsOneWidget);
      expect(_shownWindows(tester), isEmpty);
    });
  });

  group('no second matcher in the sources', () {
    test('the sources are found', () {
      final files = [for (final (path, _) in _sources()) path];
      expect(files, contains(_backendFile));
      expect(files, contains(_matcherFile));
      expect(files.length, greaterThan(200));
    });

    test('only the backend runs the SDK matcher', () {
      final calls = RegExp(
        r'\b(searchShell|normalizeShellSearchText|swapShellSearchKeyboardLayout)\(',
      );
      final offenders = [
        for (final (path, lines) in _sources())
          if (path != _backendFile && path != _matcherFile)
            for (final (line, text) in _code(lines))
              if (calls.hasMatch(text)) '$path:$line: ${text.trim()}',
      ];
      expect(offenders, isEmpty, reason: 'search through the one backend');
    });

    test('only the backend reads the apps\' search words', () {
      final offenders = [
        for (final (path, lines) in _sources())
          if (path != _backendFile &&
              path != _matcherFile &&
              !_searchWordsDefinitions.contains(path))
            for (final (line, text) in _code(lines))
              if (text.contains('searchableText'))
                '$path:$line: ${text.trim()}',
      ];
      expect(offenders, isEmpty, reason: 'search through the one backend');
    });

    test('nothing that lists apps or windows tests them against a query', () {
      final offenders = <String>[];
      for (final (path, lines) in _sources()) {
        if (path == _backendFile || path == _matcherFile) {
          continue;
        }
        if (!lines.any(_appOrWindowTypes.hasMatch)) {
          continue;
        }
        for (final (line, text) in _code(lines)) {
          if (!_queryMatch.hasMatch(text)) {
            continue;
          }
          if (_notSearches[path] case final allowed?
              when text.contains(allowed)) {
            continue;
          }
          offenders.add('$path:$line: ${text.trim()}');
        }
      }
      expect(offenders, isEmpty, reason: 'search through the one backend');
    });

    test('the patterns catch the matchers eb18 had', () {
      // The old launcher plugin's filter and the tablet's own lower-casing
      // filter, as they were written.
      expect(
        _queryMatch.hasMatch(
          "      .where((app) => app.searchableText.contains(query))",
        ),
        isTrue,
      );
      expect(
        _queryMatch.hasMatch(
          '        .where((app) => names[app]!.toLowerCase().contains(q))',
        ),
        isTrue,
      );
      expect(
        _queryMatch.hasMatch('  if (title.toLowerCase().startsWith(text)) {'),
        isTrue,
      );
    });
  });
}
