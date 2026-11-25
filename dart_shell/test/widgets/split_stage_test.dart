import 'package:denial_desktop/src/features/mobile/mobile_split_stage.dart';
import 'package:denial_desktop/src/launcher/widgets/launcher_icon.dart';
import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/state/split_view.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

void main() {
  final other = phoneWindow(3, 'org.gnome.Console');

  (DenialWindow, DenialWindow) pairAt(double share) => splitWindows(
    (1, 'org.gnome.Nautilus'),
    (2, 'org.gnome.TextEditor'),
    share: share,
    texture: false,
  );

  Future<void> show(
    WidgetTester tester,
    MobileShellHarness shell, {
    ShellThemeData theme = const ShellThemeData(
      transparencyMode: ShellTransparencyMode.off,
    ),
  }) async {
    final state = shell.container.read(referenceShellProvider);
    final pair = state.primarySplit!;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: shell.container,
        child: DenialLocalizationScope(
          locale: const Locale('en'),
          child: MediaQuery(
            data: const MediaQueryData(size: tabletView),
            child: ShellTheme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: MobileSplitStage(
                  pair: pair,
                  windows: [pair.left, pair.right],
                  foreground: state.foregroundObjectId,
                  opacity: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<MobileShellHarness> stage(
    WidgetTester tester, {
    double share = 0.5,
    ShellThemeData theme = const ShellThemeData(
      transparencyMode: ShellTransparencyMode.off,
    ),
  }) async {
    tester.view
      ..physicalSize = tabletView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = MobileShellHarness();
    addTearDown(shell.dispose);
    final (left, right) = pairAt(share);
    await shell.publish(tester, [other, left, right]);
    shell.controller.focusWindow(right);
    await tester.pump();
    await show(tester, shell, theme: theme);
    shell.bridge.requests.clear();
    return shell;
  }

  /// A slow drag from [from] by [by], in steps, as a finger moves.
  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    final gesture = await tester.startGesture(from);
    const steps = 20;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(by / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pump();
  }

  Finder covers() => find.byType(LauncherIcon);

  testWidgets('the divider covers the apps while it moves and settles at a '
      'third', (tester) async {
    final shell = await stage(tester);
    expect(covers(), findsNothing);
    // The divider is in the middle of the gap deniald left.
    final gesture = await tester.startGesture(const Offset(679, 500));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(covers(), findsNWidgets(2));
    await gesture.up();
    await tester.pump();
    expect(shell.bridge.requests, ['split 1 2 left 0.667']);
    // The covers stay until the apps have their new widths.
    expect(covers(), findsNWidgets(2));
    final (left, right) = pairAt(2 / 3);
    await shell.publish(tester, [other, left, right]);
    await show(tester, shell);
    expect(covers(), findsNothing);
    await shell.finish(tester);
  });

  testWidgets('the divider dragged to an edge takes that app out', (
    tester,
  ) async {
    final shell = await stage(tester);
    await drag(tester, const Offset(679, 500), const Offset(-640, 0));
    await tester.pump(const Duration(milliseconds: 400));
    // The editor fills the screen; the files app leaves it.
    expect(shell.bridge.requests, ['leave split 2', 'minimize 1', 'focus 2']);
    await shell.finish(tester);
  });

  testWidgets('a handle pulled down takes its app out in front', (
    tester,
  ) async {
    final shell = await stage(tester);
    // The files app's handle, at the top middle of its half.
    await drag(tester, const Offset(337, 62), const Offset(0, 320));
    expect(shell.bridge.requests, ['leave split 1', 'minimize 2', 'focus 1']);
    await shell.finish(tester);
  });

  testWidgets('a handle dropped over the other half swaps the apps', (
    tester,
  ) async {
    final shell = await stage(tester, share: 1 / 3);
    final pair = shell.container.read(referenceShellProvider).primarySplit!;
    expect(pair.share, closeTo(1 / 3, 1e-9));
    await drag(tester, const Offset(224, 62), const Offset(600, 30));
    expect(shell.bridge.requests, ['split 1 2 right 0.667']);
    await shell.finish(tester);
  });

  testWidgets('an app lifted by its handle is square while windows are, and '
      'rounded as windows when they are', (tester) async {
    Future<BorderRadiusGeometry> liftedCorners(ShellThemeData theme) async {
      final shell = await stage(tester, theme: theme);
      final gesture = await tester.startGesture(const Offset(337, 62));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final corners = tester
          .widget<ClipRRect>(find.byType(ClipRRect))
          .borderRadius;
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await shell.finish(tester);
      return corners;
    }

    // The shell's own roundness, as on the tablet, does not round windows.
    expect(
      await liftedCorners(
        const ShellThemeData(
          transparencyMode: ShellTransparencyMode.off,
          cornerRadiusScale: 1.6,
        ),
      ),
      BorderRadius.zero,
    );
    expect(
      await liftedCorners(
        const ShellThemeData(
          transparencyMode: ShellTransparencyMode.off,
          cornerRadiusScale: 1.6,
          roundedWindowFrame: true,
          windowCornerRadiusScale: 0.5,
        ),
      ),
      BorderRadius.circular(9),
    );
  });

  testWidgets('square apps meet at a thin divider; rounded ones keep the '
      'wide gap', (tester) async {
    double divider() =>
        tester.getSize(find.byKey(const ValueKey('divider bar'))).width;
    double grab() =>
        tester.getSize(find.byKey(const ValueKey('divider zone'))).width;

    var shell = await stage(tester);
    expect(divider(), SplitViewMetrics.squareGap);
    expect(grab(), SplitViewMetrics.dividerZone);
    await shell.finish(tester);

    shell = await stage(
      tester,
      theme: const ShellThemeData(
        transparencyMode: ShellTransparencyMode.off,
        roundedWindowFrame: true,
      ),
    );
    expect(divider(), SplitViewMetrics.gap);
    expect(grab(), SplitViewMetrics.dividerZone);
    await shell.finish(tester);
  });

  testWidgets('a short handle drag goes back', (tester) async {
    final shell = await stage(tester);
    await drag(tester, const Offset(1018, 62), const Offset(-80, 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(shell.bridge.requests, isEmpty);
    expect(splitViewShares, contains(0.5));
    await shell.finish(tester);
  });
}
