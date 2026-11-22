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

Future<LiveSettingsTransport> _pump(WidgetTester tester, Widget child) async {
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
  return transport;
}

/// deniald pushes a document with Stay awake [on]: the setting changes at
/// once and the bar shows it from the next frame.
Future<void> _stayAwake(
  WidgetTester tester,
  LiveSettingsTransport transport,
  bool on,
) async {
  transport.publish(<String, Object?>{
    'power': <String, Object?>{'stayAwake': on},
  });
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the status mark shows while Stay awake is on', (tester) async {
    final semantics = tester.ensureSemantics();
    final l10n = AppLocalizationsEn();
    final transport = await _pump(tester, const StayAwakeMark(scale: 2));

    expect(find.byIcon(Icons.coffee_rounded), findsNothing);
    expect(tester.getSize(find.byType(StayAwakeMark)), Size.zero);

    await _stayAwake(tester, transport, true);
    expect(find.byIcon(Icons.coffee_rounded), findsOneWidget);
    expect(
      find.bySemanticsLabel(l10n.quickSettingsStayAwakeOn),
      findsOneWidget,
    );
    // The icon and the gap after it grow with the bar.
    expect(tester.getSize(find.byType(StayAwakeMark)), const Size(54, 36));

    await _stayAwake(tester, transport, false);
    expect(find.byIcon(Icons.coffee_rounded), findsNothing);
    expect(find.bySemanticsLabel(l10n.quickSettingsStayAwakeOn), findsNothing);
    semantics.dispose();
  });

  testWidgets('the status cluster leads with the mark', (tester) async {
    final transport = await _pump(
      tester,
      const StatusCluster(
        battery: BatteryStatus(capacity: 64, charging: false),
      ),
    );
    expect(find.byIcon(Icons.coffee_rounded), findsNothing);

    await _stayAwake(tester, transport, true);
    expect(
      find.descendant(
        of: find.byType(StatusCluster),
        matching: find.byIcon(Icons.coffee_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopRight(find.byIcon(Icons.coffee_rounded)).dx,
      lessThan(tester.getTopLeft(find.byType(MobileConnectivityMarks)).dx),
    );
  });
}
