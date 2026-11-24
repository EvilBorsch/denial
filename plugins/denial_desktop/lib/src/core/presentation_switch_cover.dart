import 'dart:async';
import 'dart:ui' as ui;

import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
/// has not drawn yet, and the new scene settling. Instead the last frame of
/// the presentation left stays in front ([presentationSwitchHoldLimit] at
/// most) until the windows the new one shows have drawn at their new sizes,
/// then dissolves into it ([presentationSwitchDissolve]). The new scene runs
/// and takes input underneath from the first frame.
///
/// The cover is the frame that was on screen, which deniald froze in
/// [coverTexture] (`presentationSwitchProvider`): nothing is drawn again for
/// it. Without that texture (an older deniald, a locked session) the cover
/// is a picture this widget takes of the scene's last layers. A frame of the
/// dissolve draws the live scene and the cover, nothing more.
class PresentationSwitchCover extends ConsumerStatefulWidget {
  const PresentationSwitchCover({
    super.key,
    required this.presentation,
    this.enabled = true,
    this.coverTexture,
    this.waiting = false,
    this.onDrawn,
    this.onReleased,
    required this.child,
  });

  /// The presentation shown; a change starts the cover.
  final ReferenceShellProfile presentation;

  /// False while the switch also changes the screens, such as a monitor
  /// coming or going: the last frame would not fit.
  final bool enabled;

  /// The frame on screen before the switch to [presentation], frozen by
  /// deniald; null when this widget takes its own picture.
  final int? coverTexture;

  /// A switch waits for deniald to freeze a frame: frames keep coming.
  final bool waiting;

  /// The scene drew its first frame.
  final VoidCallback? onDrawn;

  /// The cover [coverTexture] dissolved: deniald may drop that texture.
  final ValueChanged<int>? onReleased;

  final Widget child;

  @override
  ConsumerState<PresentationSwitchCover> createState() =>
      _PresentationSwitchCoverState();
}

class _PresentationSwitchCoverState
    extends ConsumerState<PresentationSwitchCover>
    with TickerProviderStateMixin {
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

  /// Keeps frames coming while deniald waits for one to freeze.
  late final Ticker _frames = createTicker((_) {});

  /// The cover: a frozen frame of deniald's, or a picture of the scene.
  int? _texture;
  ui.Image? _picture;
  Timer? _holdLimit;
  ProviderSubscription<bool>? _settled;
  final _since = Stopwatch();

  bool get _covered => _texture != null || _picture != null;

  @override
  void initState() {
    super.initState();
    _followWaiting();
    if (widget.onDrawn case final drawn?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) drawn();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PresentationSwitchCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followWaiting();
    if (oldWidget.presentation != widget.presentation &&
        widget.enabled &&
        oldWidget.enabled) {
      _cover();
    }
  }

  @override
  void dispose() {
    _endCover();
    _frames.dispose();
    _dissolve.dispose();
    super.dispose();
  }

  void _followWaiting() {
    if (widget.waiting && !_frames.isActive) {
      _frames.start();
    } else if (!widget.waiting && _frames.isActive) {
      _frames.stop();
    }
  }

  /// Covers the switch with the frame on screen, before this frame draws the
  /// new scene.
  void _cover() {
    final texture = widget.coverTexture;
    final String cover;
    _endCover();
    if (texture != null) {
      _texture = texture;
      cover = 'the frozen frame on screen (texture $texture)';
    } else {
      final picture = _takePicture();
      if (picture == null) return;
      _picture = picture;
      cover = 'a ${picture.width}x${picture.height} picture';
    }
    debugPrint(
      'presentation switch to ${widget.presentation.name}: covered by $cover',
    );
    _since
      ..reset()
      ..start();
    _dissolve.value = 0;
    _dissolve.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : presentationSwitchDissolve;
    _holdLimit = Timer(presentationSwitchHoldLimit, _reveal);
    // Settled windows end the hold; the first frame of the new scene comes
    // first, so its windows are the ones checked.
    final shownTexture = _texture;
    final shownPicture = _picture;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _texture != shownTexture || _picture != shownPicture) {
        return;
      }
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
          if (settled) _reveal(settled: true);
        },
        fireImmediately: true,
      );
    });
  }

  /// A picture of the scene's last layers, the cover when deniald gave none.
  /// It draws the old scene once more.
  ui.Image? _takePicture() {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      debugPrint('presentation switch: no cover, the scene is not laid out');
      return null;
    }
    // The layer still holds the frame on screen: this build has not painted.
    final layer = boundary.layer;
    if (layer is! OffsetLayer || !layer.attached) {
      debugPrint('presentation switch: no cover, the scene has no picture');
      return null;
    }
    try {
      return layer.toImageSync(
        Offset.zero & boundary.size,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } on Object catch (error) {
      debugPrint('presentation switch: no cover, $error');
      return null;
    }
  }

  /// The windows are ready, or the hold is over: dissolve.
  void _reveal({bool settled = false}) {
    _holdLimit?.cancel();
    _holdLimit = null;
    _settled?.close();
    _settled = null;
    if (!mounted || !_covered || _dissolve.isAnimating) return;
    if (_dissolve.value == 0) {
      debugPrint(
        'presentation switch: dissolves after ${_since.elapsedMilliseconds} '
        'ms (${settled ? 'windows redrawn' : 'hold limit'})',
      );
      _dissolve.forward();
    }
  }

  void _dissolveStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _covered) {
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
    if (_texture case final texture?) {
      _texture = null;
      // Not while the tree builds: the release changes the shell's state.
      final released = widget.onReleased;
      if (released != null) scheduleMicrotask(() => released(texture));
    }
  }

  @override
  Widget build(BuildContext context) {
    final texture = _texture;
    final picture = _picture;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (texture != null || picture != null)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _opacity,
                child: texture != null
                    ? Texture(
                        textureId: texture,
                        freeze: true,
                        filterQuality: FilterQuality.none,
                      )
                    : RawImage(
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
