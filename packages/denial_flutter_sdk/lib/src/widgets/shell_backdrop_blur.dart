import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/shell_theme.dart';
import '../theme/glass_configuration.dart';

/// A tightly clipped, layout-aware blur for translucent compositor surfaces.
///
/// Every instance owns its backdrop unless [grouped] is true. Windows must
/// never be grouped because they can overlap; non-overlapping siblings such as
/// system-bar pills can opt into one shared engine blur through [BackdropGroup].
class ShellBackdropBlur extends StatelessWidget {
  const ShellBackdropBlur({
    required this.child,
    this.blur = true,
    this.grouped = false,
    this.useWindowAlphaThreshold = false,
    this.singleWindowSurface = false,
    this.separateChild = false,
    this.strength = 1,
    this.borderRadius,
    this.blendMode = ui.BlendMode.src,
    this.opacity,
    this.clipUnfiltered = true,
    super.key,
  }) : assert(strength >= 0 && strength <= 1),
       assert(!separateChild || !useWindowAlphaThreshold),
       assert(!separateChild || blendMode == ui.BlendMode.src);

  final Widget child;
  final bool blur;
  final bool grouped;
  final bool useWindowAlphaThreshold;
  final bool singleWindowSurface;

  /// Paint foreground controls after the backdrop assignment. This keeps
  /// their geometry out of the filter's intermediate color layer. Window
  /// alpha-threshold materials need the foreground inside that layer instead.
  final bool separateChild;
  final double strength;
  final BorderRadiusGeometry? borderRadius;
  final ui.BlendMode blendMode;

  /// Fade the completed backdrop and foreground independently. In particular,
  /// separate-child glass must not be isolated with controls in an opacity group.
  final Animation<double>? opacity;

  /// Clip [child] to [borderRadius] even when no filter runs. Pass false for
  /// a child that paints its own rounded shape, such as a decorated tile, to
  /// spare it a clip on every frame.
  final bool clipUnfiltered;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final resolvedStrength = strength.clamp(0.0, 1.0).toDouble();
    final radius = borderRadius?.resolve(Directionality.of(context));
    final available =
        blur &&
        theme.backdropBlurEnabled &&
        (theme.transparencyMode == ShellTransparencyMode.glass ||
            theme.backdropBlurSigma > 0) &&
        (!useWindowAlphaThreshold || theme.backdropBlurOpacityThreshold < 1.0);
    final enabled = available && resolvedStrength > 0;
    Widget fade(Widget value) => opacity == null
        ? value
        : FadeTransition(opacity: opacity!, child: value);
    final effectiveBlendMode = opacity == null
        ? blendMode
        : ui.BlendMode.srcOver;
    final Widget filtered;
    if (available) {
      final filterConfig = theme.backdropFilterConfigAt(
        resolvedStrength,
        borderRadius: radius ?? BorderRadius.zero,
        useWindowAlphaThreshold: useWindowAlphaThreshold,
        singleWindowSurface: singleWindowSurface,
      );
      // An opacity above the filter changes on every frame of a fade, and
      // the engine then filters the unchanged backdrop again each frame.
      // Faded inside the filter's own layer instead, the filtered backdrop
      // is reused across the fade. A grouped or disabled filter has no
      // layer of its own to fade.
      final fadesInLayer = opacity != null && enabled && !grouped;
      final filterChild = separateChild ? const SizedBox.expand() : child;
      final layerChild = fadesInLayer
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                filterChild,
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _LayerFade(opacity!)),
                  ),
                ),
              ],
            )
          : filterChild;
      final backdrop = grouped
          ? BackdropFilter.grouped(
              filterConfig: filterConfig,
              blendMode: effectiveBlendMode,
              enabled: enabled,
              child: layerChild,
            )
          : BackdropFilter(
              filterConfig: filterConfig,
              blendMode: effectiveBlendMode,
              enabled: enabled,
              child: layerChild,
            );
      final fadedBackdrop = fadesInLayer
          ? _HiddenAtZero(opacity: opacity!, child: backdrop)
          : fade(backdrop);
      filtered = separateChild
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(child: fadedBackdrop),
                fade(child),
              ],
            )
          : fadedBackdrop;
    } else {
      filtered = fade(child);
    }

    if (!available && !clipUnfiltered) {
      return filtered;
    }
    if (radius == null) {
      return available
          ? ClipRect(clipBehavior: Clip.hardEdge, child: filtered)
          : filtered;
    }
    if (radius == BorderRadius.zero) {
      return ClipRect(clipBehavior: Clip.hardEdge, child: filtered);
    }
    return ClipRRect(
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: filtered,
    );
  }
}

/// Multiplies the backdrop filter's layer, the filtered backdrop and the
/// child over it, by [opacity] (destination-in), quantized as an opacity
/// layer quantizes it. The layer then composites over the scene exactly as
/// the whole filter would under that opacity.
class _LayerFade extends CustomPainter {
  _LayerFade(this.opacity) : super(repaint: opacity);

  final Animation<double> opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = ui.Color.getAlphaFromOpacity(opacity.value.clamp(0.0, 1.0));
    if (alpha == 255) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = ui.BlendMode.dstIn
        ..color = Color.fromARGB(alpha, 0, 0, 0),
    );
  }

  @override
  bool shouldRepaint(_LayerFade oldDelegate) => oldDelegate.opacity != opacity;
}

/// Paints [child] only while [opacity] is above zero, as a fade does, and
/// repaints only when it crosses zero: the fade itself is [_LayerFade]'s.
class _HiddenAtZero extends SingleChildRenderObjectWidget {
  const _HiddenAtZero({required this.opacity, required super.child});

  final Animation<double> opacity;

  @override
  _RenderHiddenAtZero createRenderObject(BuildContext context) =>
      _RenderHiddenAtZero(opacity);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHiddenAtZero renderObject,
  ) {
    renderObject.opacity = opacity;
  }
}

class _RenderHiddenAtZero extends RenderProxyBox {
  _RenderHiddenAtZero(this._opacity);

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (value == _opacity) return;
    if (attached) {
      _opacity.removeListener(_changed);
      value.addListener(_changed);
    }
    _opacity = value;
    _changed();
  }

  bool _visible = false;

  bool get _shown => ui.Color.getAlphaFromOpacity(
        _opacity.value.clamp(0.0, 1.0),
      ) >
      0;

  void _changed() {
    if (_shown != _visible) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity.addListener(_changed);
  }

  @override
  void detach() {
    _opacity.removeListener(_changed);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _visible = _shown;
    if (_visible) super.paint(context, offset);
  }
}
