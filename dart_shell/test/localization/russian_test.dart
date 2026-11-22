import 'package:denial_flutter_sdk/localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a Russian system gets the Russian catalog', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru', 'RU')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    late AppLocalizations l10n;
    late String shortDate;
    late String longDate;
    await tester.pumpWidget(
      DenialLocalizationScope(
        child: Builder(
          builder: (context) {
            l10n = context.l10n;
            final day = DateTime(2026, 11, 22);
            shortDate = localizedShortDate(context, day);
            longDate = localizedLongDate(context, day);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(l10n.localeName, 'ru');

    // Russian has three plural forms; 11 to 14 take the third, 21 the first.
    String apps(int count) => l10n.homeFolderApps('Игры', count);
    expect(apps(1), 'Игры, 1 приложение');
    expect(apps(3), 'Игры, 3 приложения');
    expect(apps(5), 'Игры, 5 приложений');
    expect(apps(12), 'Игры, 12 приложений');
    expect(apps(21), 'Игры, 21 приложение');
    expect(l10n.settingsShortcutsConfigured(0), 'Нет сочетаний клавиш');
    expect(l10n.settingsShortcutsConfigured(22), '22 сочетания клавиш');

    // A date with a day takes the month in the genitive, and a short date
    // the language's own short names.
    expect(longDate, 'Воскресенье, 22 ноября');
    expect(shortDate, 'Вс, 22 нояб.');
  });
}
