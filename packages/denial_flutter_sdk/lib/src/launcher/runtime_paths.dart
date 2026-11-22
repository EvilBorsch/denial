import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/startup_environment.dart';

class RuntimePaths {
  RuntimePaths({
    required Map<String, String> environment,
    List<String> gettextLocaleDirs = systemGettextLocaleDirs,
  }) : environment = Map.unmodifiable(environment),
       gettextLocaleDirs = List.unmodifiable(gettextLocaleDirs);

  /// Where the system's gettext catalogues are installed, in the order the
  /// C library searches them for a domain that is not bound to a directory
  /// of its own: the catalogues the packages install themselves, then
  /// Ubuntu's language packs, which hold the translations of the packages in
  /// its main archive (Ubuntu's glibc adds that directory after the default
  /// one; it does not exist elsewhere).
  static const List<String> systemGettextLocaleDirs = <String>[
    '/usr/share/locale',
    '/usr/share/locale-langpack',
  ];

  final Map<String, String> environment;

  /// The directories searched for `LOCALE/LC_MESSAGES/DOMAIN.mo`, in this
  /// order. [systemGettextLocaleDirs] unless a test gives its own.
  final List<String> gettextLocaleDirs;

  String get homeDir {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      // Fail closed instead of reading or writing another user's home.
      return '/nonexistent';
    }
    return home;
  }

  String get configHome =>
      environment['XDG_CONFIG_HOME'] ?? p.join(homeDir, '.config');

  String get dataHome =>
      environment['XDG_DATA_HOME'] ?? p.join(homeDir, '.local', 'share');

  String get stateHome =>
      environment['XDG_STATE_HOME'] ?? p.join(homeDir, '.local', 'state');

  String get cacheHome =>
      environment['XDG_CACHE_HOME'] ?? p.join(homeDir, '.cache');

  String get wallpaperDirectory =>
      denialEnvironmentValue(environment, 'DENIAL_WALLPAPER_DIR') ??
      p.join(homeDir, 'Pictures', 'Wallpapers');

  List<String> get dataDirs {
    return (environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':')
        .where((dir) => dir.isNotEmpty)
        .toList(growable: false);
  }

  String get powerdControlSocketPath =>
      denialEnvironmentValue(environment, 'DENIAL_POWERD_CONTROL_SOCKET') ??
      '/run/denia-powerd/control.sock';

  Future<File> layoutFile() async {
    final dir = Directory(p.join(configHome, 'denia-home'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'layout.json'));
  }

  Future<File> wallpaperStateFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'wallpaper'));
  }

  Future<File> applicationRecentsFile() async {
    final dir = Directory(p.join(stateHome, 'denial'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'application-recents.json'));
  }

  List<Directory> desktopApplicationDirs() {
    final paths = <String>[
      p.join(dataHome, 'applications'),
      for (final dir in dataDirs) p.join(dir, 'applications'),
      p.join(
        homeDir,
        '.local',
        'share',
        'flatpak',
        'exports',
        'share',
        'applications',
      ),
      '/var/lib/flatpak/exports/share/applications',
    ];

    return uniquePaths(paths).map(Directory.new).toList(growable: false);
  }

  List<String> iconRoots() {
    return uniquePaths([
      dataHome,
      ...dataDirs,
      p.join(homeDir, '.local', 'share', 'flatpak', 'exports', 'share'),
      '/var/lib/flatpak/exports/share',
    ]);
  }

  static List<String> uniquePaths(Iterable<String> paths) {
    final seen = <String>{};
    final unique = <String>[];
    for (final path in paths) {
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      unique.add(path);
    }
    return unique;
  }
}
