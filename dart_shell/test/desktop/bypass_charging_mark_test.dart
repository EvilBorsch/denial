import 'package:denial_desktop/src/state/bypass_charging.dart';
import 'package:denial_desktop/src/widgets/shade/status_glyphs.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/system_services.dart';
import 'package:denial_sdk/system.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';

// No real network services or SIM reads are used.
class _NoNetwork extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() => NetworkConnectivityState.initial();
}

/// Bypass charging as the test shows it: offered and off at first.
class _Bypass extends BypassChargingController {
  @override
  BypassChargingState build() => const BypassChargingState(available: true);

  void show(BypassChargingState next) => state = next;
}

Future<(_Bypass, LiveSettingsTransport)> _pump(
  WidgetTester tester,
  Widget child,
) async {
  final bypass = _Bypass();
  final transport = LiveSettingsTransport();
  addTearDown(transport.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(NativeSettingsStore(transport)),
        networkConnectivityProvider.overrideWith(_NoNetwork.new),
        mobileNetworkProvider.overrideWith(
          (ref) => const Stream<MobileNetworkSnapshot>.empty(),
        ),
        bypassChargingProvider.overrideWith(() => bypass),
      ],
      child: DenialLocalizationScope(
        locale: const Locale('en'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  return (bypass, transport);
}

void main() {
  testWidgets('the status mark shows while Bypass charging is on', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final l10n = AppLocalizationsEn();
    final (bypass, _) = await _pump(tester, const BypassChargingMark(scale: 2));

    expect(find.byIcon(Icons.power_rounded), findsNothing);
    expect(tester.getSize(find.byType(BypassChargingMark)), Size.zero);

    bypass.show(const BypassChargingState(available: true, on: true));
    await tester.pump();
    expect(find.byIcon(Icons.power_rounded), findsOneWidget);
    expect(
      find.bySemanticsLabel(l10n.quickSettingsBypassChargingOn),
      findsOneWidget,
    );
    // The icon and the gap after it grow with the bar.
    expect(tester.getSize(find.byType(BypassChargingMark)), const Size(54, 36));

    // A refused switch leaves bypass on, as the battery reports it.
    bypass.show(
      const BypassChargingState(available: true, on: true, failed: true),
    );
    await tester.pump();
    expect(find.byIcon(Icons.power_rounded), findsOneWidget);

    bypass.show(const BypassChargingState(available: true));
    await tester.pump();
    expect(find.byIcon(Icons.power_rounded), findsNothing);
    expect(
      find.bySemanticsLabel(l10n.quickSettingsBypassChargingOn),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('the status cluster shows it after Stay awake, before the '
      'connectivity marks', (tester) async {
    final (bypass, transport) = await _pump(
      tester,
      const StatusCluster(
        battery: BatteryStatus(capacity: 64, charging: false),
      ),
    );
    expect(find.byIcon(Icons.power_rounded), findsNothing);

    bypass.show(const BypassChargingState(available: true, on: true));
    transport.publish(<String, Object?>{
      'power': <String, Object?>{'stayAwake': true},
    });
    await tester.pump();
    await tester.pump();
    final plug = find.descendant(
      of: find.byType(StatusCluster),
      matching: find.byIcon(Icons.power_rounded),
    );
    expect(plug, findsOneWidget);
    expect(
      tester.getTopRight(find.byIcon(Icons.coffee_rounded)).dx,
      lessThan(tester.getTopLeft(plug).dx),
    );
    expect(
      tester.getTopRight(plug).dx,
      lessThan(tester.getTopLeft(find.byType(MobileConnectivityMarks)).dx),
    );
  });

  test('the mark is spoken in every language', () {
    expect(
      AppLocalizationsEn().quickSettingsBypassChargingOn,
      'Bypass charging is on',
    );
    expect(
      AppLocalizationsRu().quickSettingsBypassChargingOn,
      'Обходная зарядка включена',
    );
    expect(AppLocalizationsZh().quickSettingsBypassChargingOn, '旁路充电已开启');
  });
}
