import 'package:denial_desktop/src/widgets/shade/quick_settings_tiles.dart';
import 'package:denial_desktop/src/widgets/shade/stay_awake_tile.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';

void main() {
  testWidgets('the tile switches Stay awake and follows the setting', (
    tester,
  ) async {
    final transport = LiveSettingsTransport(<String, Object?>{
      'power': <String, Object?>{'idleSuspendEnabled': true},
    });
    addTearDown(transport.close);
    final l10n = AppLocalizationsEn();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(
            NativeSettingsStore(transport),
          ),
        ],
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
                      stayAwakeQuickTile(ref, context.l10n),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    QuickTile tile() => tester.widget<QuickTile>(find.byType(QuickTile));

    // The document has not arrived: the tile cannot tell on from off.
    expect(tile().title, l10n.quickSettingsStayAwake);
    expect(tile().icon, Icons.coffee_rounded);
    expect(tile().enabled, isFalse);
    expect(tile().subtitle, l10n.commonLoading);

    await tester.pump();
    expect(tile().enabled, isTrue);
    expect(tile().active, isFalse);
    expect(tile().subtitle, l10n.commonOff);

    await tester.tap(find.byType(QuickTile));
    await tester.pump();
    expect(tile().active, isTrue);
    expect(tile().subtitle, l10n.commonOn);
    // The switch is persisted like every other setting, beside the owner's
    // idle suspend choice, which it leaves alone.
    await tester.pump(const Duration(milliseconds: 400));
    final power = transport.decoded['power'] as Map<String, dynamic>;
    expect(power['stayAwake'], isTrue);
    expect(power['idleSuspendEnabled'], isTrue);
    expect(transport.writes, 1);

    // Switched off from outside the shell, the tile follows.
    transport.publish(<String, Object?>{
      'power': <String, Object?>{
        'idleSuspendEnabled': true,
        'stayAwake': false,
      },
    });
    await tester.pump();
    expect(tile().active, isFalse);
    expect(tile().subtitle, l10n.commonOff);

    await tester.tap(find.byType(QuickTile));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tile().active, isTrue);
    expect(
      (transport.decoded['power'] as Map<String, dynamic>)['stayAwake'],
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
