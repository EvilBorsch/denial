import 'package:denial_desktop/src/desktop/desktop_panel_hover_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const delay = Duration(milliseconds: 220);

  testWidgets('a panel the pointer opened closes when the pointer leaves it', (
    tester,
  ) async {
    var closes = 0;
    final controller = DesktopPanelHoverController(onClose: () => closes++);
    addTearDown(controller.dispose);

    controller.beginOpening(byHover: true);
    expect(controller.dismissesOnHoverExit, isTrue);
    // Leaving the edge trigger while the panel still enters waits for it.
    controller.scheduleClose();
    await tester.pump(delay * 2);
    expect(closes, 0);
    controller.openingCompleted();
    await tester.pump(delay);
    expect(closes, 1);
  });

  testWidgets(
    'a panel opened by a key or a gesture stays when the pointer leaves it',
    (tester) async {
      var closes = 0;
      final controller = DesktopPanelHoverController(onClose: () => closes++);
      addTearDown(controller.dispose);

      // Four fingers up open the launcher under the pointer; the end of the
      // shell's mouse lifecycle (a touchpad going away) then reads as an exit.
      controller.beginOpening(byHover: false);
      expect(controller.dismissesOnHoverExit, isFalse);
      controller.scheduleClose();
      controller.openingCompleted();
      await tester.pump(delay * 4);
      expect(closes, 0);

      // The pointer wandering in and out of the settled panel leaves it too.
      controller.cancelClose();
      controller.scheduleClose();
      await tester.pump(delay * 4);
      expect(closes, 0);
    },
  );

  testWidgets('closing forgets how the panel was opened', (tester) async {
    var closes = 0;
    final controller = DesktopPanelHoverController(onClose: () => closes++);
    addTearDown(controller.dispose);

    controller.beginOpening(byHover: true);
    controller.openingCompleted();
    controller.reset();
    expect(controller.dismissesOnHoverExit, isFalse);

    // The next panel opens by Super: no hover dismissal.
    controller.beginOpening(byHover: false);
    controller.openingCompleted();
    controller.scheduleClose();
    await tester.pump(delay * 2);
    expect(closes, 0);

    // And the one after that by the hot edge again.
    controller.reset();
    controller.beginOpening(byHover: true);
    controller.openingCompleted();
    controller.scheduleClose();
    await tester.pump(delay);
    expect(closes, 1);
  });

  testWidgets('a pending close from a hover-opened panel is cancelled', (
    tester,
  ) async {
    var closes = 0;
    final controller = DesktopPanelHoverController(onClose: () => closes++);
    addTearDown(controller.dispose);

    controller.beginOpening(byHover: true);
    controller.openingCompleted();
    controller.scheduleClose();
    await tester.pump(delay ~/ 2);
    // The pointer comes back into the panel.
    controller.cancelClose();
    await tester.pump(delay * 2);
    expect(closes, 0);
  });
}
