import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_desktop/src/search/shell_search_backend.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart' show DenialBridge;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The shell's one search backend (eb19): the index of apps, the open
// windows, and the one matcher and ranking every search surface uses.

DesktopApp _app(
  String id,
  String name, {
  List<String> keywords = const [],
  List<String> untranslated = const [],
  String? wmClass,
}) => DesktopApp(
  id: '$id.desktop',
  name: name,
  exec: id,
  desktopPath: '/usr/share/applications/$id.desktop',
  categories: const <String>[],
  keywords: keywords,
  untranslatedNames: untranslated,
  startupWmClass: wmClass,
);

DenialWindow _window(int id, String appId, String title) => DenialWindow(
  objectId: id,
  objectKind: 'xdg_toplevel',
  surfaceId: id,
  windowId: id,
  textureId: id,
  title: title,
  appId: appId,
  width: 100,
  height: 100,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 100,
  surfaceHeight: 100,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 100,
  textureSourceHeight: 100,
  geometryX: 0,
  geometryY: 0,
  geometryWidth: 100,
  geometryHeight: 100,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

final _firefox = HomeGridItem.app(_app('firefox', 'Firefox'));
final _files = HomeGridItem.app(
  _app(
    'org.gnome.Nautilus',
    'Файлы',
    keywords: ['папка'],
    untranslated: ['Files', 'folder'],
  ),
);
final _settings = HomeGridItem.app(_app('denial-settings', 'Settings'));
final _terminal = HomeGridItem.app(
  _app('org.gnome.Console', 'Терминал', untranslated: ['Terminal']),
);
final _calculator = LocalFlutterApplication(
  id: 'denial.calculator',
  title: 'Calculator',
  builder: (_, _) => const SizedBox(),
  categories: const ['Utility'],
);

class _Bridge extends DenialBridge {}

ShellSearchIndex _index() => ShellSearchIndex.build(
  homeApps: [
    _settings,
    _firefox,
    HomeGridItem.folder(id: 'tools', name: 'Tools', apps: [_files, _terminal]),
    // The same app twice on home is one app.
    _firefox,
  ].expand((item) => item.apps),
  localApps: [_calculator],
  launcher: AppLauncher(bridge: _Bridge()),
  titleOf: (app) => app.title,
  categoriesOf: (app) => app.categories,
);

List<String> _names(Iterable<ShellSearchApp> apps) => [
  for (final app in apps) app.name,
];

void main() {
  // The launcher the index asks for an app's window ids needs the bridge.
  TestWidgetsFlutterBinding.ensureInitialized();
  const backend = ShellSearchBackend();
  final index = _index();
  final windows = shellSearchOpenWindows(
    [
      _window(2, 'firefox', 'Inbox — Mozilla Firefox'),
      _window(3, 'org.gnome.Console', 'pingv@pad: ~'),
      _window(1, 'firefox', 'GitHub — Mozilla Firefox'),
      _window(9, 'org.example.Unknown', 'Report.odt'),
    ],
    index: index,
    titleOf: (window) => window.title,
  );

  ShellSearchOutcome search(
    String query, {
    ShellSearchScope scope = ShellSearchScope.appsAndWindows,
    List<String> recent = const [],
  }) => backend.search(
    query,
    scope: scope,
    index: index,
    windows: windows,
    recentIds: recent,
  );

  group('the index', () {
    test('has every app once, by name, the shell\'s own apps too', () {
      expect(_names(index.apps), [
        'Calculator',
        'Firefox',
        'Settings',
        'Терминал',
        'Файлы',
      ]);
      expect(
        index[desktopApplicationRecentId('firefox.desktop')]?.name,
        'Firefox',
      );
      expect(
        index[localApplicationRecentId('denial.calculator')]?.localApp,
        same(_calculator),
      );
    });

    test('knows which app a window belongs to', () {
      expect(index.appOfWindow('firefox')?.name, 'Firefox');
      expect(index.appOfWindow('org.gnome.Console.desktop')?.name, 'Терминал');
      expect(index.appOfWindow('denial.calculator')?.name, 'Calculator');
      expect(index.appOfWindow('org.example.Unknown'), isNull);
    });

    test('names a window by its app, else by its title', () {
      expect(
        [for (final window in windows) window.appName],
        ['Firefox', 'Терминал', 'Firefox', 'Report.odt'],
      );
    });

    test('lists the apps started last, newest first, capped', () {
      final recent = index.recent([
        desktopApplicationRecentId('org.gnome.Console.desktop'),
        'desktop:gone.desktop',
        desktopApplicationRecentId('firefox.desktop'),
        desktopApplicationRecentId('org.gnome.Console.desktop'),
        localApplicationRecentId('denial.calculator'),
      ], max: 2);
      expect(_names(recent), ['Терминал', 'Firefox']);
    });
  });

  group('the one search', () {
    test('with nothing typed: every app and the recent ones, no window', () {
      final outcome = search(
        '  ',
        recent: [desktopApplicationRecentId('firefox.desktop')],
      );
      expect(outcome.searching, isFalse);
      expect(_names(outcome.apps), _names(index.apps));
      expect(_names(outcome.recentApps), ['Firefox']);
      expect(outcome.windows, isEmpty);
      expect(outcome.first, isNull);
    });

    test('apps first, then windows; Enter takes the best app', () {
      final outcome = search('fire');
      expect(_names(outcome.apps), ['Firefox']);
      // Both of Firefox's windows, the one used last first.
      expect([for (final window in outcome.windows) window.id], [2, 1]);
      expect(outcome.first, ShellSearchAppTarget(outcome.apps.single));
    });

    test('a window alone, by its title', () {
      final outcome = search('inbox');
      expect(outcome.apps, isEmpty);
      expect([for (final window in outcome.windows) window.id], [2]);
      expect(outcome.first, ShellSearchWindowTarget(outcome.windows.single));
    });

    test('a translated app by its English words', () {
      expect(_names(search('files').apps), ['Файлы']);
      expect(_names(search('term').apps), ['Терминал']);
      expect(_names(search('папка').apps), ['Файлы']);
    });

    test('an open window of a translated app by the same words', () {
      // On the tablet "files" listed «Файлы» but not its open window, while
      // «файлы» and "afqks" (it on the Latin keys) found both.
      final open = shellSearchOpenWindows(
        [
          _window(5, 'org.gnome.Nautilus', 'Загрузки'),
          ...[for (final window in windows) window.window],
        ],
        index: index,
        titleOf: (window) => window.title,
      );
      for (final query in ['files', 'folder', 'папка', 'файлы', 'afqks']) {
        for (final scope in ShellSearchScope.values) {
          final outcome = backend.search(
            query,
            scope: scope,
            index: index,
            windows: open,
          );
          expect(
            [for (final window in outcome.windows) window.id],
            [5],
            reason: '"$query" in $scope',
          );
        }
      }
      final terminal = search('terminal');
      expect(_names(terminal.apps), ['Терминал']);
      expect([for (final window in terminal.windows) window.id], [3]);
    });

    test('a query typed in the other keyboard layout', () {
      // "ашду" is "file" typed on the Russian keys, and "nthv" is "терм"
      // typed on the Latin ones.
      expect(_names(search('ашду').apps), ['Файлы']);
      expect(_names(search('nthv').apps), ['Терминал']);
    });

    test('ё and е are one letter, case does not matter', () {
      final yo = shellSearchOpenWindows(
        [_window(4, 'org.gnome.TextEditor', 'Ёлка.txt')],
        index: index,
        titleOf: (window) => window.title,
      );
      final outcome = backend.search(
        'ЕЛКА',
        scope: ShellSearchScope.openWindows,
        index: index,
        windows: yo,
      );
      expect([for (final window in outcome.windows) window.id], [4]);
    });

    test('nothing for an unknown word', () {
      final outcome = search('zzzz');
      expect(outcome.isEmpty, isTrue);
      expect(outcome.first, isNull);
    });
  });

  group('the overview\'s search', () {
    test('finds only open windows, never apps to start', () {
      final outcome = search('fire', scope: ShellSearchScope.openWindows);
      expect(outcome.apps, isEmpty);
      expect([for (final window in outcome.windows) window.id], [2, 1]);
      expect(
        search('settings', scope: ShellSearchScope.openWindows).isEmpty,
        isTrue,
      );
      expect(
        search('calc', scope: ShellSearchScope.openWindows).isEmpty,
        isTrue,
      );
    });

    test('with nothing typed lists every open window', () {
      final outcome = search('', scope: ShellSearchScope.openWindows);
      expect([for (final window in outcome.windows) window.id], [2, 3, 1, 9]);
      expect(outcome.apps, isEmpty);
      expect(outcome.recentApps, isEmpty);
    });
  });

  group('choosing a running app', () {
    test('switches to its window used last', () {
      final firefox = index[desktopApplicationRecentId('firefox.desktop')]!;
      final settings =
          index[desktopApplicationRecentId('denial-settings.desktop')]!;
      final open = [for (final window in windows) window.window];
      expect(backend.openWindowOf(firefox, open)?.objectId, 2);
      expect(backend.openWindowOf(settings, open), isNull);
    });

    test('the desktop\'s windows come by their last use', () {
      final strip = [
        _window(1, 'a', 'one'),
        _window(2, 'b', 'two'),
        _window(3, 'c', 'three'),
      ];
      DesktopWindowPlacement at(int id, int z) => DesktopWindowPlacement(
        objectId: id,
        frame: const Rect.fromLTWH(0, 0, 10, 10),
        z: z,
        monitorId: 1,
      );
      expect(
        [
          for (final window in shellSearchMostRecentFirst(strip, {
            1: at(1, 5),
            2: at(2, 9),
            3: at(3, 1),
          }))
            window.objectId,
        ],
        [2, 1, 3],
      );
    });
  });
}
