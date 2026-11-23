import 'package:denial_flutter_sdk/launcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _files = LauncherApplication(
  id: 'desktop:org.gnome.Nautilus',
  name: 'Files',
  searchableText: 'org.gnome.nautilus files system filemanager',
);
const _firefox = LauncherApplication(
  id: 'desktop:firefox',
  name: 'Firefox',
  searchableText: 'firefox firefox network webbrowser',
);
const _papers = LauncherApplication(
  id: 'desktop:org.gnome.Papers',
  name: 'Papers',
  searchableText: 'org.gnome.papers papers office viewer pdf',
);
const _settings = LauncherApplication(
  id: 'local:settings',
  name: 'Настройки',
  searchableText: 'settings настройки settings',
);
const _terminal = LauncherApplication(
  id: 'desktop:org.gnome.Console',
  name: 'Console',
  searchableText: 'org.gnome.console console system terminalemulator',
);

const _apps = [_files, _firefox, _papers, _settings, _terminal];

const _report = ShellSearchWindow(
  id: 11,
  appId: 'org.gnome.Papers',
  appName: 'Papers',
  title: 'Quarterly report.pdf',
);
const _manual = ShellSearchWindow(
  id: 12,
  appId: 'org.gnome.Papers',
  appName: 'Papers',
  title: 'Manual — chapter 2',
);
const _browser = ShellSearchWindow(
  id: 13,
  appId: 'firefox',
  appName: 'Firefox',
  title: 'Новости — Mozilla Firefox',
);

const _windows = [_report, _manual, _browser];

ShellSearchResults _search(String query, {int maxApplications = 8}) =>
    searchShell(
      query,
      windows: _windows,
      applications: _apps,
      maxApplications: maxApplications,
    );

void main() {
  test('an empty query lists every window in order and no apps', () {
    for (final query in ['', '   ']) {
      final results = _search(query);
      expect(results.windows, _windows);
      expect(results.applications, isEmpty);
      expect(results.first, isNull, reason: 'Enter does nothing yet');
    }
  });

  test('windows match by app name and by title', () {
    expect(_search('papers').windows, [_report, _manual]);
    expect(_search('report').windows, [_report]);
    expect(_search('chapter').windows, [_manual]);
    expect(_search('новости').windows, [_browser]);
  });

  test('apps match by name, then by their other text', () {
    expect(_search('fire').applications, [_firefox]);
    expect(_search('pdf').applications, [_papers]);
    expect(_search('terminal').applications, [_terminal]);
    expect(_search('настр').applications, [_settings]);
    expect(_search('zzz').isEmpty, isTrue);
  });

  test(
    'a name that starts with the query ranks above one that contains it',
    () {
      const consoleLike = LauncherApplication(
        id: 'desktop:x',
        name: 'Xfce Console Tools',
        searchableText: 'x',
      );
      const insider = LauncherApplication(
        id: 'desktop:y',
        name: 'Teleconsole',
        searchableText: 'y',
      );
      final results = searchShell(
        'console',
        windows: const [],
        applications: const [insider, consoleLike, _terminal],
      );
      expect(results.applications, [_terminal, consoleLike, insider]);
    },
  );

  test('matches in a name rank above matches in other text', () {
    const nameMatch = LauncherApplication(
      id: 'desktop:a',
      name: 'Viewer',
      searchableText: 'a',
    );
    final results = searchShell(
      'viewer',
      windows: const [],
      applications: const [_papers, nameMatch],
    );
    expect(results.applications, [nameMatch, _papers]);
  });

  test('every word of the query must match', () {
    expect(_search('papers report').windows, [_report]);
    expect(_search('papers firefox').windows, isEmpty);
  });

  test('case and ё do not matter', () {
    expect(_search('FIREFOX').applications, [_firefox]);
    const hedgehog = LauncherApplication(
      id: 'desktop:h',
      name: 'Ёжик',
      searchableText: 'h',
    );
    expect(
      searchShell(
        'ежик',
        windows: const [],
        applications: const [hedgehog],
      ).applications,
      [hedgehog],
    );
  });

  test('a query typed in the other keyboard layout still finds', () {
    // "firefox" typed with the Russian layout on, and "настройки" with the
    // Latin one.
    expect(_search('ашкуащч').applications, [_firefox]);
    expect(_search('yfcnhjqrb').applications, [_settings]);
    expect(swapShellSearchKeyboardLayout('Ашк'), 'Fir');
  });

  test('direct matches rank above other-layout matches', () {
    // "ку" is "re" in the other layout: "Quarterly report" matches it, but a
    // window whose title has "ку" itself comes first.
    const direct = ShellSearchWindow(
      id: 20,
      appId: 'x',
      appName: 'X',
      title: 'куб',
    );
    final results = searchShell(
      'ку',
      windows: const [_report, direct],
      applications: const [],
    );
    expect(results.windows.first, direct);
    expect(results.windows, contains(_report));
  });

  test('Enter takes the best window, else the best app', () {
    final papers = _search('papers').first;
    expect(papers, isA<ShellSearchWindowHit>());
    expect((papers! as ShellSearchWindowHit).window, _report);
    final console = _search('console').first;
    expect(console, isA<ShellSearchApplicationHit>());
    expect((console! as ShellSearchApplicationHit).application, _terminal);
    expect(_search('zzz').first, isNull);
  });

  test('ties keep the window order and sort apps by name', () {
    final results = searchShell(
      'org',
      windows: const [_manual, _report],
      applications: const [_terminal, _papers, _files],
    );
    expect(results.windows, [_manual, _report]);
    expect(results.applications, [_terminal, _files, _papers]);
  });

  test('apps are capped', () {
    expect(_search('o', maxApplications: 2).applications, hasLength(2));
    expect(_search('o', maxApplications: 0).applications, isEmpty);
  });
}
