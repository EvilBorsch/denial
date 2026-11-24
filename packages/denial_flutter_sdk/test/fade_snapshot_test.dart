import 'dart:ui' as ui;

import 'package:denial_flutter_sdk/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Home's content fades as Recents opens over it and closes again: the
/// image a fade draws is what the raster thread renders on the fade's
/// first frame, a visible stall for a full-screen grid.
void main() {
  late int rendered;
  setUp(() {
    rendered = 0;
    ui.Image.onCreate = (_) => rendered += 1;
  });
  tearDown(() => ui.Image.onCreate = null);

  Future<void> pumpHome(
    WidgetTester tester,
    ValueNotifier<double> opacity,
    ValueNotifier<Color> grid, {
    required bool retain,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: FadeSnapshot(
            opacity: Animation.fromValueListenable(opacity),
            retain: retain,
            child: ValueListenableBuilder<Color>(
              valueListenable: grid,
              builder: (context, color, _) => ColoredBox(color: color),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> fade(WidgetTester tester, ValueNotifier<double> opacity, double to) async {
    opacity.value = 0.5;
    await tester.pump();
    opacity.value = 0.3;
    await tester.pump();
    opacity.value = to;
    await tester.pump();
  }

  testWidgets('home that holds still is rendered once for every Recents round trip', (
    tester,
  ) async {
    final opacity = ValueNotifier(1.0);
    final grid = ValueNotifier(const Color(0xff2040ff));
    await pumpHome(tester, opacity, grid, retain: true);
    expect(rendered, 0);

    // Recents opens from home, closes, and opens again.
    await fade(tester, opacity, 0);
    await fade(tester, opacity, 1);
    await fade(tester, opacity, 0);
    await fade(tester, opacity, 1);
    expect(rendered, 1);
  });

  testWidgets('home that changed while hidden fades in as it is now', (tester) async {
    final opacity = ValueNotifier(1.0);
    final grid = ValueNotifier(const Color(0xff2040ff));
    await pumpHome(tester, opacity, grid, retain: true);
    await fade(tester, opacity, 0);
    expect(rendered, 1);

    // An app's icon is hidden as the app flies home behind Recents.
    grid.value = const Color(0xffff4020);
    await tester.pump();
    expect(rendered, 1);
    await fade(tester, opacity, 1);
    expect(rendered, 2);
    await fade(tester, opacity, 0);
    expect(rendered, 2);
  });

  testWidgets('home that changed while shown is rendered again once nothing moves', (
    tester,
  ) async {
    final opacity = ValueNotifier(1.0);
    final grid = ValueNotifier(const Color(0xff2040ff));
    await pumpHome(tester, opacity, grid, retain: true);
    // The first image is rendered ahead too, once home is idle.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(rendered, 1);

    // A page swipe: home changes while it is shown.
    grid.value = const Color(0xff20ff40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(rendered, 1, reason: 'not while it may still move');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(rendered, 2);

    // Recents then opens without rendering anything.
    await fade(tester, opacity, 0);
    expect(rendered, 2);
  });

  testWidgets('without retain every fade renders its own image and lets it go', (
    tester,
  ) async {
    var released = 0;
    ui.Image.onDispose = (_) => released += 1;
    addTearDown(() => ui.Image.onDispose = null);
    final opacity = ValueNotifier(1.0);
    final grid = ValueNotifier(const Color(0xff2040ff));
    await pumpHome(tester, opacity, grid, retain: false);

    await fade(tester, opacity, 1);
    expect((rendered, released), (1, 1));
    await fade(tester, opacity, 0);
    expect((rendered, released), (2, 2));
    await tester.pump(const Duration(seconds: 2));
    expect(rendered, 2);
  });

  testWidgets('a fade shows the child at its opacity and the live child at 1', (
    tester,
  ) async {
    final opacity = ValueNotifier(1.0);
    final grid = ValueNotifier(const Color(0xff2040ff));
    await pumpHome(tester, opacity, grid, retain: true);
    expect(find.byType(ColoredBox), paints..rect(color: const Color(0xff2040ff)));
    opacity.value = 0.5;
    await tester.pump();
    expect(find.byType(FadeSnapshot), paints..drawImageRect());
    opacity.value = 0;
    await tester.pump();
    expect(find.byType(FadeSnapshot), paintsNothing);
  });
}
