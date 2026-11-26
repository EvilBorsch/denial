import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ShellT3CodeSettings defaults and JSON round-trip', () {
    const defaults = ShellT3CodeSettings();
    expect(defaults.enabled, isTrue);
    expect(defaults.branch, 'main');
    expect(defaults.workspaceRoot, '~');
    expect(defaults.volumeDownDoublePress, isTrue);
    expect(defaults.voiceModelId, contains('gigaam'));

    final custom = defaults.copyWith(
      enabled: false,
      providerInstanceId: 'codex-1',
      providerDriver: 'codex',
      model: 'gpt-5.4',
      volumeDownDoublePress: false,
    );
    final decoded = ShellT3CodeSettings.fromJson(custom.toJson());
    expect(decoded, custom);

    final settings = const ShellSettings().copyWith(t3Code: custom);
    final roundTripped = ShellSettings.fromJson(settings.toJson());
    expect(roundTripped.t3Code, custom);
  });
}
