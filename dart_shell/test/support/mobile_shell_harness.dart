import 'dart:async';

import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/input.dart' show InputLayoutSnapshot;
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart'
    show HapticsService, hapticsServiceProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tablet's landscape panel at the shell's scale, in logical pixels.
const tabletView = Size(1357, 960);

/// A phone window filling the panel below the status bar, as deniald
/// configures one in the mobile presentation. Without [texture] it has no
/// buffer to draw, so widget tests on flutter_tester, which lacks Denial's
/// window layers, can lay it out.
DenialWindow phoneWindow(
  int id,
  String appId, {
  String? title,
  Rect? geometry,
  bool minimized = false,
  bool texture = true,
  int? splitPartner,
  double splitRatio = 0,
  int? transientParent,
}) {
  final frame = geometry ?? const Rect.fromLTWH(0, 48, 1357, 912);
  return DenialWindow(
    objectId: id,
    objectKind: 'xdg_toplevel',
    surfaceId: id + 100,
    windowId: id + 200,
    textureId: id + 300,
    title: title ?? '$appId $id',
    appId: appId,
    width: texture ? frame.width.round() : 0,
    height: texture ? (frame.height + frame.top).round() : 0,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: frame.width,
    surfaceHeight: frame.height + frame.top,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: frame.width,
    textureSourceHeight: frame.height + frame.top,
    geometryX: frame.left,
    geometryY: frame.top,
    geometryWidth: frame.width,
    geometryHeight: frame.height,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    minimized: minimized,
    splitViewPartnerObjectId: splitPartner,
    splitViewRatio: splitRatio,
    transientParentObjectId: transientParent,
  );
}

/// Windows [left] and [right] (ids, app ids) side by side in Split View
/// on the tablet, the left one taking [share]: their halves as deniald
/// configures them, with its 10 px gap.
(DenialWindow, DenialWindow) splitWindows(
  (int, String) left,
  (int, String) right, {
  double share = 0.5,
  bool texture = true,
}) {
  const width = 1357.0;
  const gap = 10.0;
  final leftWidth = ((width - gap) * share).roundToDouble();
  return (
    phoneWindow(
      left.$1,
      left.$2,
      geometry: Rect.fromLTWH(0, 48, leftWidth, 912),
      splitPartner: right.$1,
      splitRatio: share,
      texture: texture,
    ),
    phoneWindow(
      right.$1,
      right.$2,
      geometry: Rect.fromLTWH(
        leftWidth + gap,
        48,
        width - leftWidth - gap,
        912,
      ),
      splitPartner: left.$1,
      splitRatio: share,
      texture: texture,
    ),
  );
}

/// A bridge whose windows the test publishes and whose requests it records.
class MobileShellBridge extends DenialBridge {
  final _snapshots = StreamController<DenialWindowSnapshot>.broadcast(
    sync: true,
  );
  final _activations = StreamController<int>.broadcast(sync: true);
  final _editors = StreamController<DenialTextInputState>.broadcast(sync: true);
  final _devices = StreamController<DenialInputDeviceCapabilities>.broadcast(
    sync: true,
  );

  List<DenialWindow> windows = const [];
  int _sequence = 0;
  final requests = <String>[];

  /// The compositor publishes [next] as its windows.
  void publish(List<DenialWindow> next) {
    windows = List.unmodifiable(next);
    _snapshots.add(
      DenialWindowSnapshot(sequence: ++_sequence, windows: windows),
    );
  }

  /// The compositor activates [window], as on a touch.
  void activate(DenialWindow window) => _activations.add(window.windowId);

  @override
  Stream<DenialWindowSnapshot> get windowSnapshots => _snapshots.stream;

  @override
  Stream<int> get windowActivations => _activations.stream;

  @override
  Future<DenialWindowSnapshot> listWindows(List<DenialWindow> fallback) async =>
      DenialWindowSnapshot(sequence: _sequence, windows: windows);

  @override
  Stream<DenialTextInputState> get textInputStates => _editors.stream;

  @override
  Stream<DenialInputDeviceCapabilities> get inputDeviceCapabilities =>
      _devices.stream;

  @override
  Future<DenialInputDeviceCapabilities> readInputDeviceCapabilities() async =>
      const DenialInputDeviceCapabilities.none();

  @override
  void focusWindow(DenialWindow window) =>
      requests.add('focus ${window.objectId}');

  @override
  void closeWindow(DenialWindow window) =>
      requests.add('close ${window.objectId}');

  @override
  void minimizeWindow(DenialWindow window) =>
      requests.add('minimize ${window.objectId}');

  /// The input layouts the shell published, the last one last.
  final inputLayouts = <InputLayoutSnapshot>[];

  @override
  bool publishInputLayout(InputLayoutSnapshot snapshot) {
    inputLayouts.add(snapshot);
    return true;
  }

  @override
  void splitView(
    DenialWindow window,
    DenialWindow target, {
    required bool windowOnLeft,
    required double ratio,
  }) => requests.add(
    'split ${window.objectId} ${target.objectId} '
    '${windowOnLeft ? 'left' : 'right'} ${ratio.toStringAsFixed(3)}',
  );

  @override
  void leaveSplitView(DenialWindow window) =>
      requests.add('leave split ${window.objectId}');

  @override
  void prewarmHaptics() {}

  @override
  void dispose() {
    unawaited(_snapshots.close());
    unawaited(_activations.close());
    unawaited(_editors.close());
    unawaited(_devices.close());
    super.dispose();
  }
}

/// The mobile shell's controller over [MobileShellBridge].
class MobileShellHarness {
  MobileShellHarness() {
    container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        startupEnvironmentProvider.overrideWithValue(
          StartupEnvironment(const {'DENIAL_SHELL_PROFILE': 'mobile'}),
        ),
        homeGridControllerProvider.overrideWith(_NoApps.new),
        hapticsServiceProvider.overrideWith(
          (ref) => _QuietHaptics(ref.watch(denialBridgeProvider)),
        ),
      ],
    );
    container.listen(referenceShellProvider, (_, _) {});
  }

  final bridge = MobileShellBridge();
  late final ProviderContainer container;

  ReferenceShellController get controller =>
      container.read(referenceShellProvider.notifier);

  /// Publishes [windows] and lets the controller take them.
  Future<void> publish(WidgetTester tester, List<DenialWindow> windows) async {
    bridge.publish(windows);
    await tester.pump();
  }

  /// Lets the deck's springs come to rest.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 300 && controller.deck.presenting.value; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Ends a test: the fake bridge answers no platform request, so dispose
  /// and let the requests time out.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    bridge.dispose();
  }
}

/// Home with no apps: windows have no home app.
class _NoApps extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: const <HomeGridItem?>[]);
}

class _QuietHaptics extends HapticsService {
  _QuietHaptics(super.bridge);

  @override
  void prewarm() {}

  @override
  void pulse() {}
}
