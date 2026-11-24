import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/surface_hosting.dart' show ShellSurfaceEntry;
import 'package:denial_flutter_sdk/surfaces.dart' show ShellSurfaceLayer;

/// Whether the shell's own wallpaper is all that lies behind the overview's
/// glass, so that glass can be drawn from the wallpaper frosted once.
///
/// Anything else between the wallpaper and the overview would be missing from
/// that image: a client wallpaper covering an output ([coveredOutputs]), a
/// layer-shell background or bottom surface, a visible desktop-plane shell
/// surface, or a window shown on the desktop plane ([desktopPlaneWindows],
/// such as a minimized window kept on the desktop). Any of them keeps the live
/// filter. Surfaces that step aside for the overview, as the desktop clock
/// does, are not visible there and do not count.
bool desktopBackdropIsWallpaper({
  required Set<String> coveredOutputs,
  required Iterable<DenialWindow> layerSurfaces,
  required Iterable<ShellSurfaceEntry> surfaceEntries,
  required int desktopPlaneWindows,
}) {
  if (coveredOutputs.isNotEmpty || desktopPlaneWindows > 0) {
    return false;
  }
  for (final surface in layerSurfaces) {
    if (!surface.isHeld &&
        (surface.contentKind == DenialWindowContentKind.layerShellBackground ||
            surface.contentKind == DenialWindowContentKind.layerShellBottom)) {
      return false;
    }
  }
  for (final entry in surfaceEntries) {
    if (entry.surface.layer == ShellSurfaceLayer.desktop &&
        entry.placement.visible) {
      return false;
    }
  }
  return true;
}
