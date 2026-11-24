import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// An imported client image and its Wayland viewport, before window effects.
@immutable
class WindowPlaneTexture {
  const WindowPlaneTexture({
    required this.id,
    required this.bufferSize,
    required this.source,
    this.destination = const Rect.fromLTWH(0, 0, 1, 1),
    this.transform = 0,
    this.opacity = 1,
  });

  final int id;
  final Size bufferSize;
  final Rect source;

  /// Destination as fractions of the client area (may extend beyond it).
  final Rect destination;
  final int transform;
  final double opacity;

  bool get isValid =>
      id > 0 &&
      !bufferSize.isEmpty &&
      source.isFinite &&
      !source.isEmpty &&
      destination.isFinite &&
      !destination.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is WindowPlaneTexture &&
      other.id == id &&
      other.bufferSize == bufferSize &&
      other.source == source &&
      other.destination == destination &&
      other.transform == transform &&
      other.opacity == opacity;

  @override
  int get hashCode =>
      Object.hash(id, bufferSize, source, destination, transform, opacity);
}

/// Denial's window rendering primitive.
///
/// The imported-texture constructor issues one window draw: client, cached
/// glass/blur, transparency, analytic rounded edges and colored frame. The
/// child constructor first composes its child (for subsurfaces or Flutter
/// applications), then uses exactly the same final window shader. Neither
/// contract relies on the engine recognizing a widget/clip/paint pattern.
/// Shadows are deliberately independent cached decorations.
class WindowPlane extends SingleChildRenderObjectWidget {
  const WindowPlane.texture({
    super.key,
    required WindowPlaneTexture this.texture,
    this.radius = 0,
    this.frameWidth = 0,
    this.frameColor = const Color(0x00000000),
    this.backdrop,
    this.materialRegion,
    this.translucentCorners,
    this.materialReach = 0,
    this.filterQuality = FilterQuality.none,
    this.presentationScale = 1,
    this.pixelGridOrigin = Offset.zero,
  });

  const WindowPlane.child({
    super.key,
    required super.child,
    this.radius = 0,
    this.frameWidth = 0,
    this.frameColor = const Color(0x00000000),
    this.backdrop,
  }) : texture = null,
       materialRegion = null,
       translucentCorners = null,
       materialReach = 0,
       filterQuality = FilterQuality.none,
       presentationScale = 1,
       pixelGridOrigin = Offset.zero;

  final WindowPlaneTexture? texture;
  final double radius;
  final double frameWidth;
  final Color frameColor;
  final ImageFilterConfig? backdrop;

  /// The part of the client area that receives [backdrop], in fractions of
  /// its size, such as a popup's window geometry inside its client-drawn
  /// shadow. The material takes its shape from it and is only evaluated there.
  final Rect? materialRegion;

  /// The client is opaque everywhere but in a rectangle of this size, in
  /// fractions of the client area, at each corner of it: rounded corners,
  /// as its Wayland opaque region declares them. The window shader adds
  /// [backdrop] only under translucent client pixels, so the material can
  /// show only there, and the plane evaluates it only within
  /// [materialReach] of those corners ([windowPlaneMaterialPieces]).
  final Size? translucentCorners;

  /// How far, in logical pixels, [backdrop] reads the scene around a pixel
  /// it produces (ShellThemeData.windowMaterialReach).
  final double materialReach;
  final FilterQuality filterQuality;
  final double presentationScale;
  final Offset pixelGridOrigin;

  @override
  RenderWindowPlane createRenderObject(BuildContext context) =>
      RenderWindowPlane(this);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderWindowPlane renderObject,
  ) {
    renderObject.configuration = this;
  }
}

class RenderWindowPlane extends RenderShiftedBox {
  RenderWindowPlane(this._configuration) : super(null);

