import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

/// Animates a positioned rectangle while retaining its child layout.
///
/// By default the child adopts the destination layout once. Supplying
/// [layoutRect] keeps a stable canonical layout instead, which lets callers
/// move and scale expensive retained layers without resizing them. A paint
/// transform maps that layout onto the interpolated visual rectangle and hit
/// testing follows the transform. Set [layoutDuringAnimation] when the child
/// really must be laid out at every intermediate rectangle.
class RetainedAnimatedPositioned extends ImplicitlyAnimatedWidget {
  const RetainedAnimatedPositioned({
    required this.rect,
    required this.child,
    this.layoutRect,
    this.animationOrigin,
    this.globalClipRect,
    this.layoutDuringAnimation = false,
    this.driver,
    this.driverHome,
    required super.duration,
    super.curve,
    super.onEnd,
    super.key,
  });

  final Rect rect;
  final Widget child;
  final Rect? layoutRect;

  /// Overrides the visual begin rectangle when [rect] changes.
  ///
  /// This is useful when a retained child had a temporary paint transform:
  /// the transform can be removed while its absolute visual rectangle becomes
  /// the position tween's origin, avoiding a one-frame snap.
  final Rect? animationOrigin;

  /// Keeps the retained child inside a stationary scene-space viewport.
  ///
  /// The clip is resolved against [layoutRect] on every animation tick, so it
  /// stays fixed while the child translates or scales underneath it.
  final Rect? globalClipRect;
  final bool layoutDuringAnimation;

  /// Moves the child between [driverHome] (at 0) and [rect] (at 1) as the
  /// driver's value changes, without rebuilding: a gesture or a spring that
  /// many windows share. Changes of [rect] still ease as usual and the
  /// driver applies to the eased rectangle. When the driver goes away, the
  /// next animation starts from where it left the child.
  final Animation<double>? driver;
  final Rect? driverHome;

  bool get _driven => driver != null && driverHome != null;

  @override
  AnimatedWidgetBaseState<RetainedAnimatedPositioned> createState() =>
      _RetainedAnimatedPositionedState();
}

