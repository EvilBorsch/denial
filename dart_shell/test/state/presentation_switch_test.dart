import 'package:denial_desktop/src/state/presentation_switch.dart';
import 'package:denial_desktop/src/state/reference_shell_presentation.dart';
import 'package:denial_desktop/src/state/reference_shell_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

// A switch between the tablet and desktop presentations is covered by the
// frame on screen: the shell asks deniald to freeze it, keeps showing what it
// has until the frozen frame comes, switches under it and releases it after
// the dissolve. Without an answer (a deniald before eb19) it switches after
// a short wait, as before.

/// The presentation chosen, set by the test instead of the keyboard, the
/// tile and the settings.
class _Chosen extends ReferenceShellPresentation {
  @override
  ReferenceShellProfile build() => ReferenceShellProfile.desktop;

  void choose(ReferenceShellProfile presentation) => state = presentation;
}

void main() {
  const mobile = ReferenceShellProfile.mobile;
  const desktop = ReferenceShellProfile.desktop;

  MobileShellHarness shellFor(bool singleScreen) {
    final shell = MobileShellHarness(
      overrides: [
        referenceShellPresentationProvider.overrideWith(_Chosen.new),
        singleScreenSessionProvider.overrideWithValue(singleScreen),
      ],
    );
    addTearDown(shell.dispose);
    return shell;
  }

  PresentationSwitchState stateOf(MobileShellHarness shell) =>
      shell.container.read(presentationSwitchProvider);

  void choose(MobileShellHarness shell, ReferenceShellProfile presentation) =>
      (shell.container.read(referenceShellPresentationProvider.notifier)
              as _Chosen)
          .choose(presentation);

  /// The shell up and drawn once, in the desktop presentation.
  Future<MobileShellHarness> drawnShell(
    WidgetTester tester, {
    bool singleScreen = true,
  }) async {
    final shell = shellFor(singleScreen);
    shell.container.listen(presentationSwitchProvider, (_, _) {});
    await tester.pump();
    shell.container.read(presentationSwitchProvider.notifier).drawn();
    return shell;
  }

  testWidgets('the switch waits for the frozen frame, switches under it and '
      'releases it after the dissolve', (tester) async {
    final shell = await drawnShell(tester);
    expect(stateOf(shell), const PresentationSwitchState(shown: desktop));

    choose(shell, mobile);
    // Still the desktop: its frame is what deniald freezes, without the
    // cursor, and frames keep coming meanwhile.
    expect(shell.bridge.requests, ['cover 1']);
    expect(
      stateOf(shell),
      const PresentationSwitchState(shown: desktop, waiting: true),
    );

    shell.bridge.answerCover(1, 42);
    expect(
      stateOf(shell),
      const PresentationSwitchState(shown: mobile, coverTexture: 42),
    );

    // The cover dissolved.
    shell.container.read(presentationSwitchProvider.notifier).release(42);
    expect(shell.bridge.requests, ['cover 1', 'release cover 1']);
    expect(stateOf(shell), const PresentationSwitchState(shown: mobile));
    // A stale release changes nothing.
    shell.container.read(presentationSwitchProvider.notifier).release(42);
    expect(shell.bridge.requests, ['cover 1', 'release cover 1']);
    await shell.finish(tester);
  });

  testWidgets('a deniald that does not answer delays the switch by the wait '
      'at most, and a late answer is released', (tester) async {
    final shell = await drawnShell(tester);
    choose(shell, mobile);
    await tester.pump(
      PresentationSwitch.coverWait - const Duration(milliseconds: 10),
    );
    expect(stateOf(shell).shown, desktop);
    await tester.pump(const Duration(milliseconds: 20));
    expect(stateOf(shell), const PresentationSwitchState(shown: mobile));
    // deniald may still have it under way: it drops it.
    expect(shell.bridge.requests, ['cover 1', 'release cover 1']);

    shell.bridge.answerCover(1, 42);
    expect(shell.bridge.requests.last, 'release cover 1');
    expect(stateOf(shell), const PresentationSwitchState(shown: mobile));
    await shell.finish(tester);
  });

  testWidgets('an answer without a frozen frame switches at once', (
    tester,
  ) async {
    final shell = await drawnShell(tester);
    choose(shell, mobile);
    shell.bridge.answerCover(1, null);
    expect(stateOf(shell), const PresentationSwitchState(shown: mobile));
    await shell.finish(tester);
  });

  testWidgets('chosen back while waiting: nothing switches, the cover goes', (
    tester,
  ) async {
    final shell = await drawnShell(tester);
    choose(shell, mobile);
    choose(shell, desktop);
    shell.bridge.answerCover(1, 42);
    expect(stateOf(shell), const PresentationSwitchState(shown: desktop));
    expect(shell.bridge.requests, ['cover 1', 'release cover 1']);
    await shell.finish(tester);
  });

  testWidgets('a switch during the dissolve frees the cover before it asks '
      'for the next', (tester) async {
    final shell = await drawnShell(tester);
    choose(shell, mobile);
    shell.bridge.answerCover(1, 42);
    choose(shell, desktop);
    expect(shell.bridge.requests, ['cover 1', 'release cover 1', 'cover 2']);
    shell.bridge.answerCover(2, 43);
    expect(
      stateOf(shell),
      const PresentationSwitchState(shown: desktop, coverTexture: 43),
    );
    // The first cover's own release comes late: it is already gone.
    shell.container.read(presentationSwitchProvider.notifier).release(42);
    expect(shell.bridge.requests.last, 'cover 2');
    await shell.finish(tester);
  });

  testWidgets('no cover is asked for before the first frame or beside a '
      'monitor', (tester) async {
    final shell = shellFor(true);
    shell.container.listen(presentationSwitchProvider, (_, _) {});
    // The start restores the presentation shown last.
    choose(shell, mobile);
    expect(stateOf(shell), const PresentationSwitchState(shown: mobile));
    expect(shell.bridge.requests, isEmpty);
    await shell.finish(tester);

    final beside = await drawnShell(tester, singleScreen: false);
    choose(beside, mobile);
    expect(stateOf(beside), const PresentationSwitchState(shown: mobile));
    expect(beside.bridge.requests, isEmpty);
    await beside.finish(tester);
  });
}
