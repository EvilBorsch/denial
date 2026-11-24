import 'dart:async';

import 'package:denial_flutter_sdk/platform.dart'
    show DenialShellAction, DenialShellActionEvent;
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reference_shell_controller.dart';
import 'reference_shell_presentation.dart';
import 'reference_shell_profile.dart';

/// The presentation the shell shows, and how a switch to it is covered.
@immutable
class PresentationSwitchState {
  const PresentationSwitchState({
    required this.shown,
    this.coverTexture,
    this.waiting = false,
  });

  /// The tablet's (mobile) or the desktop's presentation, as drawn.
  final ReferenceShellProfile shown;

  /// The frame on screen before the switch to [shown], frozen by deniald in
  /// this texture: the switch's cover. Null when the shell takes its own
  /// picture instead (an older deniald, a locked session, a monitor).
  final int? coverTexture;

  /// A switch waits for its cover: the cursor hides, so the frozen frame
  /// has none, and frames keep coming, so deniald has one to freeze.
  final bool waiting;

  @override
  bool operator ==(Object other) =>
      other is PresentationSwitchState &&
      other.shown == shown &&
      other.coverTexture == coverTexture &&
      other.waiting == waiting;

  @override
  int get hashCode => Object.hash(shown, coverTexture, waiting);
}

/// Switches the drawn presentation in two steps, so the switch's cover is
/// the frame already on screen and nothing has to be drawn again for it:
///
/// 1. The presentation chosen ([referenceShellPresentationProvider])
///    changes. The shell asks deniald for the frame on screen
///    ([DenialBridge.requestPresentationCover]) and keeps showing the
///    presentation it has.
/// 2. deniald answers with the frame frozen in a texture: the shell shows
///    the new presentation with that texture over it, which then dissolves
///    (`PresentationSwitchCover`) and is released.
///
/// Without an answer within [coverWait] (a deniald before eb19 ignores the
/// request), or with an answer without a texture, the shell switches at
/// once and takes its own picture, as before.
final presentationSwitchProvider =
    NotifierProvider<PresentationSwitch, PresentationSwitchState>(
      PresentationSwitch.new,
    );

class PresentationSwitch extends Notifier<PresentationSwitchState> {
  /// How long a switch waits for deniald's frozen frame. It comes after
  /// one or two frames.
  static const Duration coverWait = Duration(milliseconds: 150);

  int _nextRequest = 0;

  /// The request waiting for its answer, and the presentation it is for.
  int? _pending;
  ReferenceShellProfile? _target;

  /// The request whose texture covers the switch shown, and that texture.
  int? _held;
  int? _heldTexture;

  Timer? _timeout;

  /// The scene was drawn once: a cover has a frame to freeze.
  var _drawn = false;

  @override
  PresentationSwitchState build() {
    final bridge = ref.watch(denialBridgeProvider);
    _pending = null;
    _target = null;
    _held = null;
    _drawn = false;
    final answers = bridge.shellActions
        .where((event) => event.action == DenialShellAction.presentationCover)
        .listen(_answered);
    ref.onDispose(() {
      _timeout?.cancel();
      _timeout = null;
      unawaited(answers.cancel());
      for (final id in [?_pending, ?_held]) {
        bridge.releasePresentationCover(id);
      }
    });
    ref.listen<ReferenceShellProfile>(
      referenceShellPresentationProvider,
      (_, next) => _chosen(next),
    );
    return PresentationSwitchState(
      shown: ref.read(referenceShellPresentationProvider),
    );
  }

  /// The scene drew its first frame.
  void drawn() => _drawn = true;

  /// The cover [texture] dissolved: deniald drops it.
  void release(int texture) {
    if (texture != _heldTexture) return;
    _releaseHeld();
    if (state.coverTexture == texture) {
      state = PresentationSwitchState(shown: state.shown);
    }
  }

  void _releaseHeld() {
    final id = _held;
    _held = null;
    _heldTexture = null;
    if (id != null) ref.read(denialBridgeProvider).releasePresentationCover(id);
  }

  void _chosen(ReferenceShellProfile next) {
    if (_pending != null) {
      // Chosen again while the cover is on its way.
      _target = next;
      return;
    }
    if (next == state.shown) return;
    final bridge = ref.read(denialBridgeProvider);
    // deniald freezes one frame at a time: a cover still dissolving from the
    // switch before gives way, and its dissolve ends.
    _releaseHeld();
    final id = ++_nextRequest;
    if (!_drawn ||
        ref.read(referenceShellProvider).locked ||
        ref.read(singleScreenSessionProvider) != true ||
        !bridge.requestPresentationCover(id)) {
      state = PresentationSwitchState(shown: next);
      return;
    }
    _pending = id;
    _target = next;
    _timeout = Timer(coverWait, () => _switch(null));
    state = PresentationSwitchState(shown: state.shown, waiting: true);
  }

  void _answered(DenialShellActionEvent event) {
    if (!ref.mounted) return;
    if (event.requestId != _pending) {
      // The answer came after the switch went without it.
      if (event.textureId != null && event.requestId != _held) {
        ref.read(denialBridgeProvider).releasePresentationCover(event.requestId);
      }
      return;
    }
    _switch(event.textureId);
  }

  void _switch(int? texture) {
    _timeout?.cancel();
    _timeout = null;
    final id = _pending;
    final target = _target;
    _pending = null;
    _target = null;
    if (id == null || target == null) return;
    if (texture == null) {
      // A deniald that took the request but has not answered yet drops it.
      ref.read(denialBridgeProvider).releasePresentationCover(id);
    } else {
      _held = id;
      _heldTexture = texture;
    }
    if (target == state.shown) {
      // Chosen back while waiting: nothing to switch, nothing to cover.
      _releaseHeld();
      state = PresentationSwitchState(shown: target);
      return;
    }
    state = PresentationSwitchState(shown: target, coverTexture: texture);
  }
}
