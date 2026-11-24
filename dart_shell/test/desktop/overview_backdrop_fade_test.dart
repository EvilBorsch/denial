import 'package:denial_flutter_sdk/effects.dart' show ShellBackdropBlur;
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The overview's backdrop: the desktop blurred under a scrim, faded in as the
// overview opens. Offstage: the test engine cannot paint Denial's filters,
// and these tests read the widget structure the engine receives.
Widget overviewBackdrop(Animation<double> motion, {bool grouped = false}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        child: ShellTheme(
          data: const ShellThemeData(),
          child: BackdropGroup(
            child: ShellBackdropBlur(
              opacity: motion,
              grouped: grouped,
              blendMode: BlendMode.srcOver,
              child: const ColoredBox(color: Color(0x66000000)),
            ),
          ),
        ),
      ),
    );

Finder get filter => find.byType(BackdropFilter, skipOffstage: false);

Finder fadesAbove(Finder of) => find.ancestor(
  of: of,
  matching: find.byWidgetPredicate(
    (widget) => widget is FadeTransition || widget is Opacity,
    skipOffstage: false,
  ),
);

Finder paintsInside(Finder of) => find.descendant(
  of: of,
  matching: find.byType(CustomPaint, skipOffstage: false),
);

void main() {
  testWidgets(
    'the overview backdrop fades inside its filter layer, not above it',
    (tester) async {
      final motion = AnimationController(vsync: const TestVSync(), value: 0.4);
      addTearDown(motion.dispose);
      await tester.pumpWidget(overviewBackdrop(motion));
      // No opacity above the filter: an opacity changing every frame of
      // the fade would make the engine filter the unchanged desktop again.
      expect(filter, findsOneWidget);
      expect(fadesAbove(filter), findsNothing);
      // The fade is drawn over the filtered backdrop, inside its layer.
      expect(paintsInside(filter), findsOneWidget);
    },
  );

  testWidgets('a grouped backdrop has no layer of its own and fades above it', (
    tester,
  ) async {
    final motion = AnimationController(vsync: const TestVSync(), value: 0.4);
    addTearDown(motion.dispose);
    await tester.pumpWidget(overviewBackdrop(motion, grouped: true));
    expect(fadesAbove(filter), findsOneWidget);
    expect(paintsInside(filter), findsNothing);
  });
}
