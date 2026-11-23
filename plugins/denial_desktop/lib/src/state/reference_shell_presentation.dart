import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart'
    show displayLayoutProvider, inputDeviceCapabilitiesProvider;

import 'reference_shell_profile.dart';

/// Scene selection, independent of startup/security policy. Each scene's
/// input publisher also selects its native window-geometry policy.
final referenceShellPresentationProvider =
    NotifierProvider<ReferenceShellPresentation, ReferenceShellProfile>(
      ReferenceShellPresentation.new,
    );

/// Whether the session shows on one screen; null until deniald reported its
/// screens. Only then is the presentation a choice (the Desktop view tile)
/// that follows the keyboard: a monitor beside the tablet carries the
/// desktop shell itself.
final singleScreenSessionProvider = Provider<bool?>((ref) {
  final outputs = ref.watch(
    displayLayoutProvider.select((layout) => layout?.outputs.length),
  );
  return outputs == null ? null : outputs <= 1;
});

/// The presentation of a single screen: the tablet's (mobile) or the
/// desktop's.
///
/// It follows a physical keyboard ([ShellPresentationSettings.followKeyboard],
/// on unless switched off): attaching one, the cover, USB or Bluetooth,
/// brings up the desktop, and detaching the last one the tablet. Virtual
/// keyboards, such as a test tool's, do not count. The Desktop view tile, or
/// the dashboard's button, switches by hand, and that choice holds until the
/// next attach or detach. With a monitor beside the tablet nothing switches
/// on its own.
///
/// The shell starts in the presentation it showed last, kept in the settings
/// document with whether a keyboard was attached when it was chosen. While
/// following the keyboard, the device list then corrects it once if a
/// keyboard was attached or detached in between.
class ReferenceShellPresentation extends Notifier<ReferenceShellProfile> {
  /// How long the last physical keyboard must stay away before the tablet
  /// presentation follows. The cover's driver (`oneplus-pogo-keyboard`)
  /// switches a keyboard that went silent off and on again, which takes
  /// about two seconds, when it is folded behind the tablet or missed its
  /// wake-up: that must not flip the presentation there and back.
  static const Duration detachGrace = Duration(seconds: 3);

  Timer? _detach;

  /// The physical keyboard the presentation follows: an attach counts at
  /// once, a detach after [detachGrace]. Null until deniald reported its
  /// devices.
  bool? _keyboard;

  /// Whether a physical keyboard was attached when the presentation shown
  /// was chosen; null when that is not known.
  bool? _chosenWithKeyboard;

  /// The settings arrived and the presentation chosen last was restored.
  var _restored = false;

  /// The device list and the screens arrived after that, and corrected the
  /// start.
  var _settled = false;

  var _persistScheduled = false;

  @override
  ReferenceShellProfile build() {
    _detach?.cancel();
    _detach = null;
    _keyboard = null;
    _chosenWithKeyboard = null;
    _restored = false;
    _settled = false;
    _persistScheduled = false;
    ref.onDispose(() {
      _detach?.cancel();
      _detach = null;
    });
    ref.listen<bool>(
      shellSettingsSyncStatusProvider.select(
        (status) => status.phase != ShellSettingsSyncPhase.loading,
      ),
      (_, known) {
        if (known) _catchUp();
      },
    );
    ref.listen<bool?>(
      inputDeviceCapabilitiesProvider.select(
        (devices) => devices.capabilities.revision > 0
            ? devices.capabilities.hasPhysicalKeyboard
            : null,
      ),
      (_, present) => _keyboardReported(present),
    );
    ref.listen<bool>(
      shellSettingsProvider.select(
        (settings) => settings.presentation.followKeyboard,
      ),
      _followKeyboardChanged,
    );
    ref.listen<ShellPresentationMode?>(
      shellSettingsProvider.select((settings) => settings.presentation.mode),
      _modeChanged,
    );
    ref.listen<bool?>(singleScreenSessionProvider, _singleScreenChanged);
    // What is known already, after this build: a provider may not change
    // the settings while it builds.
    scheduleMicrotask(_catchUp);
    return ref.read(referenceShellProfileProvider);
  }

  /// Switches by hand: the tile, the dashboard's button. It holds until the
  /// next attach or detach of a keyboard.
  void toggle() {
    if (_detach != null) {
      // The keyboard is gone already; the choice comes after that.
      _detach!.cancel();
      _detach = null;
      _keyboard = false;
    }
    _chosenWithKeyboard = _keyboard;
    _show(
      state == ReferenceShellProfile.desktop
          ? ReferenceShellProfile.mobile
          : ReferenceShellProfile.desktop,
    );
  }

  ShellPresentationSettings get _settings =>
      ref.read(shellSettingsProvider).presentation;

