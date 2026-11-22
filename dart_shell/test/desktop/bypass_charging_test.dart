import 'dart:io';

import 'package:denial_desktop/src/state/bypass_charging.dart';
import 'package:denial_desktop/src/widgets/shade/bypass_charging_tile.dart';
import 'package:denial_desktop/src/widgets/shade/quick_settings_tiles.dart';
import 'package:denial_desktop/src/widgets/shade/shade_progress.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_sdk/system.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A power-supply class directory. Each supply is a map of its attribute
/// files and a link to its device, as in sysfs.
Future<String> _sysfs(Map<String, Map<String, String>> supplies) async {
  final temp = await Directory.systemTemp.createTemp('bypass-charging-');
  addTearDown(() => temp.delete(recursive: true));
  final root = await Directory('${temp.path}/power_supply').create();
  final devices = await Directory('${temp.path}/devices').create();
  for (final MapEntry(key: name, value: attributes) in supplies.entries) {
    final device = await Directory('${devices.path}/$name').create();
    for (final MapEntry(key: attribute, value: contents)
        in attributes.entries) {
      await File('${device.path}/$attribute').writeAsString(contents);
    }
    await Link('${root.path}/$name').create(device.path);
  }
  return root.path;
}

Map<String, String> _battery(String chargeBehaviour) => {
  'type': 'Battery\n',
  'charge_behaviour': chargeBehaviour,
};

/// What the kernel does with a write to `charge_behaviour`: it selects the
/// written behaviour if it is offered, or refuses the write.
class _Kernel {
  final writes = <String>[];

  /// The error the next writes fail with, when set.
  FileSystemException? refuse;

  Future<void> write(String path, String value) async {
    writes.add(value);
    final error = refuse;
    if (error != null) throw error;
    final file = File(path);
    final offered = [
      for (final word in (await file.readAsString()).trim().split(' '))
        word.replaceAll(RegExp(r'[\[\]]'), ''),
    ];
    if (!offered.contains(value)) {
      throw FileSystemException(
        'Cannot write',
        path,
        const OSError('Invalid argument', 22),
      );
    }
    await file.writeAsString(
      '${offered.map((word) => word == value ? '[$word]' : word).join(' ')}\n',
    );
  }
}

/// The battery source, reporting only what the test tells it.
class _Battery extends BatteryController {
  @override
  BatteryStatus build() => BatteryStatus.unknown;

  void report(BatteryStatus status) => state = status;
}

class _Shell {
  _Shell(String root, this.kernel) : battery = _Battery() {
    container = ProviderContainer(
      overrides: [
        bypassChargingServiceProvider.overrideWithValue(
          BypassChargingService(
            powerSupplyRoot: root,
            writeAttribute: kernel.write,
          ),
        ),
        batteryProvider.overrideWith(() => battery),
      ],
    );
    // The status bar's mark keeps the controller alive in the shell.
    container.listen(bypassChargingProvider, (_, _) {});
  }

  final _Kernel kernel;
  final _Battery battery;
  late final ProviderContainer container;

  BypassChargingState get state => container.read(bypassChargingProvider);
  BypassChargingController get controller =>
      container.read(bypassChargingProvider.notifier);

  /// The shade starts to open ([open]) or is closed.
  void shade({required bool open}) =>
      container.read(shadeProgressProvider).parent = open
      ? const AlwaysStoppedAnimation(0.2)
      : kAlwaysDismissedAnimation;

  /// Waits for the state to satisfy [test], as file reads land.
  Future<void> until(bool Function(BypassChargingState state) test) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!test(state)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the bypass charging state stayed $state');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void dispose() => container.dispose();
}

List<String> _captureLog() {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  addTearDown(() => debugPrint = previous);
  return lines;
}

FileSystemException _refused(String path, String message, int errno) =>
    FileSystemException('Cannot write', path, OSError(message, errno));

