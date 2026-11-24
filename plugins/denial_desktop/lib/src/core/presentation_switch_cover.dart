import 'dart:async';
import 'dart:ui' as ui;

import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/reference_shell_controller.dart';
import '../state/reference_shell_profile.dart';
import '../state/reference_shell_state.dart';

/// How long the last picture of the presentation left dissolves into the
/// new one.
const Duration presentationSwitchDissolve = Duration(milliseconds: 260);

/// The longest the last picture holds while the windows redraw at their new
/// sizes, from the switch.
const Duration presentationSwitchHoldLimit = Duration(milliseconds: 450);

/// A window that has drawn its new size is within this many logical pixels
/// of the geometry deniald gave it.
const double _sizeTolerance = 2.0;

/// The windows [presentation] shows once it is up: on the desktop the app
/// windows on the screen, on the tablet the app in front and its Split View
/// partner. Minimized windows show nothing.
List<DenialWindow> presentationSwitchShownWindows(
  ReferenceShellState state,
  ReferenceShellProfile presentation,
  Rect screen,
) {
  if (presentation == ReferenceShellProfile.mobile) {
    final front = state.primaryWindow;
    if (front == null || front.minimized) return const <DenialWindow>[];
    final partner = state.splitPartnerOf(front);
    return [front, ?partner];
  }
  return [
    for (final window in state.desk.openAppWindows)
      if (!window.minimized &&
          (window.geometry?.overlaps(screen) ?? false))
        window,
  ];
}

/// Whether [windows] have drawn at the sizes [presentation] gave them:
/// deniald laid each one out for it ([DenialWindow.onPhone]) and its
/// committed content has its geometry's size.
bool presentationSwitchWindowsSettled(
  Iterable<DenialWindow> windows,
  ReferenceShellProfile presentation,
) {
  final onPhone = presentation == ReferenceShellProfile.mobile;
  for (final window in windows) {
    if (window.onPhone != onPhone) return false;
    if (window.geometry == null) continue;
    if ((window.contentWidth - window.geometryWidth).abs() > _sizeTolerance ||
        (window.contentHeight - window.geometryHeight).abs() >
            _sizeTolerance) {
      return false;
    }
  }
  return true;
}

/// Makes the switch between the tablet and desktop presentations seamless.
///
/// The switch replaces the whole scene, and deniald resizes the windows to
/// the new presentation only once it shows: for a few frames the windows
/// would show their old buffers at new sizes, the wallpaper where a window
/// has not drawn yet, and the new scene settling. Instead the last picture
/// of the presentation left stays in front ([presentationSwitchHoldLimit] at
/// most) until the windows the new one shows have drawn at their new sizes,
/// then dissolves into it ([presentationSwitchDissolve]). The new scene runs
/// and takes input underneath from the first frame.
///
/// The picture is one image the GPU already holds: a frame of the dissolve
/// draws the live scene and that image, nothing more.
class PresentationSwitchCover extends ConsumerStatefulWidget {
  const PresentationSwitchCover({
    super.key,
    required this.presentation,
    this.enabled = true,
    required this.child,
  });

  /// The presentation shown; a change starts the cover.
  final ReferenceShellProfile presentation;

  /// False while the switch also changes the screens, such as a monitor
  /// coming or going: the last picture would not fit.
  final bool enabled;

  final Widget child;

  @override
  ConsumerState<PresentationSwitchCover> createState() =>
      _PresentationSwitchCoverState();
}

class _PresentationSwitchCoverState
    extends ConsumerState<PresentationSwitchCover>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey(debugLabel: 'presentation switch');
  late final AnimationController _dissolve = AnimationController(
    vsync: this,
    duration: presentationSwitchDissolve,
    value: 1,
  )..addStatusListener(_dissolveStatus);
  late final Animation<double> _opacity = CurvedAnimation(
    parent: ReverseAnimation(_dissolve),
    curve: Curves.easeInOut,
  );
  ui.Image? _picture;
  Timer? _holdLimit;
  ProviderSubscription<bool>? _settled;

  @override
  void didUpdateWidget(covariant PresentationSwitchCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presentation != widget.presentation &&
        widget.enabled &&
        oldWidget.enabled) {
      _cover();
    }
  }

  @override
  void dispose() {
    _endCover();
    _dissolve.dispose();
    super.dispose();
  }

  /// Takes the last picture shown, before this frame draws the new scene.
  void _cover() {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return;
    // The layer still holds the frame on screen: this build has not painted.
    final layer = boundary.layer;
    if (layer is! OffsetLayer || !layer.attached) return;
    final ui.Image picture;
    try {
      picture = layer.toImageSync(
        Offset.zero & boundary.size,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } on Object {
      return;
    }
    _endCover();
    _picture = picture;
    _dissolve.value = 0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _dissolve.duration = Duration.zero;
    } else {
      _dissolve.duration = presentationSwitchDissolve;
    }
    _holdLimit = Timer(presentationSwitchHoldLimit, _reveal);
    // Settled windows end the hold; the first frame of the new scene comes
    // first, so its windows are the ones checked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _picture != picture) return;
      final screen = Offset.zero & MediaQuery.sizeOf(context);
      final presentation = widget.presentation;
      _settled = ref.listenManual<bool>(
        referenceShellProvider.select(
          (state) => presentationSwitchWindowsSettled(
            presentationSwitchShownWindows(state, presentation, screen),
            presentation,
          ),
        ),
        (_, settled) {
          if (settled) _reveal();
        },
        fireImmediately: true,
      );
    });
  }

  /// The windows are ready, or the hold is over: dissolve.
  void _reveal() {
    _holdLimit?.cancel();
    _holdLimit = null;
    _settled?.close();
    _settled = null;
    if (!mounted || _picture == null || _dissolve.isAnimating) return;
    if (_dissolve.value == 0) _dissolve.forward();
  }

  void _dissolveStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _picture != null) {
      setState(_endCover);
    }
  }

  void _endCover() {
    _holdLimit?.cancel();
    _holdLimit = null;
    _settled?.close();
    _settled = null;
    _picture?.dispose();
    _picture = null;
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (picture != null)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _opacity,
                child: RawImage(
                  image: picture,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
