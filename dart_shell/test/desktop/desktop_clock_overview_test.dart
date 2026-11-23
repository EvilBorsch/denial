import 'package:denial_clock/denial_clock.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ShellSurfaceEnvironment _environment({
  bool overview = false,
  bool locked = false,
}) => ShellSurfaceEnvironment(
  output: const DisplayOutput(
    monitorId: 1,
    name: 'DSI-1',
    logicalRect: Rect.fromLTWH(0, 0, 2261, 1600),
    pixelSize: Size(3392, 2400),
    scale: 1.5,
    refreshRate: 120,
  ),
  workArea: const Rect.fromLTWH(0, 40, 2261, 1560),
  isMainOutput: true,
  workspaceId: 1,
  fullscreen: false,
  overview: overview,
  desktopVisible: false,
  wallpaperSelectorVisible: false,
  locked: locked,
  settings: const ShellSettings(),
  defaultOutputSelected: true,
);

void main() {
  test('the desktop clock steps aside for the overview', () {
    const clock = DesktopClockPlugin();
    final desktop = clock.place(_environment());
    expect(desktop, isNotNull);
    expect(desktop!.visible, isTrue);

    // The overview dims the desktop behind its cards; the clock is not part
    // of it. It stays placed, so it fades back with its state when the
    // overview closes.
    final overview = clock.place(_environment(overview: true));
    expect(overview, isNotNull);
    expect(overview!.visible, isFalse);
    expect(overview.bounds, desktop.bounds);

    expect(clock.place(_environment(locked: true))!.visible, isFalse);
  });
}
