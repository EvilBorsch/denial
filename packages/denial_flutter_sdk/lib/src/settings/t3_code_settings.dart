import 'package:flutter/foundation.dart';

/// Default repository for EvilBorsch's T3 Code fork.
const String defaultT3CodeRepoUrl = 'https://github.com/EvilBorsch/t3code.git';

/// Default branch tracked for T3 Code installs and updates.
const String defaultT3CodeBranch = 'main';

/// Default Russian local speech model inside T3 Code (GigaAM v3 E2E RNNT).
const String defaultT3CodeVoiceModelId = 'handy-computer/gigaam-v3-e2e-rnnt-gguf';

/// System integration settings for T3 Code (voice dictation, Search AI,
/// Dynamic Island activity bubble, and model/harness defaults).
@immutable
class ShellT3CodeSettings {
  const ShellT3CodeSettings({
    this.enabled = true,
    this.installDir = '',
    this.repoUrl = defaultT3CodeRepoUrl,
    this.branch = defaultT3CodeBranch,
    this.providerInstanceId = '',
    this.providerDriver = '',
    this.model = '',
    this.workspaceRoot = '~',
    this.voiceModelId = defaultT3CodeVoiceModelId,
    this.volumeDownDoublePress = true,
  });

  /// Enables T3 Code voice/text triggers and the Dynamic Island bubble.
  final bool enabled;

  /// Optional override for the T3 Code installation root. Empty uses
  /// `~/.local/share/t3code-evilborsch`.
  final String installDir;

  /// Git repository URL for installing or updating T3 Code.
  final String repoUrl;

  /// Git branch for installing or updating T3 Code.
  final String branch;

  /// Preferred T3 Code provider instance (harness) ID, e.g. `antigravity`,
  /// `claudeAgent`, `codex`. Empty picks the first enabled ready provider.
  final String providerInstanceId;

  /// Driver kind matching [providerInstanceId], e.g. `antigravity`.
  final String providerDriver;

  /// Preferred model slug within the chosen harness. Empty uses the harness's
  /// default model.
  final String model;

  /// Working directory for threads started from Denial (defaults to `~`).
  final String workspaceRoot;

  /// Local speech-to-text model ID in T3 Code (defaults to GigaAM Russian).
  final String voiceModelId;

  /// Double-pressing Volume Down while awake toggles T3 voice dictation.
  final bool volumeDownDoublePress;

  ShellT3CodeSettings copyWith({
    bool? enabled,
    String? installDir,
    String? repoUrl,
    String? branch,
    String? providerInstanceId,
    String? providerDriver,
    String? model,
    String? workspaceRoot,
    String? voiceModelId,
    bool? volumeDownDoublePress,
  }) {
    return ShellT3CodeSettings(
      enabled: enabled ?? this.enabled,
      installDir: installDir ?? this.installDir,
      repoUrl: repoUrl ?? this.repoUrl,
      branch: branch ?? this.branch,
      providerInstanceId: providerInstanceId ?? this.providerInstanceId,
      providerDriver: providerDriver ?? this.providerDriver,
      model: model ?? this.model,
      workspaceRoot: workspaceRoot ?? this.workspaceRoot,
      voiceModelId: voiceModelId ?? this.voiceModelId,
      volumeDownDoublePress:
          volumeDownDoublePress ?? this.volumeDownDoublePress,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'enabled': enabled,
    'installDir': installDir,
    'repoUrl': repoUrl,
    'branch': branch,
    'providerInstanceId': providerInstanceId,
    'providerDriver': providerDriver,
    'model': model,
    'workspaceRoot': workspaceRoot,
    'voiceModelId': voiceModelId,
    'volumeDownDoublePress': volumeDownDoublePress,
  };

  factory ShellT3CodeSettings.fromJson(Object? value) {
    const defaults = ShellT3CodeSettings();
    if (value is! Map) {
      return defaults;
    }
    String cleanString(Object? raw, String fallback, {int maxLen = 512}) {
      if (raw is! String) return fallback;
      final trimmed = raw.trim();
      if (trimmed.length > maxLen || trimmed.contains('\u0000')) {
        return fallback;
      }
      return trimmed;
    }

    return ShellT3CodeSettings(
      enabled: value['enabled'] is bool
          ? value['enabled'] as bool
          : defaults.enabled,
      installDir: cleanString(value['installDir'], defaults.installDir),
      repoUrl: cleanString(
        value['repoUrl'],
        defaults.repoUrl,
      ).isEmpty
          ? defaults.repoUrl
          : cleanString(value['repoUrl'], defaults.repoUrl),
      branch: cleanString(
        value['branch'],
        defaults.branch,
        maxLen: 128,
      ).isEmpty
          ? defaults.branch
          : cleanString(value['branch'], defaults.branch, maxLen: 128),
      providerInstanceId: cleanString(
        value['providerInstanceId'],
        defaults.providerInstanceId,
        maxLen: 128,
      ),
      providerDriver: cleanString(
        value['providerDriver'],
        defaults.providerDriver,
        maxLen: 128,
      ),
      model: cleanString(value['model'], defaults.model, maxLen: 256),
      workspaceRoot: cleanString(
        value['workspaceRoot'],
        defaults.workspaceRoot,
      ).isEmpty
          ? defaults.workspaceRoot
          : cleanString(value['workspaceRoot'], defaults.workspaceRoot),
      voiceModelId: cleanString(
        value['voiceModelId'],
        defaults.voiceModelId,
        maxLen: 256,
      ).isEmpty
          ? defaults.voiceModelId
          : cleanString(
              value['voiceModelId'],
              defaults.voiceModelId,
              maxLen: 256,
            ),
      volumeDownDoublePress: value['volumeDownDoublePress'] is bool
          ? value['volumeDownDoublePress'] as bool
          : defaults.volumeDownDoublePress,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShellT3CodeSettings &&
        other.enabled == enabled &&
        other.installDir == installDir &&
        other.repoUrl == repoUrl &&
        other.branch == branch &&
        other.providerInstanceId == providerInstanceId &&
        other.providerDriver == providerDriver &&
        other.model == model &&
        other.workspaceRoot == workspaceRoot &&
        other.voiceModelId == voiceModelId &&
        other.volumeDownDoublePress == volumeDownDoublePress;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    installDir,
    repoUrl,
    branch,
    providerInstanceId,
    providerDriver,
    model,
    workspaceRoot,
    voiceModelId,
    volumeDownDoublePress,
  );
}
