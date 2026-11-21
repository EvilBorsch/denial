import 'dart:async';

import 'package:denial_desktop/src/state/hardware_keyboard.dart';
import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/state/reference_shell_metrics.dart';
import 'package:denial_desktop/src/widgets/edge_panel_layer.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/service_backends.dart'
    show AuthenticationPacket, AuthenticationPacketKind;
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The mobile lock screen's password entry. The compositor reports the shell's
// own editor and the attached input devices; while the password panel is up
// the lock screen alone decides whether the software keyboard shows, and the
// panel stays above the keys.
void main() {
  testWidgets('a keyboard cover counts at once and its detach only after a '
      'grace', (tester) async {
    final bridge = _FakeBridge();
    final container = ProviderContainer.test(
      overrides: [denialBridgeProvider.overrideWithValue(bridge)],
    );
    container.listen(hardwareKeyboardAttachedProvider, (_, _) {});
    await tester.pump();
    expect(container.read(hardwareKeyboardAttachedProvider), isFalse);

    // The OnePlus Pad 3 cover attaches as a keyboard and a touchpad.
    bridge.devices(keyboard: true, touchpad: true);
    expect(container.read(hardwareKeyboardAttachedProvider), isTrue);

    // A cover that drops off its connector and comes straight back.
    bridge.devices(keyboard: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(hardwareKeyboardAttachedProvider), isTrue);
    bridge.devices(keyboard: true, touchpad: true);
    await tester.pump(HardwareKeyboardAttached.detachGrace * 2);
    expect(container.read(hardwareKeyboardAttachedProvider), isTrue);

    bridge.devices(keyboard: false);
    await tester.pump(HardwareKeyboardAttached.detachGrace);
    expect(container.read(hardwareKeyboardAttachedProvider), isFalse);
  });

  testWidgets('a touchpad or a mouse alone is no keyboard cover', (
    tester,
  ) async {
    final bridge = _FakeBridge();
    final container = ProviderContainer.test(
      overrides: [denialBridgeProvider.overrideWithValue(bridge)],
    );
    container.listen(hardwareKeyboardAttachedProvider, (_, _) {});
    await tester.pump();

    bridge.devices(keyboard: false, touchpad: true, mouse: true);
    await tester.pump(HardwareKeyboardAttached.detachGrace * 2);
    expect(container.read(hardwareKeyboardAttachedProvider), isFalse);

    // A Bluetooth keyboard without a touchpad.
    bridge.devices(keyboard: true);
    expect(container.read(hardwareKeyboardAttachedProvider), isTrue);
  });

  testWidgets('the lock screen keeps the keyboard it shows while the '
      "compositor's editor state changes", (tester) async {
    final shell = _ShellHarness();
    addTearDown(shell.dispose);
    final controller = shell.container.read(referenceShellProvider.notifier);
    shell.lock();
    expect(shell.container.read(referenceShellProvider).locked, isTrue);

    // Without the lock screen's claim, the compositor's "no panel" for the
    // shell's editor closes the keyboard.
    controller.openEdgePanel();
    shell.bridge.editor(active: true, panel: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell.container.read(referenceShellProvider).edgePanelVisible, isFalse);

    // The password panel claims it: the field closing and reopening between
    // prompts, or a request that came too late after the swipe, changes
    // nothing.
    controller.setLockScreenKeyboardOwner(true);
    controller.openEdgePanel();
    shell.bridge.editor(active: false, panel: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell.container.read(referenceShellProvider).edgePanelVisible, isTrue);
    controller.closeEdgePanel();
    shell.bridge.editor(active: true, panel: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell.container.read(referenceShellProvider).edgePanelVisible, isFalse);

    // The claim never outlives the lock.
    controller.openEdgePanel();
    shell.unlock();
    shell.bridge.editor(active: true, panel: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell.container.read(referenceShellProvider).edgePanelVisible, isTrue);
    shell.bridge.editor(active: false, panel: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shell.container.read(referenceShellProvider).edgePanelVisible, isFalse);
    await shell.settle(tester);
  });

  for (final view in const [Size(2261, 1600), Size(1600, 2261), Size(412, 915)]) {
    testWidgets('the password panel rides above the keyboard (${view.width.round()}'
        'x${view.height.round()})', (tester) async {
      final shell = _ShellHarness();
      addTearDown(shell.dispose);
      shell.lock();
      tester.view.physicalSize = view;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const clearance = 22.0;
      const gap = 16.0;
      const panel = Key('panel');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: shell.container,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: EdgeInsets.only(bottom: clearance),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: KeyboardClearance(
                  clearance: clearance,
                  gap: gap,
                  child: SizedBox(key: panel, width: 300, height: 260),
                ),
              ),
            ),
          ),
        ),
      );
      Rect shown() => tester.getRect(find.byKey(panel));
      expect(shown().bottom, view.height - clearance);

      final keys = ReferenceShellMetrics.edgePanelHeight(
        view,
        shortcuts: shell.container.read(referenceShellProvider).oskShortcuts,
      );
      shell.container.read(referenceShellProvider.notifier).openEdgePanel();
      await tester.pumpAndSettle();
      // The layer moves in whole physical pixels.
      expect(shown().bottom, moreOrLessEquals(view.height - keys - gap, epsilon: 1));
      // A tap lands where the panel shows, not where its layout left it.
      var taps = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: shell.container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.only(bottom: clearance),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: KeyboardClearance(
                  clearance: clearance,
                  gap: gap,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps += 1,
                    child: const SizedBox(key: panel, width: 300, height: 260),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(shown().center);
      expect(taps, 1);

      shell.container.read(referenceShellProvider.notifier).closeEdgePanel();
      await tester.pumpAndSettle();
      expect(shown().bottom, view.height - clearance);      await shell.settle(tester);
    });
  }
}

