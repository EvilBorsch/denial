import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Translations from the gettext catalogues installed on the system, for
/// desktop entries that name a gettext domain instead of carrying their
/// translations.
///
/// A message is looked up in `DIRECTORY/LOCALE/LC_MESSAGES/DOMAIN.mo`, for
/// each directory in the order given and, within a directory, for each name
/// of [gettextLocaleNames]; the first catalogue that has the message wins.
/// A catalogue is read once and kept for the lifetime of this object, so one
/// object serves one scan of the applications.
///
/// A catalogue that is missing, unreadable, too large, truncated or
/// malformed only means that it has no translation: [translate] never
/// throws.
class GettextCatalogs {
  GettextCatalogs({
    required Iterable<String> directories,
    required String locale,
  }) : _directories = <String>[
         for (final directory in directories)
           if (directory.isNotEmpty)
             for (final name in gettextLocaleNames(locale))
               p.join(directory, name, 'LC_MESSAGES'),
       ];

  final List<String> _directories;
  final Map<String, GettextCatalog?> _catalogs = <String, GettextCatalog?>{};

  /// The translation of [message] in [domain], or null without one.
  String? translate(String domain, String message) {
    if (message.isEmpty || _directories.isEmpty || !_isDomainName(domain)) {
      return null;
    }
    final key = utf8.encode(message);
    for (final directory in _directories) {
      try {
        final translation = _catalog(p.join(directory, '$domain.mo'))
            ?.translate(key);
        if (translation != null) {
          return translation;
        }
      } on Object {
        // GettextCatalog checks every offset it reads. Should it still fail
        // on a file nobody foresaw, the application keeps its untranslated
        // name: an exception here would drop it from the launcher.
      }
    }
    return null;
  }

  GettextCatalog? _catalog(String path) {
    if (_catalogs.containsKey(path)) {
      return _catalogs[path];
    }
    // Recorded before loading, so that a catalogue that cannot be loaded is
    // not tried again for the next application of the same domain.
    _catalogs[path] = null;
    return _catalogs[path] = GettextCatalog.load(File(path));
  }
}

/// The catalogue directory names gettext tries for [locale]
/// (`language[_TERRITORY][.codeset][@modifier]`), most specific first:
/// `ru_RU.UTF-8` gives `ru_RU`, `ru`; `sr_RS@latin` gives `sr_RS@latin`,
/// `sr@latin`, `sr_RS`, `sr`. The codeset names no directory. Empty for the
/// untranslated `C` and `POSIX` locales and for a value that is no locale
/// name.
List<String> gettextLocaleNames(String locale) {
  final parts = _localeName.firstMatch(locale.trim());
  if (parts == null) {
    return const <String>[];
  }
  final language = parts.group(1)!;
  final territory = parts.group(2);
  final modifier = parts.group(3);
  if (language == 'C' || language == 'POSIX') {
    return const <String>[];
  }
  return <String>[
    if (territory != null && modifier != null)
      '${language}_$territory@$modifier',
    if (modifier != null) '$language@$modifier',
    if (territory != null) '${language}_$territory',
    language,
  ];
}

// Both become parts of a file path and come from the environment and from
// desktop entries: nothing in them may lead out of the catalogue directory.
final RegExp _localeName = RegExp(
  r'^([A-Za-z0-9]+)(?:_([A-Za-z0-9]+))?(?:\.[A-Za-z0-9_:-]+)?(?:@([A-Za-z0-9]+))?$',
);
final RegExp _domainName = RegExp(r'^[A-Za-z0-9_+-][A-Za-z0-9._+-]*$');

bool _isDomainName(String domain) =>
    domain.length <= 255 && _domainName.hasMatch(domain);

/// One compiled gettext catalogue (a `.mo` file), read-only.
///
/// The file is a header of 32-bit words in the byte order of the machine
/// that compiled it (magic `0x950412de`, revision, number of messages N,
/// offset of the table of original strings, offset of the table of
/// translations), two tables of N `(length, offset)` pairs, and the strings
/// they point to. The original strings are sorted bytewise, which is what
/// the lookup relies on, as gettext does for a catalogue without a hash
/// table; nothing but the strings compared and the translation returned is
/// decoded.
class GettextCatalog {
  GettextCatalog._(
    this._bytes,
    this._data,
    this._endian,
    this._count,
    this._originals,
    this._translations,
  );

  /// The largest file read. The largest Russian catalogue in the language
  /// packs of Ubuntu 26.04 is 1.4 MiB, those of its applications about
  /// 0.1 MiB.
  static const int maxFileBytes = 16 * 1024 * 1024;

  static const int _headerBytes = 28;
  static const int _magic = 0x950412de;
  static const int _magicSwapped = 0xde120495;

  final Uint8List _bytes;
  final ByteData _data;
  final Endian _endian;
  final int _count;
  final int _originals;
  final int _translations;

