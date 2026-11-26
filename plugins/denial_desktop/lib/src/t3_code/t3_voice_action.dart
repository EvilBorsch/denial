import 'dart:async';

import 'package:denial_flutter_sdk/actions.dart';
import 'package:flutter/widgets.dart';

/// Toggles T3 Code voice dictation. `deniald` queues this action when the user
/// double-presses Volume Down while the screen is awake and unlocked.
final class T3VoiceToggleAction implements ShellAction {
  const T3VoiceToggleAction(this._toggle);

  /// `deniald`'s constant `T3_VOICE_TOGGLE_ACTION`.
  static const String actionId = 'denial_desktop.t3VoiceToggle';

  final VoidCallback _toggle;

  @override
  String get id => actionId;

  @override
  String get provider => 'T3 Code';

  @override
  String label(BuildContext context) => 'T3 Code голосовой запрос';

  @override
  String description(BuildContext context) =>
      'Начать или отправить голосовой запрос в T3 Code';

  @override
  FutureOr<void> invoke(ShellActionContext context) {
    _toggle();
  }
}
