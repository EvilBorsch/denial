import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// Fades [child] through a snapshot of it.
///
/// Opacity over content with text cannot be pushed down to its draws, so a
/// plain fade renders the whole subtree into an offscreen layer on every
/// frame. While [opacity] is strictly between 0 and 1, this draws an image
/// of [child] with the opacity instead, one image draw per frame. At 1 the
/// child paints live; at 0 nothing paints.
///
/// The image shows the child as it was when the fade began: use this for
/// content that holds still while it fades, such as a home grid behind a
/// transition. A change made mid-fade shows when the fade ends.
///
/// Rendering a large child into the image takes the raster thread one long
/// frame (40 to 80 ms for the tablet's home grid), the first frame of the
/// fade. With [retain] the image outlives the fade: the next fade reuses it
/// while the child has not changed, and a child that changed while shown is
/// rendered again once nothing has moved for a while, so a fade seldom
/// starts with that frame. The image then stays in memory as long as this
/// widget does.
class FadeSnapshot extends SingleChildRenderObjectWidget {
  FadeSnapshot({
    super.key,
    required this.opacity,
    this.retain = false,
    required Widget child,
  }) : super(child: _FadeSource(child: child));

  final Animation<double> opacity;
  final bool retain;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFadeSnapshot(
    opacity: opacity,
    retain: retain,
    pixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFadeSnapshot renderObject,
  ) {
    renderObject
      ..opacity = opacity
      ..retain = retain
      ..pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderFadeSnapshot extends RenderProxyBox {
  _RenderFadeSnapshot({
    required Animation<double> opacity,
    required this.retain,
    required this.pixelRatio,
  }) : _opacity = opacity;

  /// How long the child must hold still while shown before a retained
  /// image is rendered again ahead of the next fade.
  static const _settle = Duration(milliseconds: 1500);

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (identical(value, _opacity)) return;
    if (attached) {
      _opacity.removeListener(_opacityChanged);
      value.addListener(_opacityChanged);
    }
    _opacity = value;
    _opacityChanged();
  }

  bool retain;
  double pixelRatio;

  ui.Image? _image;

  /// The child's generation, size and pixel ratio the image was taken at.
  int? _imageGeneration;
  Size? _imageSize;
  double? _imageRatio;

  double? _painted;
  bool _fading = false;
  bool _shown = false;
  bool _prepare = false;
  Timer? _idle;

  _RenderFadeSource get _source => child! as _RenderFadeSource;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity.addListener(_opacityChanged);
  }

  @override
  void detach() {
    _opacity.removeListener(_opacityChanged);
    _idle?.cancel();
    _idle = null;
    super.detach();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    (child as _RenderFadeSource).onChanged = _sourceChanged;
  }

  void _opacityChanged() {
    if (_opacity.value != _painted) markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = _source;
    final value = _painted = _opacity.value;
    _shown = value >= 1;
    if (value > 0 && value < 1) {
      if (!_fading) {
        _fading = true;
        _snapshot(source, offset);
      }
      final image = _image;
      if (image == null) {
        // The child cannot be rasterized (a platform view): fade it live.
        context.pushOpacity(
          offset,
          (value * 255).round(),
          (context, offset) => context.paintChild(source, offset),
        );
        return;
      }
      context.canvas.drawImageRect(
        image,
        Offset.zero & (_imageSize! * _imageRatio!),
        offset & size,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, value)
          ..filterQuality = FilterQuality.low,
      );
      return;
    }
    _fading = false;
    if (_shown) {
      if (_prepare) _snapshot(source, offset);
      context.paintChild(source, offset);
    }
    _prepare = false;
    if (!retain) _release();
  }

  /// Makes [_image] show the child as it is now: renders it, unless the
  /// retained image already shows it.
  void _snapshot(_RenderFadeSource source, Offset offset) {
    final container = OffsetLayer();
    PaintingContext(container, offset & size).paintChild(source, offset);
    if (!container.supportsRasterization()) {
      container.dispose();
      _release();
      return;
    }
    final transform = Matrix4.diagonal3Values(pixelRatio, pixelRatio, 1)
      ..translateByDouble(-offset.dx, -offset.dy, 0, 1);
    // Building the scene brings the child's layer up to date, which tells
    // whether anything in it changed since the image was taken.
    final scene = container.buildScene(
      ui.SceneBuilder()..pushTransform(transform.storage),
    );
    if (_image == null ||
        source.generation != _imageGeneration ||
        size != _imageSize ||
        pixelRatio != _imageRatio) {
      _image?.dispose();
      _image = scene.toImageSync(
        (pixelRatio * size.width).ceil(),
        (pixelRatio * size.height).ceil(),
      );
      _imageGeneration = source.generation;
      _imageSize = size;
      _imageRatio = pixelRatio;
      MotionTelemetry.event(
        'fade_snapshot',
        fields: {
          'width': _image!.width,
          'height': _image!.height,
          'ahead': _prepare ? 1 : 0,
        },
      );
    }
    scene.dispose();
    container.dispose();
  }

  void _release() {
    _image?.dispose();
    _image = null;
    _imageGeneration = null;
  }

  /// The child's layer was built anew: something in it changed.
  void _sourceChanged() {
    if (!retain || !_shown) return;
    _idle?.cancel();
    _idle = Timer(_settle, _prepareWhenIdle);
  }

  /// Renders the image while the child is shown and nothing moves, so the
  /// next fade starts from it.
  void _prepareWhenIdle() {
    _idle = null;
    if (!attached ||
        !_shown ||
        !(layer?.attached ?? false) ||
        _source.generation == _imageGeneration) {
      return;
    }
    final scheduler = SchedulerBinding.instance;
    if (scheduler.hasScheduledFrame || scheduler.transientCallbackCount > 0) {
      _idle = Timer(_settle, _prepareWhenIdle);
      return;
    }
    _prepare = true;
    markNeedsPaint();
  }
}

class _FadeSource extends SingleChildRenderObjectWidget {
  const _FadeSource({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFadeSource();
}

/// The faded child's own repaint boundary, whose layer counts the times a
/// scene had to build it anew.
class _RenderFadeSource extends RenderProxyBox {
  int generation = 0;
  VoidCallback? onChanged;

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant _SourceLayer? oldLayer,
  }) => oldLayer ?? _SourceLayer(this);
}

/// A scene keeps a layer whose subtree has not changed as it is, without
/// calling [addToScene]: a call means the child changed (or was never
/// shown).
class _SourceLayer extends OffsetLayer {
  _SourceLayer(this._source);

  final _RenderFadeSource _source;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _source.generation += 1;
    _source.onChanged?.call();
    super.addToScene(builder);
  }
}
