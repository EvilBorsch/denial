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
// 55 px top bar.
const Size screenWindow = Size(1696, 1145);

// What its opaque region leaves out. GTK 4.16 and later declare the largest
// rectangle the window rounded by 15 px covers: the bands above and below
// it. Older GTK declares the four rounded corners.
List<Rect> gtk4Bands(Size window) => [
  Rect.fromLTWH(0, 0, window.width, 15),
  Rect.fromLTWH(0, window.height - 15, window.width, 15),
];

List<Rect> olderGtkCorners(Size window) => [
  const Rect.fromLTWH(0, 0, 12, 12),
  Rect.fromLTWH(window.width - 12, 0, 12, 12),
  Rect.fromLTWH(0, window.height - 12, 12, 12),
  Rect.fromLTWH(window.width - 12, window.height - 12, 12, 12),
];

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
  Size window,
  List<Rect> translucent, {
  required Matrix4 toDevice,
}) => windowPlaneMaterialPieces(
  bounds: Offset.zero & window,
  content: Offset.zero & window,
  translucent: translucent,
  reach: owner.windowMaterialReach,
  toDevice: toDevice,
  viewport: pad,
);

/// Every property that makes the pieces' glass look exactly as the whole
/// window's: the pieces cover the window once, every translucent part and
/// all its material reads lie in one material piece, and each material piece
/// rounds to a rectangle on the whole window's blur grid.
void expectSameGlass(
  List<WindowPlanePiece> pieces,
  Size window,
  List<Rect> translucent,
  Matrix4 toDevice,
) {
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
  double area(Rect rect) =>
      math.max(0, rect.width) * math.max(0, rect.height);
  final covered = scissors.fold<double>(
    0,
    (sum, rect) => sum + area(rect.intersect(whole)),
  );
  expect(covered, whole.width * whole.height);

  final reach = owner.windowMaterialReach * toDevice.storage[0];
  final sides = [
    for (final piece in pieces.where((piece) => piece.material))
      roundOut(device(toDevice, piece.clip).intersect(content).intersect(pad)),
  ];
  expect(sides, isNotEmpty);
  for (final part in translucent) {
    final visible = device(toDevice, part).intersect(pad);
    if (visible.width <= 0 || visible.height <= 0) continue;
    final needs = visible.inflate(reach).intersect(whole);
    expect(
      sides.any(
        (side) =>
            side.contains(needs.topLeft) &&
            side.contains(needs.bottomRight - const Offset(0.01, 0.01)),
      ),
      isTrue,
      reason: 'the translucent part $part and its reach lie in no piece',
    );
  }
  for (final side in sides) {
    expect((side.left - whole.left) % 16, 0);
    expect((side.top - whole.top) % 16, 0);
    expect((whole.right - side.right) % 16, 0);
    expect((whole.bottom - side.bottom) % 16, 0);
  }
}

double materialShare(List<WindowPlanePiece> pieces, Matrix4 toDevice) {
  final material = pieces
      .where((piece) => piece.material)
      .map((piece) => device(toDevice, piece.clip).intersect(pad))
      .fold<double>(0, (sum, rect) => sum + rect.width * rect.height);
  return material / (pad.width * 2290);
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
    'a full-screen GTK 4 app evaluates its glass only along top and bottom',
    () {
      final toDevice = placedAt(const Offset(0, 55));
      final bands = gtk4Bands(screenWindow);
      final pieces = piecesFor(screenWindow, bands, toDevice: toDevice)!;
      expect(pieces.where((piece) => piece.material), hasLength(2));
      expect(pieces.where((piece) => !piece.material), hasLength(1));
      expectSameGlass(pieces, screenWindow, bands, toDevice);
      // A third of the window instead of all of it.
      expect(materialShare(pieces, toDevice), lessThan(0.36));
    },
  );

  test('an app of older GTK evaluates its glass only around its corners', () {
    final toDevice = placedAt(const Offset(0, 55));
    final corners = olderGtkCorners(screenWindow);
    final pieces = piecesFor(screenWindow, corners, toDevice: toDevice)!;
    expect(pieces.where((piece) => piece.material), hasLength(4));
    expectSameGlass(pieces, screenWindow, corners, toDevice);
    expect(materialShare(pieces, toDevice), lessThan(1 / 15));
  });

  test('an app sliding along the strip keeps the same glass at every frame', () {
    for (final parts in [gtk4Bands, olderGtkCorners]) {
      for (final x in [-1033.37, -401.5, 0.25, 123.37, 840.81, 1500.06]) {
        final toDevice = placedAt(Offset(x, 55));
        final translucent = parts(screenWindow);
        final pieces = piecesFor(
          screenWindow,
          translucent,
          toDevice: toDevice,
        );
        if (pieces == null) {
          // So far off screen that its material pieces would cover most of
          // what is left: one material, as before.
          expect(x.abs(), greaterThan(1000));
          continue;
        }
        expectSameGlass(pieces, screenWindow, translucent, toDevice);
      }
    }
  });

  test('one material where pieces would cover most of the window', () {
    // An overview card: the material's reach covers most of it.
    const card = Size(520, 352);
    expect(
      piecesFor(
        card,
        gtk4Bands(card),
        toDevice: placedAt(const Offset(80, 300)),
      ),
      isNull,
    );
    // Translucent along every edge.
    expect(
      piecesFor(screenWindow, [
        ...gtk4Bands(screenWindow),
        const Rect.fromLTWH(0, 0, 15, 1145),
        const Rect.fromLTWH(1681, 0, 15, 1145),
      ], toDevice: placedAt(const Offset(0, 55))),
      isNull,
    );
    // A window resized on its way into the overview, between whole device
    // pixels: the material there is sampled at fractional positions.
    const shrinking = Size(1500.3, 1012.7);
    expect(
      piecesFor(
        shrinking,
        gtk4Bands(shrinking),
        toDevice: placedAt(const Offset(98.4, 120.2)),
      ),
      isNull,
    );
    // A rotated window: no axis-aligned pieces.
    expect(
      piecesFor(
        screenWindow,
        gtk4Bands(screenWindow),
        toDevice: Matrix4.rotationZ(0.1)..scaleByDouble(scale, scale, 1, 1),
      ),
      isNull,
    );
  });
}
