import 'package:denial_desktop/src/launcher/home_grid_geometry.dart';
import 'package:denial_desktop/src/launcher/home_pager.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Pad 3's panel and the display scale's steps (one scale per display).
const _panel = Size(3392, 2400);
const _scales = [1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25];

/// Home's pager under the status bar and above the screen's bottom edge
/// (HomeSurface's content padding: 66 and 4).
Size _viewport(double scale) =>
    Size(_panel.width / scale, _panel.height / scale - 66 - 4);

void main() {
  group('home at every display scale, landscape', () {
    for (final scale in _scales) {
      test('${(scale * 100).round()} %: one even grid, the page dots under '
          'it and clear of the home pill', () {
        final viewport = _viewport(scale);
        final geometry = HomeGridGeometry.forViewport(
          viewport,
          inset: HomePager.inset,
          rowGap: HomePager.dotsBand,
        );
        expect(geometry.rows, greaterThanOrEqualTo(3));
        // The last row is one more step down, not a row apart.
        expect(
          geometry.bottomRowTop,
          closeTo((geometry.rows - 1) * geometry.stepY, 0.01),
        );
        expect(
          geometry.rectAt(geometry.columns * (geometry.rows - 1)).top,
          closeTo(
            geometry.rectAt(geometry.columns * (geometry.rows - 2)).top +
                geometry.stepY,
            0.01,
          ),
        );

        final dotsTop = HomePager.dotsTop(geometry, viewport.height);
        expect(dotsTop, greaterThanOrEqualTo(geometry.height + 4));
        // The pill is drawn about 12 px above the screen's bottom edge.
        final screenBottom = _panel.height / scale;
        expect(
          66 + dotsTop + HomePager.dotsReservedHeight,
          lessThanOrEqualTo(screenBottom - 20),
        );
      });
    }
  });

  test('a shared bottom row is the dock: at the bottom, the dots above it', () {
    final viewport = _viewport(3);
    final geometry = HomeGridGeometry.forViewport(
      viewport,
      inset: HomePager.inset,
      rowGap: HomePager.dotsReservedHeight,
      sharedBottomRow: true,
    );
    expect(geometry.sharedBottomRow, isTrue);
    expect(geometry.height, closeTo(viewport.height, 0.01));
    final dotsTop = HomePager.dotsTop(geometry, viewport.height);
    expect(dotsTop, greaterThan((geometry.rows - 2) * geometry.stepY));
    expect(
      dotsTop + HomePager.dotsReservedHeight,
      lessThanOrEqualTo(geometry.bottomRowTop),
    );
  });
}