  /// The catalogue in [file], or null if there is none to use.
  static GettextCatalog? load(File file) {
    RandomAccessFile? handle;
    try {
      // Opening anything but a regular file could block.
      if (file.statSync().type != FileSystemEntityType.file) {
        return null;
      }
      handle = file.openSync();
      final length = handle.lengthSync();
      if (length < _headerBytes || length > maxFileBytes) {
        return null;
      }
      return parse(handle.readSync(length));
    } on FileSystemException {
      return null;
    } finally {
      try {
        handle?.closeSync();
      } on FileSystemException {
        // Nothing was written; the descriptor is gone either way.
      }
    }
  }

  /// The catalogue in [bytes], or null if they are not a catalogue this
  /// class reads: another magic number or major revision, tables that do
  /// not fit in the file, or strings in an encoding other than UTF-8.
  static GettextCatalog? parse(Uint8List bytes) {
    if (bytes.length < _headerBytes) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final Endian endian;
    switch (data.getUint32(0, Endian.little)) {
      case _magic:
        endian = Endian.little;
      case _magicSwapped:
        endian = Endian.big;
      default:
        return null;
    }
    // Major revisions 0 and 1 share this layout; the minor one only adds
    // tables this class does not read.
    if (data.getUint32(4, endian) >> 16 > 1) {
      return null;
    }
    final count = data.getUint32(8, endian);
    final originals = data.getUint32(12, endian);
    final translations = data.getUint32(16, endian);
    if (!_tableFits(bytes.length, originals, count) ||
        !_tableFits(bytes.length, translations, count)) {
      return null;
    }
    final catalog = GettextCatalog._(
      bytes,
      data,
      endian,
      count,
      originals,
      translations,
    );
    return catalog._isUtf8() ? catalog : null;
  }

  static bool _tableFits(int fileBytes, int offset, int count) =>
      offset >= _headerBytes &&
      offset <= fileBytes &&
      count <= (fileBytes - offset) ~/ 8;

  /// The translation of the UTF-8 encoded [message], or null without one.
  String? translate(List<int> message) {
    if (message.isEmpty || message.contains(0)) {
      return null;
    }
    final translation = _find(message);
    if (translation == null || translation.isEmpty) {
      return null;
    }
    try {
      return utf8.decode(translation);
    } on FormatException {
      return null;
    }
  }

  /// The bytes of the translation of [message]: of its first plural form if
  /// it has several.
  Uint8List? _find(List<int> message) {
    var low = 0;
    var high = _count;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final order = _compareOriginal(middle, message);
      if (order == null) {
        return null;
      }
      if (order == 0) {
        return _string(_translations, middle);
      }
      if (order < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return null;
  }

  /// How original string [index] sorts against [message]: negative before
  /// it, zero if equal, positive after it; null if the entry points outside
  /// the file. As in C, a string ends at its first NUL: the entry of a
  /// message with plural forms is `singular NUL plural` and is found by its
  /// singular.
  int? _compareOriginal(int index, List<int> message) {
    final entry = _originals + index * 8;
    final length = _data.getUint32(entry, _endian);
    final offset = _data.getUint32(entry + 4, _endian);
    if (offset > _bytes.length || length > _bytes.length - offset) {
      return null;
    }
    for (var i = 0; ; i += 1) {
      final original = i < length ? _bytes[offset + i] : 0;
      final wanted = i < message.length ? message[i] : 0;
      if (original != wanted) {
        return original < wanted ? -1 : 1;
      }
      if (original == 0) {
        return 0;
      }
    }
  }

  /// String [index] of the table at [table], up to its first NUL; null if
  /// the entry points outside the file.
  Uint8List? _string(int table, int index) {
    final entry = table + index * 8;
    final length = _data.getUint32(entry, _endian);
    final offset = _data.getUint32(entry + 4, _endian);
    if (offset > _bytes.length || length > _bytes.length - offset) {
      return null;
    }
    var end = offset;
    while (end < offset + length && _bytes[end] != 0) {
      end += 1;
    }
    return Uint8List.sublistView(_bytes, offset, end);
  }

  /// Whether the catalogue's strings are UTF-8, as its header entry (the
  /// translation of the empty string) declares. Strings of another encoding
  /// would need converting, and their originals would not compare equal to
  /// the UTF-8 text of a desktop entry.
  bool _isUtf8() {
    final header = _find(const <int>[]);
    if (header == null) {
      return true;
    }
    final charset = _charset
        .firstMatch(latin1.decode(header))
        ?.group(1)
        ?.toLowerCase();
    return charset == null ||
        charset == 'utf-8' ||
        charset == 'utf8' ||
        charset == 'us-ascii' ||
        charset == 'ascii' ||
        // The placeholder of a template that was never filled in.
        charset == 'charset';
  }

  static final RegExp _charset = RegExp(
    r'^Content-Type:.*\bcharset=([A-Za-z0-9._:-]+)',
    caseSensitive: false,
    multiLine: true,
  );
}
