import 'package:denial_desktop/src/launcher/home_search.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter_test/flutter_test.dart';

DesktopApp _app(String id, String name, {List<String> keywords = const []}) =>
    DesktopApp(
      id: id,
      name: name,
      exec: id,
      desktopPath: '/usr/share/applications/$id.desktop',
      categories: const <String>[],
      keywords: keywords,
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

void main() {
  final firefox = HomeGridItem.app(_app('firefox', 'Firefox'));
  final files = HomeGridItem.app(
    _app('org.gnome.Nautilus', 'Files', keywords: ['folder', 'explorer']),
  );
  final settings = HomeGridItem.app(_app('denial-settings', 'Settings'));
  final terminal = HomeGridItem.app(_app('org.gnome.Console', 'Terminal'));

  HomeSearchCatalog catalog({List<HomeSearchWindow> windows = const []}) =>
      HomeSearchCatalog(
        windows: windows,
        apps: [firefox, files, settings, terminal],
        names: {
          firefox.id: 'Firefox',
          files.id: 'Files',
          settings.id: 'Settings',
          terminal.id: 'Terminal',
        },
      );

  final github = HomeSearchWindow(
    window: _window(1, 'firefox', 'GitHub — Mozilla Firefox'),
    appName: 'Firefox',
    app: firefox,
  );
  final mail = HomeSearchWindow(
    window: _window(2, 'firefox', 'Inbox — Mozilla Firefox'),
    appName: 'Firefox',
    app: firefox,
  );
  final shell = HomeSearchWindow(
    window: _window(3, 'org.gnome.Console', 'pingv@pad: ~'),
    appName: 'Terminal',
    app: terminal,
  );

  group('the drawer filters', () {
    test('apps by name, best first', () {
      final matches = catalog().search('fi');
      // "Files" and "Firefox" both start with it; ties sort by name.
      expect(matches.apps, [files, firefox]);
      expect(matches.windows, isEmpty);
      expect(matches.first, files);
    });

    test('apps by keyword, below name matches', () {
      final matches = catalog().search('folder');
      expect(matches.apps, [files]);
    });

    test('nothing for an unknown word', () {
      final matches = catalog(windows: [github]).search('calculator');
      expect(matches.isEmpty, isTrue);
      expect(matches.first, isNull);
    });

    test('a query typed in the other keyboard layout', () {
      // "ашду" is "file" typed on the Russian layout.
      expect(catalog().search('ашду').apps, [files]);
    });

    test('an empty query lists every window and no app', () {
      final matches = catalog(windows: [shell, github, mail]).search('  ');
      expect(matches.windows, [shell, github, mail]);
      expect(matches.apps, isEmpty);
      expect(matches.first, isNull);
    });
  });

  group('windows', () {
    test('match by title and come before apps', () {
      final matches = catalog(windows: [github, mail, shell]).search('inbox');
      expect(matches.windows, [mail]);
      expect(matches.first, mail);
    });

    test('of one app all match its name, most recent first', () {
      final matches = catalog(windows: [mail, github, shell]).search('firefox');
      expect(matches.windows, [mail, github]);
      expect(matches.apps, [firefox]);
      // Enter goes to the most recent window rather than a new one.
      expect(matches.first, mail);
    });
  });

  group('suggestions', () {
    test('recent apps follow the launcher history, newest first', () {
      final recent = catalog().recentApps([
        desktopApplicationRecentId('org.gnome.Console'),
        'desktop:gone.app',
        desktopApplicationRecentId('firefox'),
        desktopApplicationRecentId('org.gnome.Console'),
      ]);
      expect(recent, [terminal, firefox]);
    });

    test('are capped', () {
      final recent = catalog().recentApps([
        desktopApplicationRecentId('firefox'),
        desktopApplicationRecentId('org.gnome.Nautilus'),
        desktopApplicationRecentId('denial-settings'),
      ], max: 2);
      expect(recent, [firefox, files]);
    });
  });
}