void main() {
  group('charge_behaviour', () {
    test('the bracketed behaviour is the selected one', () {
      expect(parseBypassCharging('[auto] inhibit-charge\n'), isFalse);
      expect(parseBypassCharging('auto [inhibit-charge]\n'), isTrue);
      expect(
        parseBypassCharging('auto inhibit-charge [force-discharge]'),
        isFalse,
      );
    });

    test('a battery that does not offer inhibit-charge has no bypass', () {
      expect(parseBypassCharging('[auto] force-discharge\n'), isNull);
      expect(parseBypassCharging('[auto]\n'), isNull);
      expect(parseBypassCharging(''), isNull);
    });
  });

  group('the service', () {
    test('finds the battery that offers bypass charging', () async {
      final root = await _sysfs({
        // A charger's attribute does not count.
        'usb': {'type': 'USB\n', 'charge_behaviour': '[auto] inhibit-charge'},
        'BAT0': {'type': 'Battery\n'},
        'BAT1': _battery('[auto] inhibit-charge\n'),
      });
      expect(await BypassChargingService(powerSupplyRoot: root).probe(), (
        attribute: '$root/BAT1/charge_behaviour',
        on: false,
      ));
    });

    test('reads bypass charging on', () async {
      final root = await _sysfs({'BAT1': _battery('auto [inhibit-charge]\n')});
      expect(
        (await BypassChargingService(powerSupplyRoot: root).probe())?.on,
        isTrue,
      );
    });

    test(
      'prefers the battery manager when several batteries offer it',
      () async {
        final root = await _sysfs({
          'BAT0': _battery('[auto] inhibit-charge\n'),
          'qcom-battmgr-bat': _battery('auto [inhibit-charge]\n'),
          'zz-battery': _battery('[auto] inhibit-charge\n'),
        });
        expect(
          (await BypassChargingService(
            powerSupplyRoot: root,
          ).probe())?.attribute,
          '$root/qcom-battmgr-bat/charge_behaviour',
        );
      },
    );

    test('offers nothing without such a battery', () async {
      final root = await _sysfs({
        'BAT0': _battery('[auto] force-discharge\n'),
        'ac': {'type': 'Mains\n', 'online': '1\n'},
      });
      expect(
        await BypassChargingService(powerSupplyRoot: root).probe(),
        isNull,
      );
      expect(
        await BypassChargingService(powerSupplyRoot: '$root/no-such-class')
            .probe(),
        isNull,
      );
    });

    test('offers nothing when this user cannot write the attribute', () async {
      final root = await _sysfs({'BAT1': _battery('[auto] inhibit-charge\n')});
      final attribute = '$root/BAT1/charge_behaviour';
      expect(Process.runSync('chmod', ['0444', attribute]).exitCode, 0);
      // The test runs as an ordinary user, whom the mode keeps out.
      expect(
        await BypassChargingService(powerSupplyRoot: root).probe(),
        isNull,
      );
      // The probe opened the attribute and wrote nothing.
      expect(await File(attribute).readAsString(), '[auto] inhibit-charge\n');
    });

    test('writes the bare behaviour with one plain write', () async {
      final root = await _sysfs({'BAT1': _battery('[auto] inhibit-charge\n')});
      final attribute = '$root/BAT1/charge_behaviour';
      final service = BypassChargingService(powerSupplyRoot: root);
      await service.write(attribute, true);
      expect(await File(attribute).readAsString(), 'inhibit-charge');
      await service.write(attribute, false);
      expect(await File(attribute).readAsString(), 'auto');
    });
  });

  group('the controller', () {
    test('switches bypass charging and reads it back', () async {
      final root = await _sysfs({
        'qcom-battmgr-bat': _battery('[auto] inhibit-charge\n'),
      });
      final shell = _Shell(root, _Kernel());
      addTearDown(shell.dispose);
      await shell.until((state) => state.available);
      expect(shell.state.on, isFalse);

      final switching = shell.controller.toggle();
      expect(shell.state.busy, isTrue);
      // A second tap while the first is written does nothing.
      await shell.controller.toggle();
      await switching;
      expect(shell.kernel.writes, ['inhibit-charge']);
      expect(
        await File('$root/qcom-battmgr-bat/charge_behaviour').readAsString(),
        'auto [inhibit-charge]\n',
      );
      expect(shell.state, const BypassChargingState(available: true, on: true));

      await shell.controller.toggle();
      expect(shell.kernel.writes, ['inhibit-charge', 'auto']);
      expect(
        shell.state,
        const BypassChargingState(available: true, on: false),
      );
    });

    test('offers nothing where no battery offers it', () async {
      final root = await _sysfs({'BAT0': _battery('[auto] force-discharge\n')});
      final shell = _Shell(root, _Kernel());
      addTearDown(shell.dispose);
      await shell.controller.refresh();
      expect(shell.state, const BypassChargingState());
      await shell.controller.toggle();
      expect(shell.kernel.writes, isEmpty);
    });

    test('follows a change made elsewhere when the shade opens and when '
        'the battery changes, and polls for nothing', () async {
      final root = await _sysfs({
        'qcom-battmgr-bat': _battery('[auto] inhibit-charge\n'),
      });
      final attribute = File('$root/qcom-battmgr-bat/charge_behaviour');
      final shell = _Shell(root, _Kernel());
      addTearDown(shell.dispose);
      await shell.until((state) => state.available);

      // Switched from a terminal, unseen until something looks again.
      await attribute.writeAsString('auto [inhibit-charge]\n');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(shell.state.on, isFalse);

      shell.shade(open: true);
      await shell.until((state) => state.on);

      // The charger is unplugged: the battery source reports it.
      shell.shade(open: false);
      await attribute.writeAsString('[auto] inhibit-charge\n');
      shell.battery.report(const BatteryStatus(capacity: 80, charging: false));
      await shell.until((state) => !state.on);
      expect(shell.kernel.writes, isEmpty);
    });

    for (final (message, errno) in const [
      ('Operation not supported', 95),
      ('Resource temporarily unavailable', 11),
      ('Permission denied', 13),
    ]) {
      test('a switch refused with errno $errno shows the tile unavailable '
          'until the shade opens again', () async {
        final log = _captureLog();
        final root = await _sysfs({
          'qcom-battmgr-bat': _battery('[auto] inhibit-charge\n'),
        });
        final attribute = '$root/qcom-battmgr-bat/charge_behaviour';
        final kernel = _Kernel()..refuse = _refused(attribute, message, errno);
        final shell = _Shell(root, kernel);
        addTearDown(shell.dispose);
        await shell.until((state) => state.available);

        await shell.controller.toggle();
        expect(
          shell.state,
          const BypassChargingState(available: true, on: false, failed: true),
        );
        expect(log, [
          'Bypass charging: writing inhibit-charge to $attribute failed: '
              'OS Error: $message, errno = $errno',
        ]);
        // Not tried again from the tile, nor cleared by a battery report.
        await shell.controller.toggle();
        shell.battery.report(const BatteryStatus(capacity: 80, charging: true));
        await shell.controller.refresh();
        expect(shell.state.failed, isTrue);
        expect(kernel.writes, ['inhibit-charge']);

        kernel.refuse = null;
        shell.shade(open: true);
        await shell.until((state) => !state.failed);
        await shell.controller.toggle();
        expect(
          shell.state,
          const BypassChargingState(available: true, on: true),
        );
        expect(kernel.writes, ['inhibit-charge', 'inhibit-charge']);
      });
    }
  });

  group('the tile', () {
    final taps = <void>[];
    setUp(taps.clear);

    Future<_FixedBypass> pumpTile(
      WidgetTester tester,
      BypassChargingState state,
    ) async {
      final bypass = _FixedBypass(state, taps);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bypassChargingProvider.overrideWith(() => bypass)],
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 128,
                  height: 107,
                  child: Consumer(
                    builder: (context, ref, _) =>
                        bypassChargingQuickTile(ref, context.l10n) ??
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return bypass;
    }

    QuickTile tile(WidgetTester tester) =>
        tester.widget<QuickTile>(find.byType(QuickTile));
    final l10n = AppLocalizationsEn();

    testWidgets('is absent where no battery offers bypass charging', (
      tester,
    ) async {
      await pumpTile(tester, const BypassChargingState());
      expect(find.byType(QuickTile), findsNothing);
    });

    testWidgets('shows the battery and switches it', (tester) async {
      final bypass = await pumpTile(
        tester,
        const BypassChargingState(available: true),
      );
      expect(tile(tester).title, l10n.quickSettingsBypassCharging);
      expect(tile(tester).icon, Icons.power_rounded);
      expect(tile(tester).active, isFalse);
      expect(tile(tester).enabled, isTrue);
      expect(tile(tester).subtitle, l10n.commonOff);

      await tester.tap(find.byType(QuickTile));
      expect(taps, hasLength(1));

      bypass.show(const BypassChargingState(available: true, busy: true));
      await tester.pump();
      expect(tile(tester).enabled, isFalse);
      expect(tile(tester).busy, isTrue);

      bypass.show(const BypassChargingState(available: true, on: true));
      await tester.pump();
      expect(tile(tester).active, isTrue);
      expect(tile(tester).enabled, isTrue);
      expect(tile(tester).subtitle, l10n.commonOn);
    });

    testWidgets('a refused switch shows the tile unavailable', (tester) async {
      await pumpTile(
        tester,
        const BypassChargingState(available: true, on: true, failed: true),
      );
      expect(tile(tester).enabled, isFalse);
      expect(tile(tester).subtitle, l10n.commonUnavailable);
      // It still shows what the battery reports.
      expect(tile(tester).active, isTrue);
    });

    test('is named in every language', () {
      expect(
        AppLocalizationsEn().quickSettingsBypassCharging,
        'Bypass charging',
      );
      expect(
        AppLocalizationsRu().quickSettingsBypassCharging,
        'Обходная зарядка',
      );
      expect(AppLocalizationsZh().quickSettingsBypassCharging, '旁路充电');
    });
  });
}

/// A controller that holds the state the test shows and counts taps.
class _FixedBypass extends BypassChargingController {
  _FixedBypass(this._initial, this._taps);

  final BypassChargingState _initial;
  final List<void> _taps;

  @override
  BypassChargingState build() => _initial;

  @override
  Future<void> toggle() async => _taps.add(null);

  void show(BypassChargingState next) => state = next;
}
