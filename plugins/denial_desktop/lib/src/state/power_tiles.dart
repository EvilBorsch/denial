import 'dart:async';

import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/session/power_session_surface.dart';
import '../widgets/shade/shade_progress.dart';
import 'reference_shell_controller.dart';

/// What the Screen off and Sleep tiles of the quick settings are doing.
@immutable
class PowerTilesState {
  const PowerTilesState({
    this.screenOffPending = false,
    this.sleepPending = false,
  });

  /// The shade is closing; the screen goes dark once it is shut.
  final bool screenOffPending;

  /// logind is being asked to suspend.
  final bool sleepPending;

  PowerTilesState copyWith({bool? screenOffPending, bool? sleepPending}) =>
      PowerTilesState(
        screenOffPending: screenOffPending ?? this.screenOffPending,
        sleepPending: sleepPending ?? this.sleepPending,
      );

  @override
  bool operator ==(Object other) =>
      other is PowerTilesState &&
      other.screenOffPending == screenOffPending &&
      other.sleepPending == sleepPending;

  @override
  int get hashCode => Object.hash(screenOffPending, sleepPending);
}

final powerTilesProvider =
    NotifierProvider<PowerTilesController, PowerTilesState>(
      PowerTilesController.new,
    );

/// The Screen off and Sleep tiles. Neither adds a path of its own to the
/// compositor or to logind: Screen off is the display power request a
/// double tap on the home screen sends, Sleep the suspend of the power
/// controls.
class PowerTilesController extends Notifier<PowerTilesState> {
  /// The longest Screen off waits for the shade to close.
  static const shadeCloseTimeout = Duration(seconds: 1);

  @override
  PowerTilesState build() => const PowerTilesState();

  /// Turns the screen off as a short press of the power button does. The
  /// shade closes first; once it is shut, deniald darkens the screen and
  /// locks as it does for the button (at once, or after the screen-off
  /// delay). Under Stay awake it darkens the screen without locking. Nothing
  /// suspends: the idle timeout does, later, as usual.
  Future<void> screenOff() async {
    if (state.screenOffPending) return;
    state = state.copyWith(screenOffPending: true);
    final shell = ref.read(referenceShellProvider.notifier);
    shell.closeQuickSettings();
    await _shadeClosed();
    if (!ref.mounted) return;
    state = state.copyWith(screenOffPending: false);
    shell.blankDisplays();
  }

  /// Suspends the system now through logind, as the power controls'
  /// Suspend does, also while Stay awake is on: Stay awake holds off only
  /// what happens on its own. deniald's sleep delay inhibitor locks the
  /// session before the system sleeps, so it wakes locked. The shade closes
  /// once logind takes the request.
  ///
  /// A suspend logind would refuse, or refuses, is not lost in silence: the
  /// power and session controls open and say why, naming the application
  /// whose block inhibitor holds it off.
  Future<void> sleep() async {
    if (state.sleepPending) return;
    state = state.copyWith(sleepPending: true);
    final power = ref.read(sessionPowerProvider.notifier);
    // A confirmation the power menu left armed would hold the request back.
    power.cancelConfirmation();
    // Capabilities and inhibitors as they are now.
    await power.refresh();
    if (!ref.mounted) return;
    await power.request(SessionPowerAction.suspend);
    if (!ref.mounted) return;
    state = state.copyWith(sleepPending: false);
    final error = ref.read(sessionPowerProvider).error;
    if (error == null) {
      ref.read(referenceShellProvider.notifier).closeQuickSettings();
      return;
    }
    debugPrint('Sleep: the system did not suspend: $error');
    showPowerSessionControls(ref.read(shellPopupControllerProvider.notifier));
  }

  /// Completes once the shade is shut, or after [shadeCloseTimeout].
  Future<void> _shadeClosed() {
    final shade = ref.read(shadeProgressProvider);
    if (shade.value <= 0) return Future<void>.value();
    final closed = Completer<void>();
    void check() {
      if (shade.value <= 0 && !closed.isCompleted) closed.complete();
    }

    shade.addListener(check);
    return closed.future
        .timeout(shadeCloseTimeout, onTimeout: () {})
        .whenComplete(() => shade.removeListener(check));
  }
}
