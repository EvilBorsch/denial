/// Desktop-entry metadata shared with Denial's application catalog.
///
/// [exec] is desktop-entry data, not a shell command for plugins to execute.
/// Application launching remains a native runtime operation.
class const DesktopApp({
  required final String id,
  required final String name,
  required final String exec,
  required final String desktopPath,
  required final List<String> categories,
  final List<String> keywords = const <String>[],
  final String? icon,
  final String? iconPath,
  final String? startupWmClass,

  /// The entry's own words before translation (its `Name`, `GenericName`
  /// and `Keywords`) where they differ from [name] and [keywords], so that a
  /// search in English also finds an app whose name is translated.
  final List<String> untranslatedNames = const <String>[],
}) {
  String get searchableText => <String>[
    id,
    name,
    ...categories,
    ...keywords,
    ...untranslatedNames,
  ].join(' ').toLowerCase();
}
