import 'dart:async';

import 'package:denial_desktop/src/state/power_tiles.dart';
import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/state/reference_shell_state.dart';
import 'package:denial_desktop/src/widgets/shade/power_tiles.dart';
import 'package:denial_desktop/src/widgets/shade/quick_settings_tiles.dart';
import 'package:denial_desktop/src/widgets/shade/shade_progress.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/service_backends.dart'
    show AuthenticationPacket, LogindBackend;
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';

// The Screen off and Sleep tiles of the quick settings. Screen off sends
// deniald the display power request of a double tap, which deniald answers
// as a short press of the power button: it locks, unless Stay awake is on
// (compositor idle_policy tests). Sleep is the power controls' suspend.
void main() {
  group('Screen off', () {
    for (final stayAwake in [false, true]) {
      testWidgets('closes the shade, then turns the screen off once '
          '(Stay awake ${stayAwake ? 'on' : 'off'})', (tester) async {
        final shell = _Shell(stayAwake: stayAwake);
        addTearDown(shell.dispose);
        await tester.pump();
        expect(shell.stayAwake, stayAwake);
        shell.openShade();

        final off = shell.tiles.screenOff();
        // The shade closes first; the screen stays lit while it moves.
        expect(shell.shellState.quickSettingsVisible, isFalse);
        expect(shell.state.screenOffPending, isTrue);
        expect(shell.bridge.screenOffRequests, 0);
        // A second tap while it closes does nothing more.
        await shell.tiles.screenOff();
        shell.shade.value = 0.4;
        await tester.pump();
        expect(shell.bridge.screenOffRequests, 0);

        shell.shade.value = 0;
        await off;
        // The same request either way: deniald decides about the lock.
        expect(shell.bridge.screenOffRequests, 1);
        expect(shell.state.screenOffPending, isFalse);
        // Nothing suspends.
        expect(shell.logind.actions, isEmpty);
        await shell.settle(tester);
      });
    }

    testWidgets('does not wait for a shade that does not close', (
      tester,
    ) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      await tester.pump();
      shell.openShade();

      unawaited(shell.tiles.screenOff());
      await tester.pump(const Duration(milliseconds: 900));
      expect(shell.bridge.screenOffRequests, 0);
      await tester.pump(PowerTilesController.shadeCloseTimeout);
      expect(shell.bridge.screenOffRequests, 1);
      await shell.settle(tester);
    });

    testWidgets('turns the screen off at once when the shade is shut', (
      tester,
    ) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      await tester.pump();
      shell.shade.value = 0;

      await shell.tiles.screenOff();
      expect(shell.bridge.screenOffRequests, 1);
      await shell.settle(tester);
    });
  });

  group('Sleep', () {
    for (final stayAwake in [false, true]) {
      testWidgets('suspends through logind and closes the shade '
          '(Stay awake ${stayAwake ? 'on' : 'off'})', (tester) async {
        final shell = _Shell(stayAwake: stayAwake);
        addTearDown(shell.dispose);
        await tester.pump();
        expect(shell.stayAwake, stayAwake);
        shell.openShade();

        shell.logind.gate = Completer<void>();
        final sleeping = shell.tiles.sleep();
        await tester.pump();
        expect(shell.state.sleepPending, isTrue);
        // A second tap while logind answers does nothing more.
        await shell.tiles.sleep();
        expect(shell.logind.actions, [LogindAction.suspend]);
        expect(shell.shellState.quickSettingsVisible, isTrue);

        shell.logind.gate!.complete();
        await sleeping;
        expect(shell.logind.actions, [LogindAction.suspend]);
        expect(shell.state.sleepPending, isFalse);
        expect(shell.shellState.quickSettingsVisible, isFalse);
        expect(shell.popups, isEmpty);
        // The screen is not turned off by the shell: deniald blanks and
        // locks before the system sleeps.
        expect(shell.bridge.screenOffRequests, 0);
        await shell.settle(tester);
      });
    }

    testWidgets('names the application whose inhibitor blocks the suspend', (
      tester,
    ) async {
      final shell = _Shell(
        snapshot: _snapshot(
          inhibitors: [
            LogindInhibitor(
              what: {'sleep'},
              who: 'Video editor',
              why: 'Export in progress',
              mode: 'block',
              uid: 1000,
              pid: 22,
            ),
          ],
        ),
      );
      addTearDown(shell.dispose);
      await tester.pump();
      shell.openShade();

      await shell.tiles.sleep();
      expect(shell.logind.actions, isEmpty);
      // The power controls open over the shade and say why.
      expect(shell.popups, ['power-and-session']);
      expect(
        shell.container.read(sessionPowerProvider).error,
        'Video editor: Export in progress',
      );
      expect(
        shell.container
            .read(sessionPowerProvider)
            .availabilityFor(SessionPowerAction.suspend)
            .blockers,
        ['Video editor: Export in progress'],
      );
      expect(shell.shellState.quickSettingsVisible, isTrue);
      expect(shell.state.sleepPending, isFalse);
      await shell.settle(tester);
    });

    testWidgets('shows a suspend logind refuses', (tester) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      await tester.pump();
      shell.openShade();

      shell.logind.error = Exception('org.freedesktop.login1.AccessDenied');
      await shell.tiles.sleep();
      expect(shell.logind.actions, [LogindAction.suspend]);
      expect(shell.popups, ['power-and-session']);
      expect(shell.container.read(sessionPowerProvider).error, isNotNull);
      expect(shell.shellState.quickSettingsVisible, isTrue);
      await shell.settle(tester);
    });

    testWidgets('is not held back by a confirmation the power menu left', (
      tester,
    ) async {
      final shell = _Shell();
      addTearDown(shell.dispose);
      await tester.pump();
      final power = shell.container.read(sessionPowerProvider.notifier);
      await power.request(SessionPowerAction.powerOff);
      expect(
        shell.container.read(sessionPowerProvider).confirmationAction,
        SessionPowerAction.powerOff,
      );

      await shell.tiles.sleep();
      expect(shell.logind.actions, [LogindAction.suspend]);
      expect(
        shell.container.read(sessionPowerProvider).confirmationAction,
        isNull,
      );
      await shell.settle(tester);
    });
  });

  group('the tiles', () {
    Future<_TappedTiles> pumpTile(
      WidgetTester tester,
      QuickTile Function(WidgetRef ref, AppLocalizations l10n) build, {
      PowerTilesState state = const PowerTilesState(),
    }) async {
      final tiles = _TappedTiles(state);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [powerTilesProvider.overrideWith(() => tiles)],
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 128,
                  height: 107,
                  child: Consumer(
                    builder: (context, ref, _) => build(ref, context.l10n),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return tiles;
    }

    QuickTile tile(WidgetTester tester) =>
        tester.widget<QuickTile>(find.byType(QuickTile));
    final l10n = AppLocalizationsEn();

    testWidgets('Screen off is an action, not a switch', (tester) async {
      final tiles = await pumpTile(tester, screenOffQuickTile);
      expect(tile(tester).title, l10n.quickSettingsScreenOff);
      expect(tile(tester).icon, Icons.mobile_off_rounded);
      expect(tile(tester).active, isFalse);
      expect(tile(tester).enabled, isTrue);
      await tester.tap(find.byType(QuickTile));
      expect(tiles.taps, ['screenOff']);

      tiles.show(const PowerTilesState(screenOffPending: true));
      await tester.pump();
      expect(tile(tester).enabled, isFalse);
    });

    testWidgets('Sleep waits while logind is asked', (tester) async {
      final tiles = await pumpTile(tester, sleepQuickTile);
      expect(tile(tester).title, l10n.quickSettingsSleep);
      expect(tile(tester).icon, Icons.bedtime_rounded);
      expect(tile(tester).active, isFalse);
      await tester.tap(find.byType(QuickTile));
      expect(tiles.taps, ['sleep']);

      tiles.show(const PowerTilesState(sleepPending: true));
      await tester.pump();
      expect(tile(tester).enabled, isFalse);
      expect(tile(tester).busy, isTrue);
    });

    test('are named in every language', () {
      expect(AppLocalizationsEn().quickSettingsScreenOff, 'Screen off');
      expect(AppLocalizationsRu().quickSettingsScreenOff, 'Погасить экран');
      expect(AppLocalizationsZh().quickSettingsScreenOff, '关闭屏幕');
      expect(AppLocalizationsEn().quickSettingsSleep, 'Sleep');
      expect(AppLocalizationsRu().quickSettingsSleep, 'Сон');
      expect(AppLocalizationsZh().quickSettingsSleep, '睡眠');
    });
  });
}

