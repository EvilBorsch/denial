import 'dart:async';
import 'dart:convert';

import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/settings.dart';

/// deniald's side of the shared settings document: a revisioned store that
/// pushes every new revision to the shell, the first one on subscription.
/// [publish] stands for an edit that reaches deniald from outside the shell,
/// an edited settings.json or a settings.document.apply on its control
/// socket.
class LiveSettingsTransport
    implements SettingsDocumentTransport, SettingsDocumentUpdateSource {
  LiveSettingsTransport([Map<String, Object?> sections = const {}])
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

  /// The written document, decoded.
  Map<String, dynamic> get decoded =>
      jsonDecode(document) as Map<String, dynamic>;

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
