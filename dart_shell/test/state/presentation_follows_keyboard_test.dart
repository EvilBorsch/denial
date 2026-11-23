import 'dart:async';

import 'package:denial_desktop/src/state/reference_shell_presentation.dart';
import 'package:denial_desktop/src/state/reference_shell_profile.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';

// The tablet's presentation follows its keyboard cover: attached, the
// desktop; detached, the tablet. The tile switches by hand until the next
// attach or detach, a setting turns the automation off, and the shell starts
// in the presentation it showed last.
void main() {
  const mobile = ReferenceShellProfile.mobile;
  const desktop = ReferenceShellProfile.desktop;
  const grace = ReferenceShellPresentation.detachGrace;

  testWidgets('a keyboard attached brings up the desktop, the last one '
      'detached the tablet', (tester) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: false);
    expect(shell.presentation, mobile);

    // The OnePlus Pad 3 cover: a keyboard and a touchpad.
    shell.devices(keyboard: true, touchpad: true);
    expect(shell.presentation, desktop);
    await shell.settle();
    expect(shell.stored, {
      'followKeyboard': true,
      'mode': 'desktop',
      'modeKeyboard': true,
    });

    // A cover whose driver switched it off and on again: no flip.
    shell.devices(keyboard: false);
    await tester.pump(const Duration(seconds: 2));
    expect(shell.presentation, desktop);
    shell.devices(keyboard: true, touchpad: true);
    await tester.pump(grace * 2);
    expect(shell.presentation, desktop);

    shell.devices(keyboard: false);
    await tester.pump(grace - const Duration(milliseconds: 100));
    expect(shell.presentation, desktop);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell.presentation, mobile);
    await shell.settle();
    expect(shell.stored, {
      'followKeyboard': true,
      'mode': 'tablet',
      'modeKeyboard': false,
    });
    expect(shell.switches, [desktop, mobile]);
    await shell.stop();
  });

  testWidgets('a virtual keyboard, such as a test tool\'s, switches nothing', (
    tester,
  ) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: false);

    shell.devices(keyboard: true, physicalKeyboard: false);
    await tester.pump(grace * 2);
    expect(shell.presentation, mobile);

    // And it does not count as a keyboard staying attached either.
    shell.devices(keyboard: true);
    expect(shell.presentation, desktop);
    shell.devices(keyboard: true, physicalKeyboard: false);
    await tester.pump(grace);
    expect(shell.presentation, mobile);
    await shell.stop();
  });

  testWidgets('the tile\'s choice holds until the next attach or detach', (
    tester,
  ) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: true);
    expect(shell.presentation, desktop);

    shell.toggle();
    expect(shell.presentation, mobile);
    await shell.settle();
    expect(shell.stored, {
      'followKeyboard': true,
      'mode': 'tablet',
      'modeKeyboard': true,
    });
    // Other device reports change nothing: a mouse comes and goes.
    shell.devices(keyboard: true, mouse: true);
    shell.devices(keyboard: true);
    await tester.pump(grace * 2);
    expect(shell.presentation, mobile);

    // The next detach and attach decide again.
    shell.devices(keyboard: false);
    await tester.pump(grace);
    expect(shell.presentation, mobile);
    shell.devices(keyboard: true);
    expect(shell.presentation, desktop);

    // By hand without a keyboard: the desktop until one is attached and
    // detached.
    shell.devices(keyboard: false);
    await tester.pump(grace);
    expect(shell.presentation, mobile);
    shell.toggle();
    expect(shell.presentation, desktop);
    await tester.pump(grace * 2);
    expect(shell.presentation, desktop);
    shell.devices(keyboard: true);
    expect(shell.presentation, desktop);
    shell.devices(keyboard: false);
    await tester.pump(grace);
    expect(shell.presentation, mobile);
    await shell.stop();
  });

  testWidgets('a choice made while a detach waits out its grace comes after '
      'it', (tester) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: true);

    shell.devices(keyboard: false);
    await tester.pump(const Duration(seconds: 1));
    shell.toggle();
    expect(shell.presentation, mobile);
    shell.toggle();
    expect(shell.presentation, desktop);
    await tester.pump(grace * 2);
    expect(shell.presentation, desktop);
    await shell.settle();
    expect(shell.stored['modeKeyboard'], isFalse);
    await shell.stop();
  });

  testWidgets('switched off, the keyboard switches nothing; switched on, it '
      'decides at once', (tester) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: false, stored: {'followKeyboard': false});
    expect(shell.presentation, mobile);

    shell.devices(keyboard: true);
    await tester.pump(grace);
    expect(shell.presentation, mobile);
    shell.toggle();
    expect(shell.presentation, desktop);
    shell.devices(keyboard: false);
    await tester.pump(grace * 2);
    expect(shell.presentation, desktop);

    shell.devices(keyboard: true);
    shell.toggle();
    expect(shell.presentation, mobile);
    shell.settings.setFollowKeyboard(true);
    expect(shell.presentation, desktop);
    await shell.settle();
    expect(shell.stored, {
      'followKeyboard': true,
      'mode': 'desktop',
      'modeKeyboard': true,
    });
    await shell.stop();
  });

  group('after a restart', () {
    testWidgets('switched off, the presentation chosen last comes back', (
      tester,
    ) async {
      final shell = _Shell(tester);
      await shell.start(
        keyboard: false,
        stored: {
          'followKeyboard': false,
          'mode': 'desktop',
          'modeKeyboard': false,
        },
      );
      expect(shell.presentation, desktop);
      shell.devices(keyboard: true);
      await tester.pump(grace);
      shell.devices(keyboard: false);
      await tester.pump(grace * 2);
      expect(shell.presentation, desktop);
      await shell.stop();
    });

    testWidgets('a choice by hand with the keyboard as it is now holds', (
      tester,
    ) async {
      // The tablet chosen by hand with the cover attached; still attached.
      final shell = _Shell(tester);
      await shell.start(
        keyboard: true,
        stored: {
          'followKeyboard': true,
          'mode': 'tablet',
          'modeKeyboard': true,
        },
      );
      expect(shell.presentation, mobile);
      expect(shell.switches, isEmpty, reason: 'never the desktop');
      await shell.stop();
    });

    testWidgets('a keyboard attached or detached since decides, once', (
      tester,
    ) async {
      // The tablet, chosen without the cover, which is attached now.
      var shell = _Shell(tester);
      await shell.start(
        keyboard: true,
        stored: {
          'followKeyboard': true,
          'mode': 'tablet',
          'modeKeyboard': false,
        },
      );
      expect(shell.presentation, desktop);
      await shell.settle();
      expect(shell.stored['mode'], 'desktop');
      expect(shell.stored['modeKeyboard'], isTrue);
      await shell.stop();

      // The desktop with the cover; the session restarts without it.
      shell = _Shell(tester);
      await shell.start(
        keyboard: false,
        stored: {
          'followKeyboard': true,
          'mode': 'desktop',
          'modeKeyboard': true,
        },
      );
      expect(shell.presentation, mobile);
      expect(shell.switches, [desktop, mobile]);
      await shell.stop();
    });

    testWidgets('the stored presentation shows before the device list '
        'arrives', (tester) async {
      final shell = _Shell(tester);
      await shell.start(
        keyboard: null,
        stored: {
          'followKeyboard': true,
          'mode': 'desktop',
          'modeKeyboard': true,
        },
      );
      expect(shell.presentation, desktop);
      shell.devices(keyboard: true, touchpad: true);
      await shell.settle();
      expect(shell.switches, [desktop]);
      await shell.stop();
    });

    testWidgets('settings from before this release: the keyboard decides', (
      tester,
    ) async {
      final shell = _Shell(tester);
      await shell.start(keyboard: true, stored: null);
      expect(shell.presentation, desktop);
      await shell.settle();
      expect(shell.stored, {
        'followKeyboard': true,
        'mode': 'desktop',
        'modeKeyboard': true,
      });
      await shell.stop();
    });

    testWidgets('the session restarted by the test tools keeps the tile\'s '
        'choice', (tester) async {
      // Restarted through the tile's desktop without a keyboard, and the
      // test tool's virtual keyboard attached: the desktop stays.
      final shell = _Shell(tester);
      await shell.start(
        keyboard: false,
        virtualKeyboard: true,
        stored: {
          'followKeyboard': true,
          'mode': 'desktop',
          'modeKeyboard': false,
        },
      );
      expect(shell.presentation, desktop);
      expect(shell.switches, [desktop]);
      await shell.stop();
    });
  });

  testWidgets('a presentation set through the settings channel is a choice '
      'by hand', (tester) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: true);
    expect(shell.presentation, desktop);
    await shell.settle();

    // erhai-denial-setting presentation.mode tablet
    shell.transport.publish({
      'presentation': {
        'followKeyboard': true,
        'mode': 'tablet',
        'modeKeyboard': true,
      },
    });
    await tester.pump();
    expect(shell.presentation, mobile);
    shell.devices(keyboard: false);
    await tester.pump(grace);
    shell.devices(keyboard: true);
    expect(shell.presentation, desktop);
    await shell.settle();

    // erhai-denial-setting presentation.followKeyboard false
    shell.transport.publish({
      'presentation': {
        'followKeyboard': false,
        'mode': 'desktop',
        'modeKeyboard': true,
      },
    });
    await tester.pump();
    shell.devices(keyboard: false);
    await tester.pump(grace * 2);
    expect(shell.presentation, desktop);
    await shell.stop();
  });

  testWidgets('with a monitor beside the tablet nothing switches on its own', (
    tester,
  ) async {
    final shell = _Shell(tester);
    await shell.start(keyboard: false);
    shell.screens(single: false);

    shell.devices(keyboard: true);
    await tester.pump(grace);
    expect(shell.presentation, mobile);

    // Unplugged: the keyboard attached meanwhile decides, as at a start.
    shell.screens(single: true);
    expect(shell.presentation, desktop);

    // A session that starts with a monitor in waits for its screens.
    await shell.stop();
    final next = _Shell(tester);
    await next.start(keyboard: true, single: null);
    expect(next.presentation, mobile);
    next.screens(single: false);
    await tester.pump();
    expect(next.presentation, mobile);
    next.screens(single: true);
    expect(next.presentation, desktop);
    await next.stop();
  });
}