  WindowPlane _configuration;
  set configuration(WindowPlane value) {
    final previous = _configuration;
    _configuration = value;
    if (value.frameWidth != previous.frameWidth) {
      markNeedsLayout();
    } else if (value.texture != previous.texture ||
        value.radius != previous.radius ||
        value.frameColor != previous.frameColor ||
        value.backdrop != previous.backdrop ||
        value.materialRegion != previous.materialRegion ||
        value.translucentCorners != previous.translucentCorners ||
        value.materialReach != previous.materialReach ||
        value.filterQuality != previous.filterQuality ||
        value.presentationScale != previous.presentationScale ||
        value.pixelGridOrigin != previous.pixelGridOrigin) {
      // A rebuild with the same window, as when its card's list rebuilds,
      // keeps the painted plane.
      markNeedsPaint();
    }
  }

  final LayerHandle<_WindowPlaneLayer> _windowLayer = LayerHandle();

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Rect get paintBounds => (Offset.zero & size).inflate(1);

  Rect get _content => (Offset.zero & size).deflate(
    _configuration.frameWidth.clamp(0, size.shortestSide / 2),
  );

  @override
  void performLayout() {
    size = constraints.biggest;
    final content = _content;
    child?.layout(BoxConstraints.tight(content.size), parentUsesSize: true);
    if (child != null) {
      (child!.parentData! as BoxParentData).offset = content.topLeft;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_content.contains(position)) return false;
    return super.hitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final config = _configuration;
    final content = _content.shift(offset);
    final region = config.materialRegion;
    final material = region == null
        ? null
        : Rect.fromLTRB(
            content.left + region.left * content.width,
            content.top + region.top * content.height,
            content.left + region.right * content.width,
            content.top + region.bottom * content.height,
          );
    final backdrop = config.backdrop?.resolve(
      ImageFilterContext(bounds: material ?? content),
    );
    final texture = config.texture;
    final toGlobal = getTransformTo(null);
    WindowPlaneTextureGeometry? geometry;
    if (texture != null) {
      final target = Rect.fromLTWH(
        content.left + texture.destination.left * content.width,
        content.top + texture.destination.top * content.height,
        texture.destination.width * content.width,
        texture.destination.height * content.height,
      );
      geometry = windowPlaneTextureGeometry(
        texture: texture,
        target: target,
        requested: config.filterQuality,
        presentationScale: config.presentationScale,
        // RenderView-relative coordinates are logical, just like the existing
        // external texture viewport. Align only when the buffer still covers
        // the entire fractional viewport after the correction.
        globalOrigin: MatrixUtils.getAsTranslation(toGlobal),
        localTargetOrigin: target.topLeft - offset,
        pixelGridOrigin: config.pixelGridOrigin,
      );
    }
    void configure(_WindowPlaneLayer layer, {required bool withMaterial}) {
      layer
        ..bounds = offset & size
        ..content = content
        ..material = material
        ..radius = config.radius
        ..frameColor = config.frameColor
        ..backdrop = withMaterial ? backdrop : null
        ..texture = texture;
      if (geometry != null) {
        layer
          ..textureBounds = geometry.bounds
          ..textureTransform = geometry.transform
          ..filterQuality = geometry.filterQuality;
      }
      layer.invalidateScene();
    }

    final corners = config.translucentCorners;
    final view = owner?.rootNode;
    final pieces =
        texture != null &&
            backdrop != null &&
            material == null &&
            corners != null &&
            view is RenderView
        ? windowPlaneMaterialPieces(
            bounds: Offset.zero & size,
            content: _content,
            corner: Size(
              corners.width * _content.width,
              corners.height * _content.height,
            ),
            reach: config.materialReach,
            toDevice: Matrix4.diagonal3Values(
              view.configuration.devicePixelRatio,
              view.configuration.devicePixelRatio,
              1,
            )..multiply(toGlobal),
            viewport:
                Offset.zero &
                view.size * view.configuration.devicePixelRatio,
          )
        : null;
    if (pieces == null) {
      _clearPieces(0);
      final layer = _windowLayer.layer ??= _WindowPlaneLayer();
      configure(layer, withMaterial: true);
      context.pushLayer(layer, super.paint, offset);
      return;
    }
    // One window surface per piece, each clipped to it: the corner pieces
    // carry the material, the rest of the window draws the client alone.
    _windowLayer.layer = null;
    _clearPieces(pieces.length);
    for (var index = 0; index < pieces.length; index++) {
      if (index == _pieceLayers.length) {
        _pieceLayers.add(LayerHandle<_WindowPlaneLayer>());
        _pieceClips.add(LayerHandle<ClipRectLayer>());
      }
      final layer = _pieceLayers[index].layer ??= _WindowPlaneLayer();
      configure(layer, withMaterial: pieces[index].material);
      _pieceClips[index].layer = context.pushClipRect(
        true,
        offset,
        pieces[index].clip,
        (context, offset) => context.pushLayer(layer, super.paint, offset),
        oldLayer: _pieceClips[index].layer,
      );
    }
  }