class _RetainedAnimatedPositionedState
    extends AnimatedWidgetBaseState<RetainedAnimatedPositioned> {
  RectTween? _rect;

  @override
  void didUpdateWidget(covariant RetainedAnimatedPositioned oldWidget) {
    if (oldWidget._driven && !widget._driven) {
      // Hand the driven rectangle over to the next animation.
      final eased = _rect?.evaluate(animation) ?? oldWidget.rect;
      final presented = Rect.lerp(
        oldWidget.driverHome,
        eased,
        oldWidget.driver!.value,
      )!;
      _rect = RectTween(begin: presented, end: presented);
    } else if (!oldWidget._driven && widget._driven) {
      // The driver starts at home and carries the child to its new place
      // itself; an eased move there on top of it would arrive twice.
      _rect = RectTween(begin: widget.rect, end: widget.rect);
    }
    final origin = widget.animationOrigin;
    if (origin != null && origin != oldWidget.animationOrigin) {
      // Make the presentation origin the tween's current value. This also
      // starts a return animation when the authoritative destination equals
      // the pre-drag rectangle.
      _rect = RectTween(begin: origin, end: origin);
    }
    super.didUpdateWidget(oldWidget);
    if (widget.duration == Duration.zero) {
      // A pointer grab can interrupt an animation without changing its target.
      // Finish that tween immediately, even when no new tween was started.
      controller.value = 1.0;
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _rect = visitor(
      _rect,
      widget.rect,
      (value) => RectTween(begin: value as Rect),
    ) as RectTween?;
  }

  @override
  Widget build(BuildContext context) {
    final destinationRect = widget.rect;
    final visualRect = _rect?.evaluate(animation) ?? destinationRect;
    final retainedRect = widget.layoutRect ?? destinationRect;
    final layoutRect = widget.layoutDuringAnimation ? visualRect : retainedRect;
    return Positioned.fill(
      child: _RetainedTransformBox(
        retainedSize: layoutRect.size,
        visualRect: visualRect,
        driver: widget._driven ? widget.driver : null,
        driverHome: widget._driven ? widget.driverHome : null,
        globalClipRect: widget.globalClipRect,
        child: widget.child,
      ),
    );
  }
}

/// Gives a retained child stable layout without constraining its painted or
/// interactive bounds to the old layout rectangle.
///
/// A normal [Transform] can paint outside its box, but ancestors reject hit
/// tests before the inverse transform is reached. Overview previews regularly
/// move outside their desktop rectangles, especially after a resize. This
/// scene-sized proxy owns the complete hit-test area, then applies one shared
/// transform to painting, hit testing, and semantics.
class _RetainedTransformBox extends SingleChildRenderObjectWidget {
  const _RetainedTransformBox({
    required this.retainedSize,
    required this.visualRect,
    required this.driver,
    required this.driverHome,
    required this.globalClipRect,
    required super.child,
  });

  final Size retainedSize;
  final Rect visualRect;
  final Animation<double>? driver;
  final Rect? driverHome;
  final Rect? globalClipRect;

  @override
  _RenderRetainedTransformBox createRenderObject(BuildContext context) =>
      _RenderRetainedTransformBox(
        retainedSize: retainedSize,
        visualRect: visualRect,
        driver: driver,
        driverHome: driverHome,
        globalClipRect: globalClipRect,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRetainedTransformBox renderObject,
  ) {
    renderObject
      ..retainedSize = retainedSize
      ..visualRect = visualRect
      ..driver = driver
      ..driverHome = driverHome
      ..globalClipRect = globalClipRect;
  }
}

class _RenderRetainedTransformBox extends RenderProxyBox {
  _RenderRetainedTransformBox({
    required this._retainedSize,
    required this._visualRect,
    required this._driver,
    required this._driverHome,
    required this._globalClipRect,
  });

  Size _retainedSize;

  set retainedSize(Size value) {
    if (_retainedSize == value) {
      return;
    }
    _retainedSize = value;
    markNeedsLayout();
  }

  Rect _visualRect;

  set visualRect(Rect value) {
    if (_visualRect == value) {
      return;
    }
    _visualRect = value;
    _visualRectChanged();
  }

  Animation<double>? _driver;

  set driver(Animation<double>? value) {
    if (identical(_driver, value)) {
      return;
    }
    if (attached) {
      _driver?.removeListener(_visualRectChanged);
      value?.addListener(_visualRectChanged);
    }
    _driver = value;
    _visualRectChanged();
  }

  Rect? _driverHome;

  set driverHome(Rect? value) {
    if (_driverHome == value) {
      return;
    }
    _driverHome = value;
    _visualRectChanged();
  }

  /// Where the child is shown: [_visualRect], or a driver's point between
  /// its home and [_visualRect].
  Rect get _presentedRect {
    final driver = _driver;
    final home = _driverHome;
    if (driver == null || home == null) {
      return _visualRect;
    }
    return Rect.lerp(home, _visualRect, driver.value)!;
  }

  void _visualRectChanged() {
    if (isRepaintBoundary) {
      markNeedsCompositedLayerUpdate();
    } else {
      markNeedsPaint();
    }
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _driver?.addListener(_visualRectChanged);
  }

  @override
  void detach() {
    _driver?.removeListener(_visualRectChanged);
    super.detach();
  }

  Rect? _globalClipRect;

  set globalClipRect(Rect? value) {
    if (_globalClipRect == value) {
      return;
    }
    if ((_globalClipRect == null) != (value == null)) {
      markNeedsCompositingBitsUpdate();
    }
    _globalClipRect = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// Without a scene clip the visual transform is a property of this box's
  /// own layer, so moving or scaling the retained child repaints nothing:
  /// neither the child nor the scene behind it. A scene clip applies before
  /// the transform and is painted instead.
  @override
  bool get isRepaintBoundary => _globalClipRect == null;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant TransformLayer? oldLayer,
  }) => (oldLayer ?? TransformLayer())..transform = _visualTransform;

  Matrix4 get _visualTransform {
    final rect = _presentedRect;
    final scaleX = _retainedSize.width > 0
        ? rect.width / _retainedSize.width
        : 1.0;
    final scaleY = _retainedSize.height > 0
        ? rect.height / _retainedSize.height
        : 1.0;
    return Matrix4.diagonal3Values(scaleX, scaleY, 1)
      ..setTranslationRaw(rect.left, rect.top, 0);
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth && constraints.hasBoundedHeight);
    size = constraints.biggest;
    child?.layout(BoxConstraints.tight(_retainedSize), parentUsesSize: true);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final clip = _globalClipRect;
    if (clip != null && !clip.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    return result.addWithPaintTransform(
      transform: _visualTransform,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    final clip = _globalClipRect;
    if (clip == null) {
      // The composited layer applies the visual transform.
      super.paint(context, offset);
      return;
    }

    void paintTransformed(PaintingContext context, Offset offset) {
      context.pushTransform(
        needsCompositing,
        offset,
        _visualTransform,
        (context, offset) => super.paint(context, offset),
      );
    }

    context.pushClipRect(
      needsCompositing,
      offset,
      clip,
      paintTransformed,
      clipBehavior: Clip.hardEdge,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_visualTransform);
  }
}