/// The shell's presentation with deniald's settings document, its device
/// list and its screens.
class _Shell {
  _Shell(this.tester);

  final WidgetTester tester;
  final bridge = _FakeBridge();
  late LiveSettingsTransport transport;
  late ProviderContainer container;
  final switches = <ReferenceShellProfile>[];
  bool? _single;

  ReferenceShellProfile get presentation =>
      container.read(referenceShellPresentationProvider);

  ShellSettingsController get settings =>
      container.read(shellSettingsProvider.notifier);

  /// The presentation section as deniald holds it.
  Map<String, dynamic> get stored =>
      transport.decoded['presentation'] as Map<String, dynamic>;

  /// Starts a session with a mobile startup profile. [stored] is the
  /// settings document's presentation section (null: none). [keyboard] is
  /// the first device report (null: none yet).
  Future<void> start({
    required bool? keyboard,
    bool virtualKeyboard = false,
    Map<String, Object?>? stored = const {},
    bool? single = true,
  }) async {
    transport = LiveSettingsTransport({'presentation': ?stored});
    if (stored == null) {
      // Written by a release before this one: no section at all.
      transport.document = transport.document.replaceFirst(
        RegExp(r'"presentation":\{[^}]*\},?'),
        '',
      );
    }
    _single = single;
    container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        settingsStoreProvider.overrideWithValue(NativeSettingsStore(transport)),
        startupEnvironmentProvider.overrideWithValue(
          StartupEnvironment(const {'DENIAL_SHELL_PROFILE': 'mobile'}),
        ),
        singleScreenSessionProvider.overrideWith((ref) => ref.watch(_screens)),
      ],
    );
    container.listen(shellSettingsProvider, (_, _) {});
    container.listen(referenceShellPresentationProvider, (previous, next) {
      if (previous != next) switches.add(next);
    }, fireImmediately: false);
    container.read(_screens.notifier).set(_single);
    if (keyboard != null) {
      devices(keyboard: keyboard, physicalKeyboard: keyboard);
      if (virtualKeyboard && !keyboard) {
        devices(keyboard: true, physicalKeyboard: false);
      }
    }
    await tester.pump();
    await tester.pump();
  }

  void devices({
    required bool keyboard,
    bool? physicalKeyboard,
    bool touchpad = false,
    bool mouse = false,
  }) => bridge.devices(
    DenialInputDeviceCapabilities.none().copyWith(
      revision: 1,
      hasKeyboard: keyboard,
      hasPhysicalKeyboard: physicalKeyboard ?? keyboard,
      hasTouchpad: touchpad,
      hasMouse: mouse,
    ),
  );

  void screens({required bool? single}) =>
      container.read(_screens.notifier).set(single);

  void toggle() =>
      container.read(referenceShellPresentationProvider.notifier).toggle();

  /// Lets the settings write go out.
  Future<void> settle() async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> stop() async {
    await settle();
    container.dispose();
    await transport.close();
  }
}

final _screens = NotifierProvider<_Screens, bool?>(_Screens.new);

class _Screens extends Notifier<bool?> {
  @override
  bool? build() => true;

  void set(bool? single) => state = single;
}

class _FakeBridge extends DenialBridge {
  final _devices = StreamController<DenialInputDeviceCapabilities>.broadcast(
    sync: true,
  );

  @override
  Stream<DenialInputDeviceCapabilities> get inputDeviceCapabilities =>
      _devices.stream;

  @override
  Future<DenialInputDeviceCapabilities> readInputDeviceCapabilities() =>
      Completer<DenialInputDeviceCapabilities>().future;

  void devices(DenialInputDeviceCapabilities capabilities) =>
      _devices.add(capabilities);
}