  final List<LayerHandle<_WindowPlaneLayer>> _pieceLayers = [];
  final List<LayerHandle<ClipRectLayer>> _pieceClips = [];

  void _clearPieces(int keep) {
    while (_pieceLayers.length > keep) {
      _pieceLayers.removeLast().layer = null;
      _pieceClips.removeLast().layer = null;
    }
  }

  @override
  void dispose() {
    _windowLayer.layer = null;
    _clearPieces(0);
    super.dispose();
  }
}

/// One part of a window drawn as a window surface of its own: [clip], in the
/// plane's coordinates, and whether that part evaluates the material.
typedef WindowPlanePiece = ({Rect clip, bool material});

// Device pixels beyond the material's own reach that its value at a pixel
// still depends on in Denial's engine: the rounding of the blur's padding,
// its downsample (texels of at most 16 pixels, read up to three apart), the
// bilinear upsample, and the filtering of the client's edges.
const double _materialDeviceMargin = 66;

// Denial's engine downsamples a window's blur on a grid of 1, 2, 4, 8 or 16
// device pixels laid from the pixel-rounded rectangle it evaluates. A corner
// piece the size of that rectangle modulo 16, and lying a multiple of 16
// from its far edges, is sampled on the very same grid.
const double _materialGrid = 16;

// Each interior edge moves this far into both of its pieces, so the scissors
// of neighbours meet at one pixel boundary and no pixel is drawn twice.
const double _pieceSeam = 1 / 64;