  bool get _settingsKnown =>
      ref.read(shellSettingsSyncStatusProvider).phase !=
      ShellSettingsSyncPhase.loading;

  bool? get _reportedKeyboard {
    final devices = ref.read(inputDeviceCapabilitiesProvider).capabilities;
    return devices.revision > 0 ? devices.hasPhysicalKeyboard : null;
  }

  /// Takes in whatever of the settings, the device list and the screens has
  /// arrived.
  void _catchUp() {
    if (!ref.mounted) return;
    if (!_restored && _settingsKnown) _restore();
    if (!_settled) {
      _keyboard ??= _reportedKeyboard;
      if (_restored &&
          _keyboard != null &&
          ref.read(singleScreenSessionProvider) != null) {
        _settle();
      }
    }
  }

  /// The settings arrived: the presentation chosen last, before the device
  /// list tells whether its keyboard is still there.
  void _restore() {
    _restored = true;
    final settings = _settings;
    _chosenWithKeyboard = settings.modeKeyboard;
    final mode = settings.mode;
    if (mode != null) state = _profileOf(mode);
  }

  /// The settings, the device list and the screens are known: a keyboard
  /// attached or detached since the presentation was chosen decides it,
  /// once.
  void _settle() {
    _settled = true;
    if (!_follow()) _persist();
  }

  void _keyboardReported(bool? present) {
    if (present == null) return;
    if (!_settled) {
      // Before the start is settled the report stands as it is: the first
      // one is the state the session starts with.
      _keyboard = present;
      _catchUp();
      return;
    }
    if (present) {
      _detach?.cancel();
      _detach = null;
      if (_keyboard != true) {
        _keyboard = true;
        _follow();
      }
      return;
    }
    if (_keyboard == false || _detach != null) return;
    _detach = Timer(detachGrace, () {
      _detach = null;
      _keyboard = false;
      _follow();
    });
  }

  /// Turned on, following the keyboard applies at once.
  void _followKeyboardChanged(bool? previous, bool follow) {
    if (!_settled || previous != false || !follow) return;
    _follow(always: true);
  }

  /// A presentation set from outside the shell, through Denial's settings
  /// channel or an edited settings file, is a choice by hand.
  void _modeChanged(
    ShellPresentationMode? previous,
    ShellPresentationMode? mode,
  ) {
    if (!_restored || mode == null || mode == _modeOf(state)) return;
    _chosenWithKeyboard = _keyboard;
    _show(_profileOf(mode));
  }

  /// Back to one screen: a keyboard attached or detached while a monitor
  /// was in decides, as at a start.
  void _singleScreenChanged(bool? previous, bool? single) {
    if (!_settled) {
      _catchUp();
      return;
    }
    if (previous == false && single == true) _follow();
  }

  /// Shows what the keyboard asks for, when the presentation follows it and
  /// the keyboard changed since the presentation was chosen ([always]: even
  /// if not). Returns whether it decided.
  bool _follow({bool always = false}) {
    final keyboard = _keyboard;
    if (keyboard == null ||
        !_settings.followKeyboard ||
        ref.read(singleScreenSessionProvider) != true ||
        (!always && keyboard == _chosenWithKeyboard)) {
      return false;
    }
    _chosenWithKeyboard = keyboard;
    _show(
      keyboard ? ReferenceShellProfile.desktop : ReferenceShellProfile.mobile,
    );
    return true;
  }

  void _show(ReferenceShellProfile presentation) {
    state = presentation;
    _persist();
  }

  /// Keeps the presentation shown for the next start. Nothing is written
  /// before the settings arrived: the presentation kept there comes first.
  /// The write goes out after the change that asked for it, which may be
  /// one of the settings themselves.
  void _persist() {
    if (!_restored || _persistScheduled) return;
    _persistScheduled = true;
    scheduleMicrotask(() {
      _persistScheduled = false;
      if (!ref.mounted) return;
      ref
          .read(shellSettingsProvider.notifier)
          .recordPresentation(_modeOf(state), keyboard: _chosenWithKeyboard);
    });
  }

  static ReferenceShellProfile _profileOf(ShellPresentationMode mode) =>
      switch (mode) {
        ShellPresentationMode.tablet => ReferenceShellProfile.mobile,
        ShellPresentationMode.desktop => ReferenceShellProfile.desktop,
      };

  static ShellPresentationMode _modeOf(ReferenceShellProfile profile) =>
      switch (profile) {
        ReferenceShellProfile.mobile => ShellPresentationMode.tablet,
        ReferenceShellProfile.desktop => ShellPresentationMode.desktop,
      };
}

/// Native geometry supplies the mobile status strip for either startup profile.
final mobilePresentationTopInsetProvider = Provider<double>((ref) => 0.0);
