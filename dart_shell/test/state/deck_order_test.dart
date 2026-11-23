import 'package:denial_desktop/src/state/deck_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Windows 1 and 3 are Firefox, 2 a terminal, 4 Files, 5 a second
  // terminal; 9 has no app id.
  const apps = {1: 'firefox', 2: 'term', 3: 'firefox', 4: 'files', 5: 'term'};
  String? appOf(int id) => apps[id];

  group('Recents keeps the windows of one app together', () {
    test('apps in the order of their most recent window', () {
      // Least to most recent: Firefox, terminal, Firefox again, Files.
      expect(groupedByApp([1, 2, 3, 4], appOf), [2, 1, 3, 4]);
    });

    test('the most recent window stays last', () {
      expect(groupedByApp([3, 4, 1, 2, 5], appOf).last, 5);
      expect(groupedByApp([3, 4, 1, 2, 5], appOf), [4, 3, 1, 2, 5]);
    });

    test('next to the window in front is another of its app', () {
      final order = groupedByApp([1, 4, 2, 3], appOf);
      expect(order, [4, 2, 1, 3]);
      expect(order[order.length - 2], 1);
    });

    test('an order already grouped stays as it is', () {
      expect(groupedByApp([4, 2, 5, 1, 3], appOf), [4, 2, 5, 1, 3]);
    });

    test('windows without an app stay apart', () {
      expect(groupedByApp([9, 1, 8, 3], appOf), [9, 8, 1, 3]);
    });

    test('nothing to group', () {
      expect(groupedByApp(const [], appOf), isEmpty);
      expect(groupedByApp([2], appOf), [2]);
    });
  });

  test("an app's windows, in order", () {
    expect(windowsOfAppOf(3, [4, 2, 1, 3], appOf), [1, 3]);
    expect(windowsOfAppOf(4, [4, 2, 1, 3], appOf), [4]);
    expect(windowsOfAppOf(9, [9, 4], appOf), [9]);
  });
}