/// The mobile shell with its shade, a stand-in for deniald's display power
/// channel and one for logind.
class _Shell {
  _Shell({bool stayAwake = false, LogindSnapshot? snapshot})
    : transport = LiveSettingsTransport({
        'power': <String, Object?>{'stayAwake': stayAwake},
      }),
      logind = _FakeLogind(snapshot ?? _snapshot()) {
    container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        authenticationServiceProvider.overrideWithValue(authentication),
        startupEnvironmentProvider.overrideWithValue(
          StartupEnvironment(const {'DENIAL_SHELL_PROFILE': 'mobile'}),
        ),
        logindServiceProvider.overrideWithValue(logind),
        settingsStoreProvider.overrideWithValue(NativeSettingsStore(transport)),
      ],
    );
    container.listen(referenceShellProvider, (_, _) {});
    container.listen(shellSettingsProvider, (_, _) {});
    container.listen(sessionPowerProvider, (_, _) {});
    container.read(shadeProgressProvider).parent = shade;
  }

  final bridge = _FakeBridge();
  final authentication = _FakeAuthenticationService();
  final LiveSettingsTransport transport;
  final _FakeLogind logind;
  final shade = AnimationController(vsync: const TestVSync(), value: 0);
  late final ProviderContainer container;

  PowerTilesController get tiles => container.read(powerTilesProvider.notifier);
  PowerTilesState get state => container.read(powerTilesProvider);
  ReferenceShellState get shellState => container.read(referenceShellProvider);
  bool get stayAwake => container.read(shellSettingsProvider).power.stayAwake;
  List<String?> get popups => [
    for (final popup in container.read(shellPopupControllerProvider))
      if (!popup.closing) popup.keyName,
  ];

  /// The shade is pulled all the way down.
  void openShade() {
    container.read(referenceShellProvider.notifier).openQuickSettings();
    shade.value = 1;
    expect(shellState.quickSettingsVisible, isTrue);
  }

  /// The fake bridge answers no platform request: dispose, then let the
  /// requests time out.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    shade.dispose();
    unawaited(transport.close());
    authentication.dispose();
  }
}

