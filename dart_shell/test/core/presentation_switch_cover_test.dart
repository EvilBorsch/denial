import 'package:denial_desktop/src/core/presentation_switch_cover.dart';
import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/state/reference_shell_profile.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

// Switching between the tablet and desktop presentations replaces the whole
// scene, and deniald resizes the windows only once the new one shows. The
// last picture of the presentation left stays in front until the windows
// the new one shows are laid out for it and have drawn their new sizes, then
// dissolves.

/// A window as deniald publishes it: laid out at [geometry], for the phone
/// when [onPhone], its client having drawn [drawn] (the geometry's size when
/// absent).
DenialWindow window(
  int id, {
  Rect geometry = const Rect.fromLTWH(0, 48, 1357, 912),
  Size? drawn,
  bool onPhone = true,
  bool minimized = false,
}) {
  final content = drawn ?? geometry.size;
  return DenialWindow(
    objectId: id,
    objectKind: 'xdg_toplevel',
    surfaceId: id + 100,
    windowId: id + 200,
    textureId: 0,
    title: 'app $id',
    appId: 'org.example.App$id',
    width: 0,
    height: 0,
    surfaceX: geometry.left,
    surfaceY: geometry.top,
    surfaceWidth: content.width,
    surfaceHeight: content.height,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: content.width,
    textureSourceHeight: content.height,
    geometryX: geometry.left,
    geometryY: geometry.top,
    geometryWidth: geometry.width,
    geometryHeight: geometry.height,
    contentX: geometry.left,
    contentY: geometry.top,
    contentWidth: content.width,
    contentHeight: content.height,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    minimized: minimized,
    onPhone: onPhone,
  );
}

const _desktopScreen = Rect.fromLTWH(0, 40, 1357, 920);
final _screen = Offset.zero & tabletView;

