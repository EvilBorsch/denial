import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/state.dart' show inputDeviceCapabilitiesProvider;

/// Whether a keyboard to type on is attached, for the software keyboard's
/// automatic appearance on a phone or tablet.
///
/// deniald tells the shell which touchpads and mice are connected, not which
/// keyboards: to libinput the power and volume buttons are keyboards too, so
/// a keyboard device alone says nothing. A touchpad stands in for a keyboard
/// cover instead; the OnePlus Pad 3 keyboard, for one, attaches as a keyboard
/// and a touchpad together.
///
/// A detach counts only after [detachGrace]: a cover that drops off its
/// connector and comes straight back must not flash the software keyboard.
final hardwareKeyboardAttachedProvider =
    NotifierProvider<HardwareKeyboardAttached, bool>(
      HardwareKeyboardAttached.new,
    );

class HardwareKeyboardAttached extends Notifier<bool> {
  static const Duration detachGrace = Duration(milliseconds: 1500);

  Timer? _detach;

  @override
  bool build() {
    ref.onDispose(() {
      _detach?.cancel();
      _detach = null;
    });
    ref.listen<bool>(
      inputDeviceCapabilitiesProvider.select(
        (devices) => devices.capabilities.hasTouchpad,
      ),
      _touchpadChanged,
    );
    return ref.read(inputDeviceCapabilitiesProvider).capabilities.hasTouchpad;
  }

  void _touchpadChanged(bool? previous, bool present) {
    _detach?.cancel();
    _detach = null;
    if (present) {
      state = true;
      return;
    }
    _detach = Timer(detachGrace, () {
      _detach = null;
      state = false;
    });
  }
}
