import 'package:denial_desktop/src/desktop/desktop_search_overlay.dart';
import 'package:denial_desktop/src/state/reference_shell_metrics.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The tablet's panel at the shell's scale 2, under a 40 px top bar.
  const view = Size(1696, 1200);
  const workArea = Rect.fromLTRB(0, 40, 1696, 1200);

  test('the one search keeps its place without the screen keyboard', () {
    final panel = DesktopSearchOverlay.panelBounds(workArea);
    expect(panel.width, 880);
    expect(panel.height, closeTo(928, 0.01));
    expect(panel.center.dx, 848);
  });

  test('a finger opens the one search with the screen keyboard: every '
      'result sits above it', () {
    final keyboardTop =
        view.height -
        ReferenceShellMetrics.edgePanelHeight(view, shortcuts: false);
    final alone = DesktopSearchOverlay.panelBounds(workArea);
    final panel = DesktopSearchOverlay.panelBounds(
      workArea,
      keyboardTop: keyboardTop,
    );
    expect(alone.bottom, greaterThan(keyboardTop));
    expect(panel.top, alone.top);
    expect(panel.bottom, lessThanOrEqualTo(keyboardTop - 16));
    expect(panel.height, greaterThan(300));
  });

  test('the keyboard sliding in shrinks the panel with it', () {
    final full = ReferenceShellMetrics.edgePanelHeight(view, shortcuts: false);
    final bottoms = [
      for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0])
        DesktopSearchOverlay.panelBounds(
          workArea,
          keyboardTop: view.height - full * progress,
        ).bottom,
    ];
    for (var i = 1; i < bottoms.length; i++) {
      expect(bottoms[i], lessThanOrEqualTo(bottoms[i - 1]));
    }
  });
}
