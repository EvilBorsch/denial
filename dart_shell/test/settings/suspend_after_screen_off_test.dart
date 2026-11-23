import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';

// Sleep after the screen turns off: a timeout of its own, which the display
// and lock timeouts no longer drag along, written under its own key.
void main() {
  test(
    'the display timeout leaves sleep after the screen turns off alone',
    () async {
      final transport = LiveSettingsTransport(<String, Object?>{
        'power': <String, Object?>{
          'idleDpmsTimeoutSeconds': 600,
          'idleSuspendEnabled': true,
          'idleSuspendTimeoutSeconds': 300,
          'idleSuspendAfterScreenOffSeconds': 300,
        },
      });
      final container = _container(transport);
      await pumpEventQueue();
      final settings = container.read(shellSettingsProvider.notifier);

      settings.setIdleDpmsTimeoutSeconds(1800);
      var power = container.read(shellSettingsProvider).power;
      expect(power.idleDpmsTimeoutSeconds, 1800);
      expect(power.idleSuspendAfterScreenOffSeconds, 300);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      var written = transport.decoded['power'] as Map<String, dynamic>;
      expect(written['idleDpmsTimeoutSeconds'], 1800);
      expect(written['idleSuspendAfterScreenOffSeconds'], 300);
      // An older Denial's key is left as it was.
      expect(written['idleSuspendTimeoutSeconds'], 300);

      settings.setIdleSuspendAfterScreenOffSeconds(60);
      power = container.read(shellSettingsProvider).power;
      expect(power.idleSuspendAfterScreenOffSeconds, 60);
      expect(power.idleDpmsTimeoutSeconds, 1800);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      written = transport.decoded['power'] as Map<String, dynamic>;
      expect(written['idleSuspendAfterScreenOffSeconds'], 60);
      expect(written['idleDpmsTimeoutSeconds'], 1800);
      expect(written['idleSuspendEnabled'], isTrue);
    },
  );

  test(
    'the lock timeout is not held under sleep after the screen turns off',
    () async {
      final transport = LiveSettingsTransport(<String, Object?>{
        'power': <String, Object?>{'idleSuspendAfterScreenOffSeconds': 60},
      });
      final container = _container(transport);
      await pumpEventQueue();
      final settings = container.read(shellSettingsProvider.notifier);

      settings.setIdleLockTimeoutSeconds(5400);
      expect(
        container.read(shellSettingsProvider).power.idleLockTimeoutSeconds,
        5400,
      );
      settings.setIdleSuspendAfterScreenOffSeconds(30);
      final power = container.read(shellSettingsProvider).power;
      expect(power.idleSuspendAfterScreenOffSeconds, 30);
      expect(power.idleLockTimeoutSeconds, 5400);
      // Within the shared bounds: half a minute to two hours.
      settings.setIdleSuspendAfterScreenOffSeconds(5);
      expect(
        container
            .read(shellSettingsProvider)
            .power
            .idleSuspendAfterScreenOffSeconds,
        30,
      );
      settings.setIdleSuspendAfterScreenOffSeconds(99999);
      expect(
        container
            .read(shellSettingsProvider)
            .power
            .idleSuspendAfterScreenOffSeconds,
        7200,
      );
    },
  );
}

ProviderContainer _container(LiveSettingsTransport transport) {
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWithValue(NativeSettingsStore(transport)),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.close);
  container.listen(shellSettingsProvider, (_, _) {});
  return container;
}
