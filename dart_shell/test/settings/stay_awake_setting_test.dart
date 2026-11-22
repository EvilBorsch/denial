import 'dart:async';
import 'dart:convert';

import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an edited settings document turns Stay awake on in the shell',
    () async {
      final transport = _LiveSettingsTransport();
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
    final transport = _LiveSettingsTransport(<String, Object?>{
      'power': <String, Object?>{'idleSuspendEnabled': true, 'stayAwake': true},
      'pluginPreferences': <String, Object?>{'pets': 3},
    });
    final container = _container(transport);
    await pumpEventQueue();
    expect(container.read(shellSettingsProvider).power.stayAwake, isTrue);

    container.read(shellSettingsProvider.notifier).setStayAwake(false);
    expect(container.read(shellSettingsProvider).power.stayAwake, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final written = jsonDecode(transport.document) as Map<String, dynamic>;
    final power = written['power'] as Map<String, dynamic>;
    expect(power['stayAwake'], isFalse);
    expect(power['idleSuspendEnabled'], isTrue);
    expect(written['pluginPreferences'], <String, Object?>{'pets': 3});
    expect(transport.writes, 1);
  });
}

ProviderContainer _container(_LiveSettingsTransport transport) {
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

/// deniald's side of the shared document: a revisioned store that pushes
/// every new revision to the shell, the first one on subscription.
class _LiveSettingsTransport
    implements SettingsDocumentTransport, SettingsDocumentUpdateSource {
  _LiveSettingsTransport([Map<String, Object?> sections = const {}])
    : document = _encode(sections);

  int revision = 1;
  String document;
  int writes = 0;
  late final StreamController<DenialSettingsDocument> _updates =
      StreamController<DenialSettingsDocument>.broadcast(
        onListen: () => _updates.add(_current),
      );

  DenialSettingsDocument get _current =>
      DenialSettingsDocument(revision: revision, json: document);

  static String _encode(Map<String, Object?> sections) {
    final base = const ShellSettings().toJson();
    for (final MapEntry(:key, :value) in sections.entries) {
      final current = base[key];
      base[key] = current is Map && value is Map
          ? <String, Object?>{...current, ...value}
          : value!;
    }
    return '${jsonEncode(base)}\n';
  }

  void publish(Map<String, Object?> sections) {
    revision += 1;
    document = _encode(sections);
    _updates.add(_current);
  }

  Future<void> close() => _updates.close();

  @override
  Stream<DenialSettingsDocument> get settingsDocumentUpdates => _updates.stream;

  @override
  Future<DenialSettingsDocument> read() async => _current;

  @override
  Future<DenialSettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    if (expectedRevision != revision) {
      throw StateError('settings revision conflict');
    }
    writes += 1;
    revision += 1;
    this.document = document;
    return _current;
  }
}