class _ShellHarness {
  _ShellHarness() {
    container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        authenticationServiceProvider.overrideWithValue(authentication),
        startupEnvironmentProvider.overrideWithValue(
          StartupEnvironment(const {'DENIAL_SHELL_PROFILE': 'mobile'}),
        ),
      ],
    );
    container.listen(referenceShellProvider, (_, _) {});
  }

  final bridge = _FakeBridge();
  final authentication = _FakeAuthenticationService();
  late final ProviderContainer container;

  /// The fake bridge answers no platform request: dispose, then let the
  /// requests time out.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  void lock() => authentication.emit(_state(locked: true));
  void unlock() => authentication.emit(_state(locked: false));

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    authentication.dispose();
  }
}

class _FakeBridge extends DenialBridge {
  final _devices = StreamController<DenialInputDeviceCapabilities>.broadcast(
    sync: true,
  );
  final _editors = StreamController<DenialTextInputState>.broadcast(sync: true);
  int _serial = 0;

  @override
  Stream<DenialInputDeviceCapabilities> get inputDeviceCapabilities =>
      _devices.stream;

  @override
  Future<DenialInputDeviceCapabilities> readInputDeviceCapabilities() async =>
      const DenialInputDeviceCapabilities.none();

  @override
  Stream<DenialTextInputState> get textInputStates => _editors.stream;

  void devices({
    required bool keyboard,
    bool touchpad = false,
    bool mouse = false,
  }) => _devices.add(
    const DenialInputDeviceCapabilities.none().copyWith(
      hasKeyboard: keyboard,
      hasTouchpad: touchpad,
      hasMouse: mouse,
    ),
  );

  void editor({required bool active, required bool panel}) => _editors.add(
    DenialTextInputState(
      active: active,
      inputPanelVisible: panel,
      legacy: false,
      contentHint: 0,
      contentPurpose: 0,
      activationSerial: ++_serial,
    ),
  );
}

class _FakeAuthenticationService implements AuthenticationService {
  final StreamController<AuthenticationPacket> _events =
      StreamController<AuthenticationPacket>.broadcast(sync: true);

  @override
  Stream<AuthenticationPacket> get events => _events.stream;

  void emit(AuthenticationPacket packet) => _events.add(packet);

  @override
  void begin({bool password = false}) {}

  @override
  void cancel({required int attemptId}) {}

  @override
  void lock() {}

  @override
  void respond({
    required int attemptId,
    required int promptSequence,
    required String response,
  }) {}

  @override
  void synchronize() {}

  @override
  void offerFingerprint(bool offered) {}

  @override
  void dispose() {
    unawaited(_events.close());
  }
}

AuthenticationPacket _state({required bool locked}) => AuthenticationPacket(
  kind: AuthenticationPacketKind.state,
  locked: locked,
  available: true,
  busy: false,
  rateLimited: false,
  attemptId: 0,
  argument: 0,
  payload: '',
);
