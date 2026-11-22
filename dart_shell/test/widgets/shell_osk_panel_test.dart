import 'package:denial_desktop/src/widgets/osk/shell_osk_panel.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The software keyboard's letter pages: English as it always was, and
// ЙЦУКЕН beside it when the keyboard layouts or the shell's language are
// Russian. The panel is driven with touches as on the tablet.
void main() {
  group('the pages offered', () {
    test('English alone without Russian anywhere', () {
      for (final configuration in [
        null,
        _configuration(['us']),
        _configuration(['us', 'de'], active: 1),
      ]) {
        final languages = ShellOskLanguages.of(
          configuration,
          shellLanguage: 'en',
        );
        expect(languages, ShellOskLanguages.englishOnly);
        expect(languages.switches, isFalse);
        expect(languages.typingLayouts, isEmpty);
      }
    });

    test('Russian for a Russian shell, the keyboard\'s own page', () {
      final languages = ShellOskLanguages.of(
        _configuration(['us']),
        shellLanguage: 'ru',
      );
      expect(languages.offered, [
        ShellOskLanguage.english,
        ShellOskLanguage.russian,
      ]);
      expect(languages.layouts[ShellOskLanguage.english], [0]);
      expect(languages.layouts[ShellOskLanguage.russian], isEmpty);
      expect(languages.activeLanguage, ShellOskLanguage.english);
      expect(languages.typingLayouts, ['us', 'ru']);
      // Before the configuration is read.
      expect(
        ShellOskLanguages.of(null, shellLanguage: 'ru').activeLanguage,
        isNull,
      );
    });

    test('a Russian layout in any place shares the active layout', () {
      var languages = ShellOskLanguages.of(
        _configuration(['us', 'ru'], active: 1),
        shellLanguage: 'en',
      );
      expect(languages.switches, isTrue);
      expect(languages.layouts[ShellOskLanguage.english], [0]);
      expect(languages.layouts[ShellOskLanguage.russian], [1]);
      expect(languages.activeLanguage, ShellOskLanguage.russian);

      languages = ShellOskLanguages.of(
        _configuration(['ru', 'de', 'us']),
        shellLanguage: 'en',
      );
      expect(languages.layouts[ShellOskLanguage.english], [1, 2]);
      expect(languages.layouts[ShellOskLanguage.russian], [0]);
      expect(languages.activeLanguage, ShellOskLanguage.russian);
    });
  });

  testWidgets('English alone looks exactly as before', (tester) async {
    final typing = <List<String>>[];
    await _pump(tester, onTypingLayouts: typing.add);
    expect(typing, [<String>[]]);

    _expectRows(tester, ['qwertyuiop', 'asdfghjkl', 'zxcvbnm']);
    expect(find.text('RU'), findsNothing);
    expect(find.text('EN'), findsNothing);
    // Shift and Backspace one and a half letters wide, the space bar 46
    // of the bottom row's 100 parts.
    final letter = _keyRect(tester, find.text('z')).width;
    expect(
      _keyRect(tester, find.byIcon(Icons.keyboard_arrow_up_rounded)).width,
      moreOrLessEquals(letter * 1.5, epsilon: 0.01),
    );
    final space = _keyRect(tester, find.byIcon(Icons.space_bar_rounded));
    final enter = _keyRect(tester, find.byIcon(Icons.keyboard_return_rounded));
    expect(space.width / enter.width, moreOrLessEquals(46 / 17, epsilon: 1e-6));
    expect(_bottomRowKeys(tester), 5);
  });

  testWidgets('the language key turns QWERTY into ЙЦУКЕН and back', (
    tester,
  ) async {
    final selected = <int>[];
    final keys = <ShellOskKeyIntent>[];
    final typing = <List<String>>[];
    await _pump(
      tester,
      languages: ShellOskLanguages.of(
        _configuration(['us']),
        shellLanguage: 'ru',
      ),
      onSelectLayout: selected.add,
      onKey: keys.add,
      onTypingLayouts: typing.add,
    );
    expect(typing, [
      ['us', 'ru'],
    ]);
    _expectRows(tester, ['qwertyuiop', 'asdfghjkl', 'zxcvbnm']);
    expect(_bottomRowKeys(tester), 6);

    await _tap(tester, find.text('RU'));
    _expectRows(tester, ['йцукенгшщзх', 'фывапролджэ', 'ячсмитьбю']);
    expect(find.text('RU'), findsNothing);
    expect(find.text('EN'), findsOneWidget);
    // Every letter of the page in its place, eleven columns.
    expect(
      _keyRect(tester, find.byIcon(Icons.keyboard_arrow_up_rounded)).width,
      moreOrLessEquals(_keyRect(tester, find.text('я')).width, epsilon: 0.01),
    );
    expect(
      _keyRect(tester, find.text('я')).left,
      moreOrLessEquals(_keyRect(tester, find.text('ц')).left, epsilon: 0.01),
    );
    // No configured Russian layout to select: the page is the keyboard's.
    expect(selected, isEmpty);
    // The language key types nothing.
    expect(keys, isEmpty);

    // The numbers are shared; their letters key returns to ЙЦУКЕН.
    await _tap(tester, find.text('?123'));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('АБВ'), findsOneWidget);
    await _tap(tester, find.text('АБВ'));
    expect(find.text('й'), findsOneWidget);

    await _tap(tester, find.text('EN'));
    _expectRows(tester, ['qwertyuiop', 'asdfghjkl', 'zxcvbnm']);
    expect(selected, [0]);
    await _tap(tester, find.text('?123'));
    expect(find.text('ABC'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('ЙЦУКЕН types Cyrillic, capitals with Shift, ё and ъ held', (
    tester,
  ) async {
    final keys = <ShellOskKeyIntent>[];
    await _pump(
      tester,
      languages: ShellOskLanguages.of(
        _configuration(['us', 'ru']),
        shellLanguage: 'en',
      ),
      onKey: keys.add,
    );
    await _tap(tester, find.text('RU'));
    String typed() => [
      for (final key in keys)
        if (key.action == ShellOskKeyAction.text ||
            key.action == ShellOskKeyAction.space)
          key.text,
    ].join();

    for (final row in ['йцукенгшщзх', 'фывапролджэ', 'ячсмитьбю']) {
      for (final letter in row.split('')) {
        await _tap(tester, find.text(letter));
      }
    }
    expect(typed(), 'йцукенгшщзхфывапролджэячсмитьбю');

    keys.clear();
    await _tap(tester, find.byIcon(Icons.keyboard_arrow_up_rounded));
    expect(find.text('Ж'), findsOneWidget);
    await _tap(tester, find.text('Ж'));
    // Shift lasts one letter.
    await _tap(tester, find.text('и'));
    expect(typed(), 'Жи');

    keys.clear();
    await _hold(tester, find.text('е'));
    await _hold(tester, find.text('ь'));
    await _tap(tester, find.byIcon(Icons.keyboard_arrow_up_rounded));
    await _hold(tester, find.text('Е'));
    expect(typed(), 'ёъЁ');

    // Punctuation of the shared row and the space bar.
    keys.clear();
    await _tap(tester, find.text(','));
    await _tap(tester, find.byIcon(Icons.space_bar_rounded));
    await _tap(tester, find.text('.'));
    expect(typed(), ', .');
    await _finish(tester);
  });

  testWidgets('Ctrl with a Russian letter names the QWERTY key in its place', (
    tester,
  ) async {
    final keys = <ShellOskKeyIntent>[];
    await _pump(
      tester,
      languages: ShellOskLanguages.of(
        _configuration(['us', 'ru'], active: 1),
        shellLanguage: 'en',
      ),
      onKey: keys.add,
    );
    expect(find.text('й'), findsOneWidget);
    for (final (letter, key) in [
      ('с', 'c'),
      ('х', 'bracketleft'),
      ('б', 'comma'),
    ]) {
      // A long press of the numbers key arms Ctrl for the next key.
      await _hold(tester, find.text('?123'));
      await _tap(tester, find.text(letter));
      expect(keys.last.action, ShellOskKeyAction.key);
      expect(keys.last.key, key);
      expect(keys.last.ctrl, isTrue);
    }
    await _finish(tester);
  });

  testWidgets('the page follows the active layout both ways', (tester) async {
    final selected = <int>[];
    var languages = ShellOskLanguages.of(
      _configuration(['us', 'ru']),
      shellLanguage: 'en',
    );
    Future<void> pump() =>
        _pump(tester, languages: languages, onSelectLayout: selected.add);
    await pump();
    expect(find.text('q'), findsOneWidget);

    // The language key selects the Russian layout.
    await _tap(tester, find.text('RU'));
    expect(selected, [1]);
    expect(find.text('й'), findsOneWidget);
    // The compositor confirms it.
    languages = ShellOskLanguages.of(
      _configuration(['us', 'ru'], active: 1),
      shellLanguage: 'en',
    );
    await pump();
    expect(find.text('й'), findsOneWidget);

    // Super+Space on the keyboard cover turns the page back.
    languages = ShellOskLanguages.of(
      _configuration(['us', 'ru']),
      shellLanguage: 'en',
    );
    await pump();
    expect(find.text('q'), findsOneWidget);
    await _tap(tester, find.text('RU'));
    expect(selected, [1, 1]);
    await _finish(tester);
  });

  testWidgets('a page of the keyboard\'s own stays over editor changes', (
    tester,
  ) async {
    final typing = <List<String>>[];
    var languages = ShellOskLanguages.of(
      _configuration(['us']),
      shellLanguage: 'ru',
    );
    Future<void> pump() =>
        _pump(tester, languages: languages, onTypingLayouts: typing.add);
    await pump();
    await _tap(tester, find.text('RU'));
    expect(find.text('й'), findsOneWidget);
    // The same configuration read again changes nothing.
    languages = ShellOskLanguages.of(
      _configuration(['us']),
      shellLanguage: 'ru',
    );
    await pump();
    expect(find.text('й'), findsOneWidget);
    expect(typing, [
      ['us', 'ru'],
    ]);

    // The shell turns English: Russian goes, and with it the keymap layout.
    languages = ShellOskLanguages.of(
      _configuration(['us']),
      shellLanguage: 'en',
    );
    await pump();
    expect(find.text('q'), findsOneWidget);
    expect(find.text('RU'), findsNothing);
    expect(typing, [
      ['us', 'ru'],
      <String>[],
    ]);
    await _finish(tester);
  });
}

DenialKeyboardConfiguration _configuration(
  List<String> layouts, {
  int active = 0,
}) => DenialKeyboardConfiguration(
  revision: 1,
  layouts: [for (final layout in layouts) DenialKeyboardLayout(layout: layout)],
  options: const [],
  repeatDelayMs: 600,
  repeatRateHz: 25,
  activeLayout: active,
);

const _view = Size(1000, 1400);

Future<void> _pump(
  WidgetTester tester, {
  ShellOskLanguages languages = ShellOskLanguages.englishOnly,
  ValueChanged<int>? onSelectLayout,
  ValueChanged<List<String>>? onTypingLayouts,
  ValueChanged<ShellOskKeyIntent>? onKey,
}) async {
  tester.view.physicalSize = _view;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DenialLocalizationScope(
      locale: const Locale('en'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: _view.width,
            height: 320,
            child: ShellOskPanel(
              key: const ValueKey('panel'),
              languages: languages,
              onSelectLayout: onSelectLayout,
              onTypingLayouts: onTypingLayouts,
              onKey: onKey,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tapAt(_keyRect(tester, finder).center);
  await tester.pump();
}

/// Holds a key past a long press.
Future<void> _hold(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(_keyRect(tester, finder).center);
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.up();
  await tester.pump();
}

/// Lets the lit keys go dark.
Future<void> _finish(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 200));

/// The key cap around [finder]'s label or icon.
Rect _keyRect(WidgetTester tester, Finder finder) => tester.getRect(
  find.ancestor(of: finder, matching: find.byType(DecoratedBox)).first,
);

/// Each string's letters are one row, left to right, rows top to bottom.
void _expectRows(WidgetTester tester, List<String> rows) {
  double? lastTop;
  for (final row in rows) {
    final rects = [
      for (final letter in row.split('')) _keyRect(tester, find.text(letter)),
    ];
    for (final rect in rects) {
      expect(rect.top, rects.first.top, reason: row);
    }
    for (var index = 1; index < rects.length; index++) {
      expect(
        rects[index].left,
        greaterThan(rects[index - 1].left),
        reason: row,
      );
    }
    if (lastTop != null) expect(rects.first.top, greaterThan(lastTop));
    lastTop = rects.first.top;
  }
}

/// The keys in the space bar's row.
int _bottomRowKeys(WidgetTester tester) {
  final top = _keyRect(tester, find.byIcon(Icons.space_bar_rounded)).top;
  return find
      .descendant(
        of: find.byKey(const ValueKey('panel')),
        matching: find.byType(DecoratedBox),
      )
      .evaluate()
      .where((element) {
        final box = element.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero).dy == top;
      })
      .length;
}
