import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:denial_flutter_sdk/src/launcher/models/desktop_app.dart';
import 'package:denial_flutter_sdk/src/launcher/repositories/desktop_apps_repository.dart';
import 'package:denial_flutter_sdk/src/launcher/repositories/gettext_catalog.dart';
import 'package:denial_flutter_sdk/src/launcher/runtime_paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A `.mo` file as msgfmt writes it without a hash table: the header, the
/// table of originals, the table of translations, then the strings, each
/// followed by a NUL, the originals sorted bytewise.
Uint8List _catalog(
  Map<String, String> messages, {
  Endian endian = Endian.little,
  String? charset = 'UTF-8',
  int revision = 0,
  Encoding encoding = utf8,
}) {
  final entries =
      <(List<int>, List<int>)>[
        if (charset != null)
          (
            const <int>[],
            ascii.encode(
              'Project-Id-Version: test\n'
              'Content-Type: text/plain; charset=$charset\n',
            ),
          ),
        for (final MapEntry(:key, :value) in messages.entries)
          (encoding.encode(key), encoding.encode(value)),
      ]..sort((a, b) {
        for (var i = 0; i < a.$1.length && i < b.$1.length; i += 1) {
          if (a.$1[i] != b.$1[i]) {
            return a.$1[i] - b.$1[i];
          }
        }
        return a.$1.length - b.$1.length;
      });
  final count = entries.length;
  final originals = 28;
  final translations = originals + count * 8;
  final strings = BytesBuilder();
  final header = ByteData(translations + count * 8)
    ..setUint32(0, 0x950412de, endian)
    ..setUint32(4, revision, endian)
    ..setUint32(8, count, endian)
    ..setUint32(12, originals, endian)
    ..setUint32(16, translations, endian)
    ..setUint32(20, 0, endian)
    ..setUint32(24, translations + count * 8, endian);
  void place(int entry, List<int> string) {
    header
      ..setUint32(entry, string.length, endian)
      ..setUint32(entry + 4, header.lengthInBytes + strings.length, endian);
    strings
      ..add(string)
      ..addByte(0);
  }

  for (var i = 0; i < count; i += 1) {
    place(originals + i * 8, entries[i].$1);
  }
  for (var i = 0; i < count; i += 1) {
    place(translations + i * 8, entries[i].$2);
  }
  return Uint8List.fromList(<int>[
    ...header.buffer.asUint8List(),
    ...strings.takeBytes(),
  ]);
}

String _name(Endian endian) =>
    endian == Endian.little ? 'little-endian' : 'big-endian';

String? _translate(Uint8List bytes, String message) =>
    GettextCatalog.parse(bytes)?.translate(utf8.encode(message));