/// Splits a window whose client is opaque except in rectangles of [corner]
/// at its corners into the window surfaces that draw it, or returns null to
/// draw it as one.
///
/// The window shader adds the material only under translucent client
/// pixels, and a pixel of the material depends on the scene no farther than
/// [reach] (plus [_materialDeviceMargin]) from it. Four corner pieces that
/// hold every translucent pixel with that reach around it carry the
/// material; three pieces cover the rest of the window with the client
/// alone. Each corner piece evaluates exactly the pixels the whole window
/// would: the same rounded rectangle shapes the glass, its edges on the
/// window's are the same clamping edges, its inner edges are farther than
/// the reach from any pixel that can show, and its size keeps the blur's
/// sampling grid (see [_materialGrid]). The pieces are laid out in device
/// pixels ([toDevice], an axis-aligned transform from the plane's
/// coordinates) and limited to [viewport], the device rectangle the engine
/// clips every material to. Null for any other transform, and when the
/// corner pieces would cover half of the window or more.
List<WindowPlanePiece>? windowPlaneMaterialPieces({
  required Rect bounds,
  required Rect content,
  required Size corner,
  required double reach,
  required Matrix4 toDevice,
  required Rect viewport,
}) {
  final m = toDevice.storage;
  if (m[1] != 0 ||
      m[3] != 0 ||
      m[4] != 0 ||
      m[7] != 0 ||
      m[15] != 1 ||
      m[0] <= 0 ||
      m[5] <= 0) {
    return null;
  }
  final (sx, sy, tx, ty) = (m[0], m[5], m[12], m[13]);
  Rect device(Rect rect) => Rect.fromLTRB(
    rect.left * sx + tx,
    rect.top * sy + ty,
    rect.right * sx + tx,
    rect.bottom * sy + ty,
  );
  final visible = device(content).intersect(viewport);
  if (visible.width <= 0 || visible.height <= 0) return null;
  // The rectangle the engine rounds the whole window's material to.
  final left = visible.left.floorToDouble();
  final top = visible.top.floorToDouble();
  final right = visible.right.ceilToDouble();
  final bottom = visible.bottom.ceilToDouble();
  final width = right - left;
  final height = bottom - top;
  double side(double needed, double extent) =>
      extent -
      _materialGrid * ((extent - needed) / _materialGrid).floorToDouble();
  final pieceWidth = side(
    (corner.width + reach) * sx + _materialDeviceMargin,
    width,
  );
  final pieceHeight = side(
    (corner.height + reach) * sy + _materialDeviceMargin,
    height,
  );
  if (2 * pieceWidth > width ||
      2 * pieceHeight > height ||
      4 * pieceWidth * pieceHeight >= width * height / 2) {
    return null;
  }
  final outer = device(bounds).inflate(2);
  final xs = [
    math.min(outer.left, left),
    left + pieceWidth,
    right - pieceWidth,
    math.max(outer.right, right),
  ];
  final ys = [
    math.min(outer.top, top),
    top + pieceHeight,
    bottom - pieceHeight,
    math.max(outer.bottom, bottom),
  ];
  // Columns from..to and rows from..to of the 3x3 grid xs by ys.
  Rect cell(int fromX, int toX, int fromY, int toY) {
    double edge(List<double> edges, int index, double inward) =>
        index == 1 || index == 2 ? edges[index] + inward : edges[index];
    return Rect.fromLTRB(
      (edge(xs, fromX, _pieceSeam) - tx) / sx,
      (edge(ys, fromY, _pieceSeam) - ty) / sy,
      (edge(xs, toX, -_pieceSeam) - tx) / sx,
      (edge(ys, toY, -_pieceSeam) - ty) / sy,
    );
  }

  return [
    (clip: cell(0, 1, 0, 1), material: true),
    (clip: cell(2, 3, 0, 1), material: true),
    (clip: cell(0, 1, 2, 3), material: true),
    (clip: cell(2, 3, 2, 3), material: true),
    if (xs[1] < xs[2]) (clip: cell(1, 2, 0, 1), material: false),
    if (ys[1] < ys[2]) (clip: cell(0, 3, 1, 2), material: false),
    if (xs[1] < xs[2]) (clip: cell(1, 2, 2, 3), material: false),
  ];
}

typedef WindowPlaneTextureGeometry = ({
  Rect bounds,
  Matrix4 transform,
  FilterQuality filterQuality,
});