void main() {
  group('the windows a presentation shows', () {
    test('are laid out for it and drawn at their sizes', () {
      const mobile = ReferenceShellProfile.mobile;
      const desktop = ReferenceShellProfile.desktop;
      expect(presentationSwitchWindowsSettled([window(1)], mobile), isTrue);
      // Still laid out for the desktop.
      expect(
        presentationSwitchWindowsSettled([window(1, onPhone: false)], mobile),
        isFalse,
      );
      // Laid out for the tablet, its last buffer still the desktop's size.
      expect(
        presentationSwitchWindowsSettled([
          window(1, drawn: const Size(1357, 920)),
        ], mobile),
        isFalse,
      );
      expect(
        presentationSwitchWindowsSettled([
          window(1, geometry: _desktopScreen, onPhone: false),
        ], desktop),
        isTrue,
      );
      // A pixel of rounding is no new size.
      expect(
        presentationSwitchWindowsSettled([
          window(
            1,
            geometry: _desktopScreen,
            drawn: const Size(1358, 919),
            onPhone: false,
          ),
        ], desktop),
        isTrue,
      );
      expect(presentationSwitchWindowsSettled(const [], desktop), isTrue);
    });

    testWidgets('on the desktop: those on the screen, not beside it', (
      tester,
    ) async {
      final shell = MobileShellHarness();
      addTearDown(shell.dispose);
      final current = window(1, geometry: _desktopScreen, onPhone: false);
      final beside = window(
        2,
        geometry: _desktopScreen.translate(1365, 0),
        onPhone: false,
      );
      final minimized = window(3, onPhone: false, minimized: true);
      await shell.publish(tester, [current, beside, minimized]);
      final shown = presentationSwitchShownWindows(
        shell.container.read(referenceShellProvider),
        ReferenceShellProfile.desktop,
        _screen,
      );
      expect([for (final window in shown) window.objectId], [1]);
      await shell.finish(tester);
    });

    testWidgets('on the tablet: the app in front', (tester) async {
      final shell = MobileShellHarness();
      addTearDown(shell.dispose);
      final files = window(1);
      final editor = window(2);
      await shell.publish(tester, [files, editor]);
      shell.controller.focusWindow(editor);
      await tester.pump();
      final shown = presentationSwitchShownWindows(
        shell.container.read(referenceShellProvider),
        ReferenceShellProfile.mobile,
        _screen,
      );
      expect([for (final window in shown) window.objectId], [2]);
      await shell.finish(tester);
    });
  });

  group('the cover', () {
    Widget host(
      MobileShellHarness shell,
      ReferenceShellProfile presentation, {
      bool enabled = true,
    }) => UncontrolledProviderScope(
      container: shell.container,
      child: MediaQuery(
        data: const MediaQueryData(size: tabletView),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: PresentationSwitchCover(
            presentation: presentation,
            enabled: enabled,
            child: ColoredBox(
              color: presentation == ReferenceShellProfile.mobile
                  ? const Color(0xff204060)
                  : const Color(0xff604020),
              child: Text('$presentation'),
            ),
          ),
        ),
      ),
    );

    Finder cover() => find.byType(RawImage);

    double coverOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find.ancestor(of: cover(), matching: find.byType(FadeTransition)),
        )
        .opacity
        .value;

    Future<MobileShellHarness> tabletWith(
      WidgetTester tester,
      DenialWindow front,
    ) async {
      final shell = MobileShellHarness();
      addTearDown(shell.dispose);
      await shell.publish(tester, [front]);
      shell.controller.focusWindow(front);
      await tester.pump();
      return shell;
    }

    testWidgets('holds the last picture until the app in front is laid out '
        'for the tablet and has drawn, then dissolves', (tester) async {
      // On the desktop: the app fills the screen below the top bar.
      final shell = await tabletWith(
        tester,
        window(1, geometry: _desktopScreen, onPhone: false),
      );
      await tester.pumpWidget(host(shell, ReferenceShellProfile.desktop));
      expect(cover(), findsNothing);

      await tester.pumpWidget(host(shell, ReferenceShellProfile.mobile));
      // The new scene is built and live underneath the desktop's picture.
      expect(cover(), findsOneWidget);
      expect(find.text('${ReferenceShellProfile.mobile}'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(coverOpacity(tester), 1.0);

      // deniald lays the app out for the tablet; it has not drawn yet.
      await shell.publish(tester, [
        window(1, drawn: _desktopScreen.size),
      ]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(coverOpacity(tester), 1.0);

      // It draws its new size: the picture dissolves.
      await shell.publish(tester, [window(1)]);
      await tester.pump(presentationSwitchDissolve ~/ 2);
      expect(coverOpacity(tester), inExclusiveRange(0.0, 1.0));
      await tester.pump(presentationSwitchDissolve);
      await tester.pump();
      expect(cover(), findsNothing);
      await shell.finish(tester);
    });

    testWidgets('dissolves after the hold limit when a window never takes '
        'its size', (tester) async {
      // A fixed-size app, such as a calculator, keeps its size anywhere.
      final shell = await tabletWith(
        tester,
        window(1, drawn: const Size(400, 600), onPhone: false),
      );
      await tester.pumpWidget(host(shell, ReferenceShellProfile.desktop));
      await tester.pumpWidget(host(shell, ReferenceShellProfile.mobile));
      await shell.publish(tester, [window(1, drawn: const Size(400, 600))]);
      await tester.pump(
        presentationSwitchHoldLimit - const Duration(milliseconds: 50),
      );
      expect(coverOpacity(tester), 1.0);
      // The limit passes: the dissolve starts with the next frame.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(presentationSwitchDissolve ~/ 2);
      expect(coverOpacity(tester), inExclusiveRange(0.0, 1.0));
      await tester.pump(presentationSwitchDissolve);
      await tester.pump();
      expect(cover(), findsNothing);
      await shell.finish(tester);
    });

    testWidgets('covers with the frame deniald froze, draws nothing again '
        'for it, and gives it back after the dissolve', (tester) async {
      final shell = await tabletWith(
        tester,
        window(1, geometry: _desktopScreen, onPhone: false),
      );
      final released = <int>[];
      var drawn = 0;
      Widget frozen(ReferenceShellProfile presentation, {int? texture}) =>
          UncontrolledProviderScope(
            container: shell.container,
            child: MediaQuery(
              data: const MediaQueryData(size: tabletView),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: PresentationSwitchCover(
                  presentation: presentation,
                  coverTexture: texture,
                  onDrawn: () => drawn += 1,
                  onReleased: released.add,
                  child: Text('$presentation'),
                ),
              ),
            ),
          );
      await tester.pumpWidget(frozen(ReferenceShellProfile.desktop));
      expect(drawn, 1);
      await tester.pumpWidget(
        frozen(ReferenceShellProfile.mobile, texture: 42),
      );
      final cover = tester.widget<Texture>(find.byType(Texture));
      expect(cover.textureId, 42);
      expect(cover.freeze, isTrue);
      expect(find.byType(RawImage), findsNothing);
      // Over the new scene, which is live underneath.
      expect(find.text('${ReferenceShellProfile.mobile}'), findsOneWidget);

      await shell.publish(tester, [window(1)]);
      await tester.pump(presentationSwitchDissolve ~/ 2);
      expect(
        tester
            .widget<FadeTransition>(
              find.ancestor(
                of: find.byType(Texture),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        inExclusiveRange(0.0, 1.0),
      );
      expect(released, isEmpty);
      await tester.pump(presentationSwitchDissolve);
      await tester.pump();
      expect(find.byType(Texture), findsNothing);
      expect(released, [42]);
      expect(drawn, 1);
      await shell.finish(tester);
    });

    testWidgets('keeps frames coming while a switch waits for its cover', (
      tester,
    ) async {
      final shell = await tabletWith(tester, window(1));
      Widget waiting(bool waiting) => UncontrolledProviderScope(
        container: shell.container,
        child: MediaQuery(
          data: const MediaQueryData(size: tabletView),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PresentationSwitchCover(
              presentation: ReferenceShellProfile.mobile,
              waiting: waiting,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(waiting(false));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(waiting(true));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(waiting(false));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await shell.finish(tester);
    });

    testWidgets('does not cover a start, an unchanged presentation or a '
        'switch together with a monitor', (tester) async {
      final shell = await tabletWith(tester, window(1));
      await tester.pumpWidget(host(shell, ReferenceShellProfile.mobile));
      expect(cover(), findsNothing);
      await tester.pumpWidget(host(shell, ReferenceShellProfile.mobile));
      expect(cover(), findsNothing);
      await tester.pumpWidget(
        host(shell, ReferenceShellProfile.desktop, enabled: false),
      );
      expect(cover(), findsNothing);
      await shell.finish(tester);
    });

    testWidgets('takes input in the new scene while it shows', (tester) async {
      final shell = await tabletWith(
        tester,
        window(1, geometry: _desktopScreen, onPhone: false),
      );
      var taps = 0;
      Widget tappable(ReferenceShellProfile presentation) =>
          UncontrolledProviderScope(
            container: shell.container,
            child: MediaQuery(
              data: const MediaQueryData(size: tabletView),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: PresentationSwitchCover(
                  presentation: presentation,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps += 1,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
      await tester.pumpWidget(tappable(ReferenceShellProfile.desktop));
      await tester.pumpWidget(tappable(ReferenceShellProfile.mobile));
      expect(cover(), findsOneWidget);
      await tester.tapAt(const Offset(600, 500));
      expect(taps, 1);
      await tester.pump(presentationSwitchHoldLimit + presentationSwitchDissolve);
      await tester.pump(const Duration(milliseconds: 20));
      await shell.finish(tester);
    });
  });
}