void main() {
  group('a gettext catalogue', () {
    const messages = <String, String>{
      'Files': 'Файлы',
      'Calculator': 'Калькулятор',
      'Text Editor': 'Текстовый редактор',
      'folder;manager;': 'папка;менеджер;',
      'Zebra': 'Зебра',
      'action\u0004Files': 'Действие',
    };

    for (final endian in <Endian>[Endian.little, Endian.big]) {
      test('gives the translations, ${_name(endian)}', () {
        final bytes = _catalog(messages, endian: endian);
        expect(_translate(bytes, 'Files'), 'Файлы');
        expect(_translate(bytes, 'Calculator'), 'Калькулятор');
        expect(_translate(bytes, 'Text Editor'), 'Текстовый редактор');
        expect(_translate(bytes, 'folder;manager;'), 'папка;менеджер;');
        expect(_translate(bytes, 'Zebra'), 'Зебра');
        expect(_translate(bytes, 'Disks'), isNull);
        expect(_translate(bytes, 'File'), isNull);
        expect(_translate(bytes, 'Filesystem'), isNull);
      });
    }

    test('does not give its header for the empty string', () {
      expect(_translate(_catalog(messages), ''), isNull);
    });

    test('finds a message with plural forms by its singular', () {
      final bytes = _catalog(const <String, String>{
        'File\u0000Files': 'Файл\u0000Файла\u0000Файлов',
        'Disks': 'Диски',
      });
      expect(_translate(bytes, 'File'), 'Файл');
      expect(_translate(bytes, 'Files'), isNull);
      expect(_translate(bytes, 'Disks'), 'Диски');
    });

    test('has no translation for an empty or untranslatable entry', () {
      final bytes = _catalog(const <String, String>{'Files': ''});
      expect(_translate(bytes, 'Files'), isNull);
    });

    test('reads revision 1.1 and no later major revision', () {
      expect(
        _translate(_catalog(messages, revision: 0x00010001), 'Files'),
        'Файлы',
      );
      expect(GettextCatalog.parse(_catalog(messages, revision: 2 << 16)), null);
    });

    test('is not read if it is not UTF-8', () {
      expect(
        GettextCatalog.parse(
          _catalog(
            const <String, String>{'Cafe': 'Café'},
            charset: 'ISO-8859-1',
            encoding: latin1,
          ),
        ),
        isNull,
      );
      expect(
        _translate(_catalog(messages, charset: 'utf-8'), 'Files'),
        'Файлы',
      );
      expect(_translate(_catalog(messages, charset: null), 'Files'), 'Файлы');
    });

    test('has no translation where the bytes are not UTF-8', () {
      final bytes = _catalog(
        const <String, String>{'Cafe': 'Café', 'Files': 'Files!'},
        charset: null,
        encoding: latin1,
      );
      expect(_translate(bytes, 'Cafe'), isNull);
      expect(_translate(bytes, 'Files'), 'Files!');
    });

    test('is not a catalogue with another magic number or no header', () {
      final bytes = _catalog(messages);
      expect(GettextCatalog.parse(Uint8List(0)), isNull);
      expect(GettextCatalog.parse(Uint8List(64)), isNull);
      expect(GettextCatalog.parse(Uint8List.sublistView(bytes, 0, 27)), isNull);
      expect(
        GettextCatalog.parse(Uint8List.fromList(bytes)..[0] = 0x00),
        isNull,
      );
    });

    for (final endian in <Endian>[Endian.little, Endian.big]) {
      test('cut short anywhere never throws, ${_name(endian)}', () {
        final bytes = _catalog(messages, endian: endian);
        for (var length = 0; length < bytes.length; length += 1) {
          final cut = Uint8List.fromList(bytes.sublist(0, length));
          for (final MapEntry(:key, :value) in messages.entries) {
            if (key.contains('\u0004')) {
              continue;
            }
            expect(
              _translate(cut, key),
              anyOf(isNull, value),
              reason: '$length of ${bytes.length} bytes, $key',
            );
          }
        }
      });
    }

    test('with any one word overwritten never throws', () {
      final bytes = _catalog(messages);
      final words = ByteData.sublistView(bytes);
      final tablesEnd = words.getUint32(24, Endian.little);
      for (var offset = 0; offset < tablesEnd; offset += 4) {
        for (final value in <int>[0, 1, 27, bytes.length, 0x7fffffff, ~0]) {
          final damaged = Uint8List.fromList(bytes);
          ByteData.sublistView(damaged)
              .setUint32(offset, value & 0xffffffff, Endian.little);
          for (final key in <String>['Files', 'Calculator', 'Zebra', 'None']) {
            expect(
              _translate(damaged, key),
              anyOf(isNull, isA<String>()),
              reason: 'word at $offset set to $value, $key',
            );
          }
        }
      }
    });

    group('in a file', () {
      late Directory root;
      setUp(() => root = Directory.systemTemp.createTempSync('gettext-test-'));
      tearDown(() => root.deleteSync(recursive: true));

      test('is loaded', () {
        final file = File(p.join(root.path, 'nautilus.mo'))
          ..writeAsBytesSync(_catalog(messages));
        expect(
          GettextCatalog.load(file)?.translate(utf8.encode('Files')),
          'Файлы',
        );
      });

      test('is nothing if missing, a directory or too short', () {
        expect(GettextCatalog.load(File(p.join(root.path, 'no.mo'))), isNull);
        Directory(p.join(root.path, 'dir.mo')).createSync();
        expect(GettextCatalog.load(File(p.join(root.path, 'dir.mo'))), isNull);
        final short = File(p.join(root.path, 'short.mo'))
          ..writeAsBytesSync(const <int>[0xde, 0x12, 0x04, 0x95]);
        expect(GettextCatalog.load(short), isNull);
      });

      test('is not read beyond the size limit', () {
        final file = File(p.join(root.path, 'huge.mo'))
          ..writeAsBytesSync(_catalog(messages));
        expect(GettextCatalog.load(file), isNotNull);
        // The same valid catalogue, followed by a hole to just over the limit.
        file.openSync(mode: FileMode.append)
          ..truncateSync(GettextCatalog.maxFileBytes + 1)
          ..closeSync();
        expect(GettextCatalog.load(file), isNull);
      });
    });
  });

  test('gettext locale names', () {
    expect(gettextLocaleNames('ru_RU.UTF-8'), <String>['ru_RU', 'ru']);
    expect(gettextLocaleNames('ru_RU'), <String>['ru_RU', 'ru']);
    expect(gettextLocaleNames('ru'), <String>['ru']);
    expect(gettextLocaleNames('sr_RS.UTF-8@latin'), <String>[
      'sr_RS@latin',
      'sr@latin',
      'sr_RS',
      'sr',
    ]);
    expect(gettextLocaleNames('ca@valencia'), <String>['ca@valencia', 'ca']);
    expect(gettextLocaleNames(''), isEmpty);
    expect(gettextLocaleNames('C'), isEmpty);
    expect(gettextLocaleNames('C.UTF-8'), isEmpty);
    expect(gettextLocaleNames('POSIX'), isEmpty);
    expect(gettextLocaleNames('../../etc'), isEmpty);
    expect(gettextLocaleNames('ru_../x'), isEmpty);
    expect(gettextLocaleNames('ru_RU@a/b'), isEmpty);
    expect(gettextLocaleNames('ru_RU.UTF-8/../..'), isEmpty);
    expect(gettextLocaleNames('ru RU'), isEmpty);
  });

  group('the catalogues of a scan', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('gettext-test-'));
    tearDown(() => root.deleteSync(recursive: true));

    File mo(String directory, String locale, String domain) =>
        File(p.join(root.path, directory, locale, 'LC_MESSAGES', '$domain.mo'))
          ..createSync(recursive: true);

    GettextCatalogs catalogs({String locale = 'ru_RU.UTF-8'}) =>
        GettextCatalogs(
          directories: <String>[
            p.join(root.path, 'locale'),
            p.join(root.path, 'langpack'),
          ],
          locale: locale,
        );

    test('read each catalogue once', () {
      final file = mo('langpack', 'ru', 'nautilus')
        ..writeAsBytesSync(
          _catalog(const <String, String>{
            'Files': 'Файлы',
            'Trash': 'Корзина',
          }),
        );
      final scan = catalogs();
      expect(scan.translate('nautilus', 'Files'), 'Файлы');
      file.deleteSync();
      expect(scan.translate('nautilus', 'Trash'), 'Корзина');
      expect(catalogs().translate('nautilus', 'Trash'), isNull);
    });

    test('look for a missing catalogue once', () {
      final scan = catalogs();
      expect(scan.translate('nautilus', 'Files'), isNull);
      mo(
        'langpack',
        'ru',
        'nautilus',
      ).writeAsBytesSync(_catalog(const <String, String>{'Files': 'Файлы'}));
      expect(scan.translate('nautilus', 'Files'), isNull);
      expect(catalogs().translate('nautilus', 'Files'), 'Файлы');
    });

    test('take a domain only as a file name', () {
      File(
        p.join(root.path, 'outside.mo'),
      ).writeAsBytesSync(_catalog(const <String, String>{'Files': 'Снаружи'}));
      Directory(p.join(root.path, 'langpack', 'ru', 'LC_MESSAGES'))
          .createSync(recursive: true);
      final scan = catalogs();
      expect(scan.translate('../../../outside', 'Files'), isNull);
      expect(scan.translate(p.join(root.path, 'outside'), 'Files'), isNull);
      expect(scan.translate('', 'Files'), isNull);
      expect(scan.translate('..', 'Files'), isNull);
    });

    test('translate nothing in the C locale', () {
      mo(
        'langpack',
        'C',
        'nautilus',
      ).writeAsBytesSync(_catalog(const <String, String>{'Files': 'Файлы'}));
      expect(catalogs(locale: 'C').translate('nautilus', 'Files'), isNull);
      expect(catalogs(locale: '').translate('nautilus', 'Files'), isNull);
    });
  });

  group('the launcher names an application', () {
    late Directory root;
    late Directory applications;

    setUp(() {
      root = Directory.systemTemp.createTempSync('launcher-gettext-test-');
      applications = Directory(p.join(root.path, 'share', 'applications'))
        ..createSync(recursive: true);
    });
    tearDown(() => root.deleteSync(recursive: true));

    void desktop(String id, List<String> lines) {
      File(p.join(applications.path, '$id.desktop')).writeAsStringSync(
        <String>[
          '[Desktop Entry]',
          'Type=Application',
          'Exec=$id',
          ...lines,
          '',
          '[Desktop Action new-window]',
          'Name=New Window',
          '',
        ].join('\n'),
      );
    }

    File mo(String directory, String locale, String domain) =>
        File(p.join(root.path, directory, locale, 'LC_MESSAGES', '$domain.mo'))
          ..createSync(recursive: true);

    void translations(
      String directory,
      String locale,
      String domain,
      Map<String, String> messages,
    ) => mo(directory, locale, domain).writeAsBytesSync(_catalog(messages));

    DesktopAppsRepository repository({String? lang = 'ru_RU.UTF-8'}) =>
        DesktopAppsRepository(
          paths: RuntimePaths(
            environment: <String, String>{
              'HOME': p.join(root.path, 'home'),
              'XDG_DATA_DIRS': p.join(root.path, 'share'),
              'LANG': ?lang,
            },
            gettextLocaleDirs: <String>[
              p.join(root.path, 'locale'),
              p.join(root.path, 'langpack'),
            ],
          ),
        );

    Future<DesktopApp> app(String id, {String? lang = 'ru_RU.UTF-8'}) async {
      final apps = await repository(lang: lang).loadApplications();
      return apps.singleWhere((app) => app.id == '$id.desktop');
    }

    const nautilus = <String>[
      'Name=Files',
      'Keywords=folder;manager;explore;',
      'X-Ubuntu-Gettext-Domain=nautilus',
    ];

    test('in the language of the session, from the language pack', () async {
      desktop('org.gnome.Nautilus', nautilus);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
        'folder;manager;explore;': 'папка;менеджер;обзор;',
      });
      final files = await app('org.gnome.Nautilus');
      expect(files.name, 'Файлы');
      expect(files.keywords, <String>['папка', 'менеджер', 'обзор']);
      final byId = await repository().loadApplication('org.gnome.Nautilus');
      expect(byId?.name, 'Файлы');
    });

    test('and keeps its English words for search', () async {
      desktop('org.gnome.Nautilus', <String>[
        ...nautilus,
        'GenericName=File Manager',
      ]);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
        'folder;manager;explore;': 'папка;менеджер;обзор;',
      });
      final files = await app('org.gnome.Nautilus');
      expect(files.name, 'Файлы');
      expect(files.untranslatedNames, <String>[
        'Files',
        'File Manager',
        'folder',
        'manager',
        'explore',
      ]);
      expect(files.searchableText, contains('files'));
      expect(files.searchableText, contains('папка'));
      // In English nothing is repeated.
      final english = await app('org.gnome.Nautilus', lang: 'en_US.UTF-8');
      expect(english.untranslatedNames, <String>['File Manager']);
    });

    test('by the catalogue of the territory before the language', () async {
      desktop('org.gnome.Nautilus', nautilus);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
        'folder;manager;explore;': 'папка;менеджер;обзор;',
      });
      translations('langpack', 'ru_RU', 'nautilus', const <String, String>{
        'Files': 'Файлы России',
      });
      final files = await app('org.gnome.Nautilus');
      expect(files.name, 'Файлы России');
      // What the territory's catalogue lacks comes from the language's.
      expect(files.keywords, <String>['папка', 'менеджер', 'обзор']);
    });

    test('by the package catalogue before the language pack', () async {
      desktop('org.gnome.Nautilus', nautilus);
      translations('langpack', 'ru_RU', 'nautilus', const <String, String>{
        'Files': 'Из языкового пакета',
        'folder;manager;explore;': 'языковой;пакет;',
      });
      translations('locale', 'ru', 'nautilus', const <String, String>{
        'Files': 'Из пакета',
      });
      final files = await app('org.gnome.Nautilus');
      expect(files.name, 'Из пакета');
      // What the package's catalogue lacks comes from the language pack.
      expect(files.keywords, <String>['языковой', 'пакет']);
    });

    test('from the package catalogue without a language pack', () async {
      desktop('org.gnome.Nautilus', nautilus);
      translations('locale', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
      });
      expect((await app('org.gnome.Nautilus')).name, 'Файлы');
    });

    test('from where the C library looks, unless told otherwise', () {
      expect(RuntimePaths(environment: const {}).gettextLocaleDirs, <String>[
        '/usr/share/locale',
        '/usr/share/locale-langpack',
      ]);
    });

    test('by its own Name[ru] before any catalogue', () async {
      desktop('org.gnome.Nautilus', <String>[
        ...nautilus,
        'Name[ru]=Проводник',
        'Keywords[ru_RU]=свои;слова;',
      ]);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
        'folder;manager;explore;': 'папка;менеджер;обзор;',
      });
      final files = await app('org.gnome.Nautilus');
      expect(files.name, 'Проводник');
      expect(files.keywords, <String>['свои', 'слова']);
    });

    test('in English without a catalogue', () async {
      desktop('org.gnome.Nautilus', nautilus);
      final files = await app('org.gnome.Nautilus');
      expect(files.name, 'Files');
      expect(files.keywords, <String>['folder', 'manager', 'explore']);
    });

    test('in English if the catalogue lacks the name', () async {
      desktop('org.gnome.Nautilus', nautilus);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Trash': 'Корзина',
      });
      expect((await app('org.gnome.Nautilus')).name, 'Files');
    });

    test('in English if the catalogue is damaged, and keeps it', () async {
      desktop('org.gnome.Nautilus', nautilus);
      desktop('org.gnome.Calculator', const <String>[
        'Name=Calculator',
        'X-Ubuntu-Gettext-Domain=gnome-calculator',
      ]);
      desktop('org.gnome.TextEditor', const <String>[
        'Name=Text Editor',
        'X-Ubuntu-Gettext-Domain=gnome-text-editor',
      ]);
      desktop('org.gnome.clocks', const <String>[
        'Name=Clocks',
        'X-Ubuntu-Gettext-Domain=gnome-clocks',
      ]);
      desktop('org.gnome.DiskUtility', const <String>[
        'Name=Disks',
        'X-Ubuntu-Gettext-Domain=gnome-disk-utility',
      ]);
      final good = _catalog(const <String, String>{
        'Files': 'Файлы',
        'Calculator': 'Калькулятор',
        'Text Editor': 'Текстовый редактор',
        'Clocks': 'Часы',
        'Disks': 'Диски',
      });
      // Not a catalogue at all.
      mo(
        'langpack',
        'ru',
        'nautilus',
      ).writeAsStringSync('msgid "Files"\nmsgstr "Файлы"\n');
      // Cut in the middle of the translation of its only message.
      final calculator = _catalog(const <String, String>{
        'Calculator': 'Калькулятор',
      });
      mo(
        'langpack',
        'ru',
        'gnome-calculator',
      ).writeAsBytesSync(calculator.sublist(0, calculator.length - 5));
      // Tables that point far outside the file.
      final wild = Uint8List.fromList(good);
      ByteData.sublistView(wild)
        ..setUint32(8, 0x7fffffff, Endian.little)
        ..setUint32(12, 0xfffffff0, Endian.little);
      mo('langpack', 'ru', 'gnome-text-editor').writeAsBytesSync(wild);
      // Empty, and a directory where the file should be.
      mo('langpack', 'ru', 'gnome-clocks');
      Directory(
        p.join(
          root.path,
          'langpack',
          'ru',
          'LC_MESSAGES',
          'gnome-disk-utility.mo',
        ),
      ).createSync();

      final apps = await repository().loadApplications();
      final names = <String, String>{
        for (final app in apps)
          if (app.desktopPath.startsWith(root.path)) app.id: app.name,
      };
      expect(names, <String, String>{
        'org.gnome.Nautilus.desktop': 'Files',
        'org.gnome.Calculator.desktop': 'Calculator',
        'org.gnome.TextEditor.desktop': 'Text Editor',
        'org.gnome.clocks.desktop': 'Clocks',
        'org.gnome.DiskUtility.desktop': 'Disks',
      });
    });

    test('in English if it names no domain', () async {
      desktop('org.gnome.Nautilus', const <String>['Name=Files']);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
      });
      translations(
        'langpack',
        'ru',
        'org.gnome.Nautilus',
        const <String, String>{'Files': 'Файлы'},
      );
      expect((await app('org.gnome.Nautilus')).name, 'Files');
    });

    test('in English if its domain is no catalogue name', () async {
      desktop('org.gnome.Nautilus', const <String>[
        'Name=Files',
        'X-Ubuntu-Gettext-Domain=../../../outside',
      ]);
      File(
        p.join(root.path, 'outside.mo'),
      ).writeAsBytesSync(_catalog(const <String, String>{'Files': 'Снаружи'}));
      Directory(p.join(root.path, 'langpack', 'ru', 'LC_MESSAGES'))
          .createSync(recursive: true);
      expect((await app('org.gnome.Nautilus')).name, 'Files');
    });

    test('in English in an English or unset locale', () async {
      desktop('org.gnome.Nautilus', nautilus);
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
      });
      expect((await app('org.gnome.Nautilus', lang: 'C.UTF-8')).name, 'Files');
      expect(
        (await app('org.gnome.Nautilus', lang: 'en_US.UTF-8')).name,
        'Files',
      );
      expect((await app('org.gnome.Nautilus', lang: null)).name, 'Files');
    });

    test('by GNOME\'s domain key, Ubuntu\'s first', () async {
      desktop('org.gnome.Calculator', const <String>[
        'Name=Calculator',
        'X-GNOME-Gettext-Domain=gnome-calculator',
      ]);
      desktop('org.gnome.Nautilus', const <String>[
        'Name=Files',
        'X-GNOME-Gettext-Domain=upstream',
        'X-Ubuntu-Gettext-Domain=nautilus',
      ]);
      translations('langpack', 'ru', 'gnome-calculator', const <String, String>{
        'Calculator': 'Калькулятор',
      });
      translations('langpack', 'ru', 'nautilus', const <String, String>{
        'Files': 'Файлы',
      });
      translations('langpack', 'ru', 'upstream', const <String, String>{
        'Files': 'Не тот домен',
      });
      expect((await app('org.gnome.Calculator')).name, 'Калькулятор');
      expect((await app('org.gnome.Nautilus')).name, 'Файлы');
    });

    test('and sorts the list by the names shown', () async {
      desktop('a', const <String>['Name=Zebra', 'X-Ubuntu-Gettext-Domain=zoo']);
      desktop('b', const <String>['Name=Yak', 'X-Ubuntu-Gettext-Domain=zoo']);
      translations('langpack', 'ru', 'zoo', const <String, String>{
        'Zebra': 'Аист',
      });
      final apps = await repository().loadApplications();
      expect(
        <String>[
          for (final app in apps)
            if (app.desktopPath.startsWith(root.path)) app.name,
        ],
        <String>['Yak', 'Аист'],
      );
    });
  });
}
