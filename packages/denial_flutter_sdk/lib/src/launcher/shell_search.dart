import 'package:flutter/foundation.dart';

import '../../launcher.dart' show LauncherApplication;

/// One open window as the shell's search sees it.
@immutable
class ShellSearchWindow {
  const ShellSearchWindow({
    required this.id,
    required this.appId,
    required this.appName,
    required this.title,
    this.appSearchableText = '',
  });

  /// The shell's identity of the window; search does not interpret it.
  final int id;
  final String appId;

  /// The app's display name (from the catalog, or its id when it has none).
  final String appName;
  final String title;

  /// The app's other words, as its [LauncherApplication.searchableText]
  /// gives them: a window is found by every word its app is found by, the
  /// English name of a translated app too. Empty for an app the catalog
  /// does not have.
  final String appSearchableText;

  @override
  bool operator ==(Object other) =>
      other is ShellSearchWindow &&
      other.id == id &&
      other.appId == appId &&
      other.appName == appName &&
      other.title == title &&
      other.appSearchableText == appSearchableText;

  @override
  int get hashCode => Object.hash(id, appId, appName, title, appSearchableText);

  @override
  String toString() => 'ShellSearchWindow($id, $appId, "$title")';
}

/// What Enter acts on: a window to go to, or an app to start.
sealed class ShellSearchHit {
  const ShellSearchHit();
}

final class ShellSearchWindowHit extends ShellSearchHit {
  const ShellSearchWindowHit(this.window);
  final ShellSearchWindow window;
}

final class ShellSearchApplicationHit extends ShellSearchHit {
  const ShellSearchApplicationHit(this.application);
  final LauncherApplication application;
}

/// The shell's search over open windows and launchable apps, shared by the
/// desktop overview, the global search overlay and the tablet's app drawer.
@immutable
class ShellSearchResults {
  const ShellSearchResults({
    required this.query,
    required this.windows,
    required this.applications,
  });

  /// The query as typed.
  final String query;

  /// Matching open windows, best first; every window when the query is empty,
  /// in the order given.
  final List<ShellSearchWindow> windows;

  /// Matching apps, best first; none when the query is empty.
  final List<LauncherApplication> applications;

  bool get isEmpty => windows.isEmpty && applications.isEmpty;

  /// What Enter acts on: the best window, else the best app. With an empty
  /// query there is none, so Enter does not jump to an arbitrary window.
  ShellSearchHit? get first {
    if (normalizeShellSearchText(query).isEmpty) {
      return null;
    }
    if (windows.isNotEmpty) {
      return ShellSearchWindowHit(windows.first);
    }
    if (applications.isNotEmpty) {
      return ShellSearchApplicationHit(applications.first);
    }
    return null;
  }
}

/// Searches [windows] (most recent first) and [applications] for [query].
///
/// Every word of the query must match a word of the candidate. A match at
/// the start of the name ranks above one at the start of a later word, which
/// ranks above one inside a word, and matches in the name above matches in
/// other text (the app ids, categories, keywords and untranslated names of
/// apps and of the apps windows belong to). A
/// query typed in the other keyboard layout (Russian ЙЦУКЕН for Latin QWERTY
/// and back, the tablet's two layouts) also finds its candidates, below the
/// direct matches. Ties keep the windows' order and sort apps by name.
ShellSearchResults searchShell(
  String query, {
  required List<ShellSearchWindow> windows,
  required List<LauncherApplication> applications,
  int maxApplications = 8,
}) {
  final words = _words(normalizeShellSearchText(query));
  if (words.isEmpty) {
    return ShellSearchResults(
      query: query,
      windows: List.unmodifiable(windows),
      applications: const [],
    );
  }
  final swapped = _words(
    normalizeShellSearchText(swapShellSearchKeyboardLayout(query)),
  );
  int? rank(List<String> primary, List<String> secondary) {
    final direct = _rank(words, primary, secondary);
    final other = swapped.isEmpty || _sameWords(swapped, words)
        ? null
        : _rank(swapped, primary, secondary);
    if (direct == null) {
      return other == null ? null : other + _swappedLayoutPenalty;
    }
    return other == null
        ? direct
        : (direct <= other + _swappedLayoutPenalty
              ? direct
              : other + _swappedLayoutPenalty);
  }

  final rankedWindows = <(int, int, ShellSearchWindow)>[];
  for (final (index, window) in windows.indexed) {
    final score = rank(
      [
        normalizeShellSearchText(window.appName),
        normalizeShellSearchText(window.title),
      ],
      [
        normalizeShellSearchText(window.appId),
        normalizeShellSearchText(window.appSearchableText),
      ],
    );
    if (score != null) {
      rankedWindows.add((score, index, window));
    }
  }
  rankedWindows.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
  });

  final rankedApps = <(int, String, LauncherApplication)>[];
  for (final app in applications) {
    final name = normalizeShellSearchText(app.name);
    final score = rank([name], [normalizeShellSearchText(app.searchableText)]);
    if (score != null) {
      rankedApps.add((score, name, app));
    }
  }
  rankedApps.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
  });

  return ShellSearchResults(
    query: query,
    windows: List.unmodifiable(rankedWindows.map((entry) => entry.$3)),
    applications: List.unmodifiable(
      rankedApps
          .take(maxApplications < 0 ? 0 : maxApplications)
          .map((entry) => entry.$3),
    ),
  );
}