class _FakeBridge extends DenialBridge {
  int screenOffRequests = 0;

  @override
  void requestDpmsOff() => screenOffRequests += 1;
}

class _FakeAuthenticationService implements AuthenticationService {
  final StreamController<AuthenticationPacket> _events =
      StreamController<AuthenticationPacket>.broadcast(sync: true);

  @override
  Stream<AuthenticationPacket> get events => _events.stream;

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

class _FakeLogind implements LogindBackend {
  _FakeLogind(this._current);

  final StreamController<LogindSnapshot> _snapshots =
      StreamController<LogindSnapshot>.broadcast(sync: true);
  LogindSnapshot _current;
  final List<LogindAction> actions = <LogindAction>[];
  Completer<void>? gate;
  Object? error;

  @override
  LogindSnapshot get currentSnapshot => _current;

  @override
  Stream<LogindSnapshot> get snapshots => _snapshots.stream;

  void _emit(LogindSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<void> start() async => _emit(_current);

  @override
  Future<void> refresh() async => _emit(_current);

  @override
  Future<void> perform(LogindAction action) async {
    actions.add(action);
    await gate?.future;
    if (error case final value?) {
      throw value;
    }
  }

  @override
  Future<void> dispose() => _snapshots.close();
}

LogindSnapshot _snapshot({
  List<LogindInhibitor> inhibitors = const <LogindInhibitor>[],
}) => LogindSnapshot(
  serviceAvailable: true,
  capabilities: {
    for (final action in LogindAction.values)
      action: LogindCapability.available,
  },
  inhibitors: inhibitors,
);

/// A tiles controller that holds the state the test shows and records taps.
class _TappedTiles extends PowerTilesController {
  _TappedTiles(this._initial);

  final PowerTilesState _initial;
  final taps = <String>[];

  @override
  PowerTilesState build() => _initial;

  @override
  Future<void> screenOff() async => taps.add('screenOff');

  @override
  Future<void> sleep() async => taps.add('sleep');

  void show(PowerTilesState next) => state = next;
}