/// Pure geometry shared by the primitive's layout and headless tests.
WindowPlaneTextureGeometry windowPlaneTextureGeometry({
  required WindowPlaneTexture texture,
  required Rect target,
  required FilterQuality requested,
  required double presentationScale,
  Offset? globalOrigin,
  Offset localTargetOrigin = Offset.zero,
  Offset pixelGridOrigin = Offset.zero,
}) {
  if (!texture.isValid || target.isEmpty) {
    return (
      bounds: Rect.zero,
      transform: Matrix4.identity(),
      filterQuality: requested,
    );
  }
  final source = texture.source;
  final ratio = presentationScale.isFinite && presentationScale > 0
      ? presentationScale
      : 1.0;
  final integralSource =
      (source.left - source.left.roundToDouble()).abs() < 0.001 &&
      (source.top - source.top.roundToDouble()).abs() < 0.001;
  final nativePixels =
      texture.transform == 0 &&
      integralSource &&
      source.width + 0.001 >= target.width * ratio &&
      source.height + 0.001 >= target.height * ratio &&
      source.width - target.width * ratio <= 1 &&
      source.height - target.height * ratio <= 1;
  final quality = requested == FilterQuality.none && !nativePixels
      ? FilterQuality.low
      : requested;
  final native = quality == FilterQuality.none && nativePixels;
  final quarterTurns = texture.transform & 3;
  final rotated = quarterTurns.isOdd;
  final viewport = rotated ? Size(target.height, target.width) : target.size;
  final sx = native ? 1 / ratio : viewport.width / source.width;
  final sy = native ? 1 / ratio : viewport.height / source.height;
  Offset correction = Offset.zero;
  if (native && globalOrigin != null) {
    double align(
      double origin,
      double extent,
      double sourceExtent,
      double grid,
    ) {
      final start = (origin - grid) * ratio;
      final end = start + extent * ratio;
      double? nearest;
      for (final candidate in [start.floorToDouble(), start.ceilToDouble()]) {
        if (candidate <= start + 0.001 &&
            candidate + sourceExtent >= end - 0.001 &&
            (nearest == null ||
                (candidate - start).abs() < (nearest - start).abs())) {
          nearest = candidate;
        }
      }
      return nearest == null ? 0 : nearest / ratio + grid - origin;
    }

    final origin = globalOrigin + localTargetOrigin;
    correction = Offset(
      align(origin.dx, target.width, source.width, pixelGridOrigin.dx),
      align(origin.dy, target.height, source.height, pixelGridOrigin.dy),
    );
  }
  final transform = Matrix4.translationValues(
    target.left + correction.dx,
    target.top + correction.dy,
    0,
  );
  if (texture.transform & 4 != 0) {
    transform
      ..translateByDouble(target.width, 0, 0, 1)
      ..scaleByDouble(-1, 1, 1, 1);
  }
  switch (quarterTurns) {
    case 1:
      transform.translateByDouble(target.width, 0, 0, 1);
    case 2:
      transform.translateByDouble(target.width, target.height, 0, 1);
    case 3:
      transform.translateByDouble(0, target.height, 0, 1);
  }
  if (quarterTurns != 0) transform.rotateZ(quarterTurns * math.pi / 2);
  return (
    bounds: Rect.fromLTWH(
      -source.left * sx,
      -source.top * sy,
      texture.bufferSize.width * sx,
      texture.bufferSize.height * sy,
    ),
    transform: transform,
    filterQuality: quality,
  );
}

class _WindowPlaneLayer extends ContainerLayer {
  Rect bounds = Rect.zero;
  Rect content = Rect.zero;
  Rect? material;
  double radius = 0;
  Color frameColor = const Color(0x00000000);
  ui.ImageFilter? backdrop;
  WindowPlaneTexture? texture;
  Rect textureBounds = Rect.zero;
  Matrix4 textureTransform = Matrix4.identity();
  FilterQuality filterQuality = FilterQuality.none;

  void invalidateScene() => markNeedsAddToScene();

  @override
  void addToScene(ui.SceneBuilder builder) {
    engineLayer = builder.pushWindowSurface(
      bounds,
      contentBounds: content,
      materialBounds: material,
      radius: radius,
      frameColor: frameColor,
      backdrop: backdrop,
      textureId: texture == null
          ? -1
          : texture!.isValid
          ? texture!.id
          : 0,
      textureBounds: textureBounds,
      textureTransform: textureTransform.storage,
      textureOpacity: texture?.opacity.clamp(0.0, 1.0) ?? 1,
      filterQuality: filterQuality,
      oldLayer: engineLayer as ui.WindowSurfaceEngineLayer?,
    );
    if (texture == null) addChildrenToScene(builder);
    builder.pop();
  }
}