/// Lower case, `ё` as `е`, runs of white space as one space, trimmed.
String normalizeShellSearchText(String text) => text
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// [text] as it would have come out in the other of the tablet's two
/// keyboard layouts: Latin QWERTY letters become the Russian ЙЦУКЕН letters
/// on the same keys and back. Other characters stay.
String swapShellSearchKeyboardLayout(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    final swapped = _latinToCyrillic[lower] ?? _cyrillicToLatin[lower];
    if (swapped == null) {
      out.write(char);
    } else {
      out.write(char == lower ? swapped : swapped.toUpperCase());
    }
  }
  return out.toString();
}

const int _swappedLayoutPenalty = 6;

const String _latinKeys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`";
const String _cyrillicKeys = 'йцукенгшщзхъфывапролджэячсмитьбюё';

final Map<String, String> _latinToCyrillic = {
  for (var i = 0; i < _latinKeys.length; i++) _latinKeys[i]: _cyrillicKeys[i],
};

final Map<String, String> _cyrillicToLatin = {
  for (var i = 0; i < _cyrillicKeys.length; i++)
    _cyrillicKeys[i]: _latinKeys[i],
};

List<String> _words(String normalized) => normalized.isEmpty
    ? const []
    : normalized.split(' ').where((word) => word.isNotEmpty).toList();

bool _sameWords(List<String> a, List<String> b) =>
    a.length == b.length && a.indexed.every((entry) => b[entry.$1] == entry.$2);

/// The worst of the query words' best matches, or null when a word matches
/// nowhere. Lower is better.
int? _rank(List<String> words, List<String> primary, List<String> secondary) {
  var worst = 0;
  for (final word in words) {
    int? best;
    for (final text in primary) {
      final score = _matchScore(word, text);
      if (score != null && (best == null || score < best)) {
        best = score;
      }
    }
    for (final text in secondary) {
      final score = _matchScore(word, text);
      if (score != null && (best == null || score + 3 < best)) {
        best = score + 3;
      }
    }
    if (best == null) {
      return null;
    }
    if (best > worst) {
      worst = best;
    }
  }
  return worst;
}

/// 0: the whole text; 1: its start; 2: the start of a later word;
/// 3: inside a word.
int? _matchScore(String word, String text) {
  if (text.isEmpty) {
    return null;
  }
  if (text == word) {
    return 0;
  }
  if (text.startsWith(word)) {
    return 1;
  }
  var index = text.indexOf(word);
  if (index < 0) {
    return null;
  }
  while (index >= 0) {
    if (_isWordStart(text, index)) {
      return 2;
    }
    index = text.indexOf(word, index + 1);
  }
  return 3;
}

bool _isWordStart(String text, int index) {
  if (index == 0) {
    return true;
  }
  final before = text.codeUnitAt(index - 1);
  // A space, or punctuation that separates words in titles and app ids.
  return before == 0x20 || // space
      before == 0x2d || // -
      before == 0x5f || // _
      before == 0x2e || // .
      before == 0x2f || // /
      before == 0x3a || // :
      before == 0x28 || // (
      before == 0x5b || // [
      before == 0x2014 || // em dash
      before == 0x2013; // en dash
}
