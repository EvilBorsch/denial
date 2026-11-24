import 'dart:convert';
import 'dart:io';

import 'package:denial_flutter_sdk/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: Center(child: SizedBox.square(dimension: 54, child: child)),
  ),
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('warm-app-icons-'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a warmed icon draws on its first frame; another waits', (
    tester,
  ) async {
    final warm = File('${dir.path}/warm.png')..writeAsBytesSync(_png);
    final cold = File('${dir.path}/cold.png')..writeAsBytesSync(_png);

    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            warmAppIcons(context, [warm.path, warm.path]);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // The file read and the decode run outside the fake clock; their
    // callbacks run as the test pumps.
    for (var i = 0; i < 20; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    await tester.pumpWidget(_host(DeferredAppIcon(iconPath: warm.path)));
    expect(find.byType(AppIconImage), findsOneWidget);

    await tester.pumpWidget(_host(DeferredAppIcon(iconPath: cold.path)));
    expect(find.byType(AppIconImage), findsNothing);
  });
}
