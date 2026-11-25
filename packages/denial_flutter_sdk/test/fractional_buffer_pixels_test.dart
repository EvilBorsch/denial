import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// At 225 % a window 701 points wide is 1577.25 pixels. A fractional-scale-v1
// client rounds its buffer to 1577 pixels; one that rounds up sends 1578.
const _scale = 2.25;
const _target = Size(701, 400);

WindowPlaneTextureGeometry _plane(double bufferWidth, {Offset at = Offset.zero}) {
  final buffer = Size(bufferWidth, _target.height * _scale);
  return windowPlaneTextureGeometry(
    texture: WindowPlaneTexture(id: 7, bufferSize: buffer, source: Offset.zero & buffer),
    target: Offset.zero & _target,
    requested: FilterQuality.none,
    presentationScale: _scale,
    globalOrigin: at,
  );
}

DenialSurfaceLayer _layer(int bufferWidth) => DenialSurfaceLayer(
  surfaceId: 1,
  parentSurfaceId: 0,
  popupRootSurfaceId: 0,
  role: DenialSurfaceRole.root,
  textureId: 9,
  width: bufferWidth,
  height: 900,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: _target.width,
  surfaceHeight: _target.height,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: bufferWidth.toDouble(),
  textureSourceHeight: 900,
  transform: 0,
  scale120: 270,
  compositionOrder: 0,
);

void main() {
  group('a window plane at a fractional scale', () {
    for (final width in [1577.0, 1578.0]) {
      test('draws a $width-pixel buffer pixel for pixel', () {
        final geometry = _plane(width);
        expect(geometry.filterQuality, FilterQuality.none);
        expect(geometry.bounds.width * _scale, closeTo(width, 1e-9));
      });
    }

    test('puts a rounded-down buffer on the pixel grid', () {
      // 101 points is 227.25 pixels: no whole pixel lets 1577 cover the
      // window, so the buffer starts at the nearest one.
      final geometry = _plane(1577, at: const Offset(101, 40));
      final left = (101 + geometry.transform.getTranslation().x) * _scale;
      expect(left, closeTo(227, 1e-9));
    });

    test('still filters a buffer drawn at another scale', () {
      // GTK3 draws at the integer scale above, 3: 2103 pixels.
      expect(_plane(2103).filterQuality, FilterQuality.low);
    });
  });

  for (final width in [1577, 1578]) {
    testWidgets('a surface layer samples a $width-pixel buffer without filtering', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: _target,
              child: SurfaceLayerTexture(layer: _layer(width), presentationScale: _scale),
            ),
          ),
        ),
      );
      final texture = tester.widget<Texture>(find.byType(Texture));
      expect(texture.filterQuality, FilterQuality.none);
      expect(tester.getSize(find.byType(Texture)).width * _scale, closeTo(width, 1e-9));
    });
  }
}
