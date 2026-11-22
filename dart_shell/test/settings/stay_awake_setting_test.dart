import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';

void main() {
  test(
    'an edited settings document turns Stay awake on in the shell',
    () async {
      final transport = LiveSettingsTransport();
      final container = _container(transport);
      await pumpEventQueue();
      expect(container.read(shellSettingsProvider).power.stayAwake, isFalse);

      // deniald pushes the document again after an edit of settings.json or a
      // settings.document.apply on its control socket.
      transport.publish(<String, Object?>{
        'power': <String, Object?>{
          'idleSuspendEnabled': true,
          'stayAwake': true,
        },
      });
      await pumpEventQueue();

      final power = container.read(shellSettingsProvider).power;
      expect(power.stayAwake, isTrue);
      expect(power.idleSuspendEnabled, isTrue);
      expect(power.idleSuspendActive, isFalse);
    },
  );

  test('switching Stay awake writes only its key and keeps the rest', () async {
    final transport = LiveSettingsTransport(<String, Object?>{
      'power': <String, Object?>{'idleSuspendEnabled': true, 'stayAwake': true},
      'pluginPreferences': <String, Object?>{'pets': 3},
    });
    final container = _container(transport);
    await pumpEventQueue();
    expect(container.read(shellSettingsProvider).power.stayAwake, isTrue);

    container.read(shellSettingsProvider.notifier).setStayAwake(false);
    expect(container.read(shellSettingsProvider).power.stayAwake, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final written = transport.decoded;
    final power = written['power'] as Map<String, dynamic>;
    expect(power['stayAwake'], isFalse);
    expect(power['idleSuspendEnabled'], isTrue);
    expect(written['pluginPreferences'], <String, Object?>{'pets': 3});
    expect(transport.writes, 1);
  });
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
