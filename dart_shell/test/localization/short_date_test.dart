import 'package:denial_flutter_sdk/localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, Locale locale, DateTime day) =>
      tester.pumpWidget(
        DenialLocalizationScope(
          locale: locale,
          child: Builder(
            builder: (context) => Text(localizedShortDate(context, day)),
          ),
        ),
      );

  testWidgets('a short date takes its weekday and month from the catalog', (
    tester,
  ) async {
    // What cutting the full names to three characters gave.
    await show(tester, const Locale('en'), DateTime(2026, 11, 22));
    expect(find.text('Sun 22 Nov'), findsOneWidget);
    await show(tester, const Locale('en'), DateTime(2026, 9, 3));
    expect(find.text('Thu 3 Sep'), findsOneWidget);
    await show(tester, const Locale('zh'), DateTime(2026, 11, 22));
    expect(find.text('十一月22日 星期日'), findsOneWidget);
  });
}
