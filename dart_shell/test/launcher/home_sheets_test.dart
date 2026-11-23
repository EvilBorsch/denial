import 'package:denial_desktop/src/launcher/home_sheets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a vertical drag on home', () {
    test('down pulls search, as on iPadOS', () {
      final drag = HomeSheetDrag(drawerAllowed: true);
      expect(drag.move(4), HomeSheet.search);
      // The first movement decides; the finger may come back.
      expect(drag.move(-30), HomeSheet.search);
    });

    test('down pulls search without the drawer too', () {
      expect(HomeSheetDrag(drawerAllowed: false).move(2), HomeSheet.search);
    });

    test('up pulls the drawer', () {
      final drag = HomeSheetDrag(drawerAllowed: true);
      expect(drag.move(-3), HomeSheet.drawer);
      expect(drag.move(20), HomeSheet.drawer);
    });

    test('up moves nothing when the user turned the drawer off', () {
      final drag = HomeSheetDrag(drawerAllowed: false);
      expect(drag.move(-3), isNull);
      expect(drag.move(40), isNull);
    });

    test('waits for a movement', () {
      final drag = HomeSheetDrag(drawerAllowed: true);
      expect(drag.move(0), isNull);
      expect(drag.sheet, isNull);
      expect(drag.move(1), HomeSheet.search);
    });
  });

  group('a released sheet', () {
    bool search(double openness, double velocity) => homeSheetOpens(
      openness: openness,
      openingVelocity: velocity,
      openShare: homeSearchOpenShare,
    );

    test('search opens past a short pull', () {
      expect(search(0.2, 0), isFalse);
      expect(search(0.31, 0), isTrue);
    });

    test('a flick decides by its direction', () {
      expect(search(0.05, 700), isTrue);
      expect(search(0.95, -700), isFalse);
    });

    test('the drawer needs a longer pull', () {
      expect(
        homeSheetOpens(
          openness: 0.35,
          openingVelocity: 0,
          openShare: homeDrawerOpenShare,
        ),
        isFalse,
      );
      expect(
        homeSheetOpens(
          openness: 0.45,
          openingVelocity: 0,
          openShare: homeDrawerOpenShare,
        ),
        isTrue,
      );
    });
  });
}
