import '../models/audio.dart';

enum DenialShellAction {
  applications,
  dashboard,
  overview,
  windowSwitcherNext,
  windowSwitcherPrevious,
  windowSwitcherEnd,
  clipboard,
  screenshotPrepare,
  screenshotTextureReady,
  screenshotDone,
  clientPointerPressed,
  wallpaper,
  openSettings,
  workspaceChanged,
  focusLeft,
  focusRight,
  focusUp,
  focusDown,

  /// deniald captured a full-screen screenshot (Power plus Volume Down).
  screenshotCaptured,

  /// Settings asked for the tablet lock screen editor.
  lockScreenEditor,

  /// Show the windows of the focused app (full-screen apps layout, three
  /// fingers down).
  appWindows,

  /// The app switcher (Alt+Tab, or Cmd+Tab in the Mac preset): step the
  /// selected app forward or back. The first step opens the switcher.
  appSwitcherNext,
  appSwitcherPrevious,

  /// Step the windows of the selected app (grave, Shift+grave). Without an
  /// open switcher it steps the focused app's windows.
  appSwitcherWindowNext,
  appSwitcherWindowPrevious,

  /// The switcher's modifier was released: switch to the selection.
  appSwitcherEnd,

  /// Escape while the switcher's modifier is held: close without switching.
  appSwitcherCancel,

  /// Open search: the global overlay, or the open overview's search field.
  search,

  /// Switch to the neighbouring app (mobile presentation, three fingers
  /// sideways).
  switchAppPrevious,
  switchAppNext,

  /// A gesture that follows the fingers or the pointer; see
  /// [DenialShellActionEvent.gesture].
  shellGesture,
}

/// The direction of a [DenialShellAction.shellGesture]: three fingers (or a
/// middle-button drag) up or down.
enum DenialShellGestureKind { up, down }

enum DenialShellGesturePhase {
  begin,
  update,

  /// The fingers lifted; [DenialShellGesture.committed] says whether the
  /// view opens.
  end,

  /// Abandoned: another gesture took over, the session locked, ...
  cancel,
}

class DenialShellGesture {
  const DenialShellGesture({
    required this.kind,
    required this.phase,
    required this.progress,
    required this.velocity,
    required this.committed,
  });

  final DenialShellGestureKind kind;
  final DenialShellGesturePhase phase;

  /// 0 at rest, 1 when the view is fully open; may leave 0..1.
  final double progress;

  /// Progress per second at [DenialShellGesturePhase.end].
  final double velocity;

  /// At [DenialShellGesturePhase.end]: true when the gesture opens its view.
  final bool committed;
}

class DenialShellActionEvent {
  const DenialShellActionEvent({
    required this.action,
    required this.monitorId,
    required this.requestId,
    required this.textureId,
    required this.workspaceId,
    this.gesture,
  });

  final DenialShellAction action;
  final int? monitorId;
  final int requestId;
  final int? textureId;
  final int? workspaceId;

  /// Only for [DenialShellAction.shellGesture].
  final DenialShellGesture? gesture;
}

// The bridge and services share these immutable snapshots without remapping.
typedef DenialAudioState = AudioLevelState;
typedef DenialAudioStream = AppAudioStream;
typedef DenialAudioDevice = AudioOutputDevice;

class DenialBrightnessState {
  const DenialBrightnessState({
    required this.monitorId,
    required this.level,
    this.completesRead = false,
  });

  final int monitorId;
  final double level;

  /// Whether this update satisfied an explicit state read from Dart.
  ///
  /// Reconciliation reads seed controls but must not present the transient
  /// brightness HUD as though the user changed the hardware level.
  final bool completesRead;
}

class DenialSoftwareDimmingState {
  const DenialSoftwareDimmingState({
    required this.monitorId,
    required this.level,
    required this.supported,
    this.completesRead = false,
  });

  final int monitorId;
  final double level;
  final bool supported;
  final bool completesRead;
}

class DenialTextInputState {
  const DenialTextInputState({
    required this.active,
    required this.inputPanelVisible,
    required this.legacy,
    required this.contentHint,
    required this.contentPurpose,
    this.activationSerial = 0,
  });

  final bool active;
  final bool inputPanelVisible;
  final bool legacy;
  final int contentHint;
  final int contentPurpose;
  final int activationSerial;
}

/// Suggestions for the word the software keyboard is typing.
class DenialTextPrediction {
  const DenialTextPrediction({
    required this.serial,
    required this.word,
    required this.correction,
    required this.suggestions,
    required this.languages,
  });

  /// The serial of the request this answers.
  final int serial;
  final String word;

  /// What a space commits instead of [word], when it looks mistyped.
  final String? correction;

  /// Other words, best first; never [word] or [correction].
  final List<String> suggestions;

  /// The languages the suggestions come from, such as `en` and `it`.
  final List<String> languages;
}

class DenialSettingsDocument {
  const DenialSettingsDocument({required this.revision, required this.json});

  final int revision;
  final String json;
}
