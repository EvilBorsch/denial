import 'dart:ui' as ui;

import 'package:denial_desktop/src/desktop/desktop_window_frame_painter.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The window part of the theme the shell builds from the settings.
ShellThemeData themeOf(Map<String, dynamic> document) {
  final appearance = ShellSettings.fromJson(document).appearance;
  return ShellThemeData(
    cornerRadiusScale: appearance.interfaceCornerRadiusScale,
    focusedWindowBorderEnabled: appearance.focusedWindowBorderEnabled,
    roundedWindowFrame: appearance.roundedWindowFrame,
    windowCornerRadiusScale: appearance.windowCornerRadiusScale,
  );
}

/// What a window's frame shows over the frame surface.
Color borderOf(
  ShellThemeData theme, {
  required bool active,
  bool pinned = false,
}) => desktopWindowBorderColor(
  pinned: pinned,
  active: active,
  theme: theme,
  inactiveColor: ShellColorScheme.dark.hairlineWindow,
);

void main() {
  const transparent = Color(0x00000000);

  test("the owner's windows are square and borderless while the shell's "
      'glass keeps its roundness', () {
    // eb19's document on the tablet: roundness 1.6, focus border off.
    final theme = themeOf(<String, dynamic>{
      'appearance': <String, dynamic>{
        'interfaceCornerRadiusScale': 1.6,
        'windowCornerRadiusScale': 1.6,
        'focusedWindowBorderEnabled': false,
      },
    });

    // Windows in every presentation: frames, windows in the overview, apps
    // sliding side by side and a lifted Split View app.
    expect(theme.windowRadius, 0);
    expect(theme.scaledWindowRadius(18), 0);
    // Cards previewing windows in recents and the overview are the shell's.
    expect(theme.windowCardRadius, closeTo(28 * 1.6, 1e-9));
    // Panels, tiles and notifications.
    expect(theme.panelRadius, closeTo(28 * 1.6, 1e-9));
    expect(theme.tileRadius, closeTo(24 * 1.6, 1e-9));
    expect(theme.notificationRadius, closeTo(18 * 1.6, 1e-9));
    // No hairline and no accent: the frame is the plain frame surface.
    expect(borderOf(theme, active: true), transparent);
    expect(borderOf(theme, active: false), transparent);
    // A pinned window keeps its mark.
    expect(
      borderOf(theme, active: false, pinned: true),
      theme.accentPalette.container,
    );
  });

  test('a new user gets square, borderless windows even with the focus '
      'border on', () {
    final theme = themeOf(<String, dynamic>{});

    expect(theme.focusedWindowBorderEnabled, isTrue);
    expect(theme.windowRadius, 0);
    expect(borderOf(theme, active: true), transparent);
  });

  test('rounded windows take their own roundness and bring the frame back', () {
    final theme = themeOf(<String, dynamic>{
      'appearance': <String, dynamic>{
        'interfaceCornerRadiusScale': 1.6,
        'roundedWindowFrame': true,
        'windowCornerRadiusScale': 0.5,
      },
    });

    expect(theme.windowRadius, 14);
    expect(theme.scaledWindowRadius(18), 9);
    expect(theme.panelRadius, closeTo(28 * 1.6, 1e-9));
    expect(borderOf(theme, active: true), theme.accent);
    expect(
      borderOf(theme, active: false),
      ShellColorScheme.dark.hairlineWindow,
    );

    // With the focus border off the focused window has the hairline too.
    final calm = theme.copyWith(focusedWindowBorderEnabled: false);
    expect(borderOf(calm, active: true), ShellColorScheme.dark.hairlineWindow);
  });

  testWidgets('a square window casts a square shadow, with none inside its '
      'corners', (tester) async {
    const window = Size(200, 120);
    const outset = DesktopWindowShadowPainter.shadowOutset;

    /// The shadow's alpha at the window's bottom-right corner pixel.
    Future<int> cornerAlpha(double radius) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..translate(outset, outset);
      DesktopWindowShadowPainter(
        radius: radius,
        shadowColor: const Color(0xff000000),
      ).paint(canvas, window);
      final picture = recorder.endRecording();
      final bytes = (await tester.runAsync(() async {
        final image = await picture.toImage(
          (window.width + 2 * outset).toInt(),
          (window.height + 2 * outset).toInt(),
        );
        return image.toByteData();
      }))!;
      final x = (outset + window.width - 1).toInt();
      final y = (outset + window.height - 1).toInt();
      final width = (window.width + 2 * outset).toInt();
      return bytes.getUint8((y * width + x) * 4 + 3);
    }

    // A rounded window leaves its corner to the shadow; a square one covers
    // it, so the shadow ends at its straight edges.
    expect(await cornerAlpha(14), greaterThan(0));
    expect(await cornerAlpha(0), 0);
  });
}
