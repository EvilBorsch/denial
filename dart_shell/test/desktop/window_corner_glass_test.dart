import 'dart:math' as math;

import 'package:denial_flutter_sdk/backdrop_blur_level.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The Pad 3: 3392x2400 pixels at the owner's shell scale 2.
const double scale = 2;
const Rect pad = Rect.fromLTWH(0, 0, 3392, 2400);

// The owner's look: glass, blur sigma 26.1, the default optics.
const ShellThemeData owner = ShellThemeData(
  transparencyMode: ShellTransparencyMode.glass,
  glass: ShellGlassConfiguration(blurSigma: 26.1),
);

// A libadwaita app on one screen of the screens layout: full width under the
// 55 px top bar, translucent only at its 12 px rounded corners.
const Size screenWindow = Size(1696, 1145);
const double libadwaitaCorner = 12;

Matrix4 placedAt(Offset origin, {double cardScale = 1}) =>
    Matrix4.diagonal3Values(scale, scale, 1)
      ..translateByDouble(origin.dx, origin.dy, 0, 1)
      ..scaleByDouble(cardScale, cardScale, 1, 1);

Rect device(Matrix4 toDevice, Rect rect) =>
    MatrixUtils.transformRect(toDevice, rect);

// The engine's scissor for a hard-edged clip, and the pixel-rounded rectangle
// it evaluates a window's material in.
Rect roundOut(Rect rect) => Rect.fromLTRB(
  rect.left.floorToDouble(),
  rect.top.floorToDouble(),
  rect.right.ceilToDouble(),
  rect.bottom.ceilToDouble(),
);

List<WindowPlanePiece>? piecesFor(
  Size window, {
  required Matrix4 toDevice,
  double corner = libadwaitaCorner,
}) => windowPlaneMaterialPieces(
  bounds: Offset.zero & window,
  content: Offset.zero & window,
  corner: Size(corner, corner),
  reach: owner.windowMaterialReach,
  toDevice: toDevice,
  viewport: pad,
);

/// Every property that makes the corner glass look exactly as the whole
/// window's: the pieces cover the window once, every translucent pixel and
/// all it reads lie in a corner piece, and each corner piece rounds to a
/// rectangle on the whole window's blur grid.
void expectSameGlass(
  List<WindowPlanePiece> pieces,
  Size window,
  Matrix4 toDevice, {
  double corner = libadwaitaCorner,
}) {
  final content = device(toDevice, Offset.zero & window);
  final whole = roundOut(content.intersect(pad));
  final scissors = [
    for (final piece in pieces) roundOut(device(toDevice, piece.clip)),
  ];
  // No pixel twice: neighbouring scissors share edges only.
  for (var a = 0; a < scissors.length; a++) {
    for (var b = a + 1; b < scissors.length; b++) {
      final overlap = scissors[a].intersect(scissors[b]);
      expect(
        overlap.width <= 0 || overlap.height <= 0,
        isTrue,
        reason: 'pieces $a and $b overlap',
      );
    }
  }
  // No pixel left out.
  final covered = scissors.fold<double>(
    0,
    (sum, rect) =>
        sum +
        math.max(0, rect.intersect(whole).width) *
            math.max(0, rect.intersect(whole).height),
  );
  expect(covered, whole.width * whole.height);

  final reach = owner.windowMaterialReach * toDevice.storage[0];
  final sides = [
    for (final piece in pieces.where((piece) => piece.material))
      roundOut(device(toDevice, piece.clip).intersect(content).intersect(pad)),
  ];
  expect(sides, hasLength(4));
  final cornerSize = corner * toDevice.storage[0];
  final translucent = [
    Rect.fromLTWH(content.left, content.top, cornerSize, cornerSize),
    Rect.fromLTWH(
      content.right - cornerSize,
      content.top,
      cornerSize,
      cornerSize,
    ),
    Rect.fromLTWH(
      content.left,
      content.bottom - cornerSize,
      cornerSize,
      cornerSize,
    ),
    Rect.fromLTWH(
      content.right - cornerSize,
      content.bottom - cornerSize,
      cornerSize,
      cornerSize,
    ),
  ];
  for (final square in translucent) {
    final visible = square.intersect(pad);
    if (visible.width <= 0 || visible.height <= 0) continue;
    // Within one piece together with everything its material reads.
    final needs = visible.inflate(reach).intersect(whole);
    expect(
      sides.any(
        (side) =>
            side.contains(needs.topLeft) &&
            side.contains(needs.bottomRight - const Offset(0.01, 0.01)),
      ),
      isTrue,
      reason: 'the corner $square and its reach lie in no material piece',
    );
  }
  for (final side in sides) {
    expect((whole.width - side.width) % 16, 0);
    expect((whole.height - side.height) % 16, 0);
    expect((side.left - whole.left) % 16, 0);
    expect((side.top - whole.top) % 16, 0);
  }
}

void main() {
  test('the owner\'s glass reads the scene up to its blur and refraction', () {
    // 1.75 sigma of the frost, and the glass's largest refraction: thickness
    // 25, eight times over at the default bevel, depth 1.1, index 1.04.
    final refraction = 25 * 8 * 1.1 * math.sqrt(1.04 * 1.04 - 1);
    expect(owner.windowMaterialReach, closeTo(1.75 * 26.1 + refraction, 1e-9));
    const blurOnly = ShellThemeData(
      backdropBlurLevel: ShellBackdropBlurLevel.fast,
    );
    expect(
      blurOnly.windowMaterialReach,
      1.75 * ShellBackdropBlurLevel.fast.sigma,
    );
  });

  test(
    'a full-screen app evaluates its glass only around its four corners',
    () {
      final toDevice = placedAt(const Offset(0, 55));
      final pieces = piecesFor(screenWindow, toDevice: toDevice)!;
      expect(pieces.where((piece) => piece.material), hasLength(4));
      expect(pieces.where((piece) => !piece.material), hasLength(3));
      expectSameGlass(pieces, screenWindow, toDevice);
      final material = pieces
          .where((piece) => piece.material)
          .map((piece) => device(toDevice, piece.clip).intersect(pad))
          .fold<double>(0, (sum, rect) => sum + rect.width * rect.height);
      // Under a fifteenth of the window instead of all of it.
      expect(material, lessThan(pad.width * 2290 / 15));
    },
  );

  test('an app sliding along the strip keeps the same glass at every frame', () {
    for (final x in [-1033.37, -401.5, 0.25, 123.37, 840.81, 1500.06]) {
      final toDevice = placedAt(Offset(x, 55));
      final pieces = piecesFor(screenWindow, toDevice: toDevice);
      if (pieces == null) {
        // So far off screen that its corners' pieces would cover half of
        // what is left: one material, as before.
        expect(x.abs(), greaterThan(1000));
        continue;
      }
      expectSameGlass(pieces, screenWindow, toDevice);
    }
  });

  test('cards too small for corner pieces keep one material', () {
    // An overview card: the material's reach covers most of it.
    expect(
      piecesFor(
        const Size(520, 352),
        toDevice: placedAt(const Offset(80, 300)),
      ),
      isNull,
    );
    // A rotated window: no axis-aligned pieces.
    expect(
      piecesFor(
        screenWindow,
        toDevice: Matrix4.rotationZ(0.1)..scaleByDouble(scale, scale, 1, 1),
      ),
      isNull,
    );
  });
}
