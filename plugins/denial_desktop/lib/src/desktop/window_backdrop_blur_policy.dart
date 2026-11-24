import 'package:denial_flutter_sdk/models.dart';

/// Whether a desktop window draws the glass material behind its client.
///
/// The window primitive applies the material only where the client's alpha
/// is above the backdrop alpha threshold, and the client's pixels cover it as
/// far as they are opaque. A window whose opaque region proves everything
/// but a narrow edge band ([DenialWindowOpacityClass.borderAlphaOnly]: rounded
/// corners, antialiased borders) could show it only in its edge's
/// antialiasing fringe. Evaluating it there still filters the live scene
/// behind the whole window on every frame the window moves: on the 3392×2400
/// Pad 3 two full-screen GTK windows sliding in the screens layout cost
/// 4–6 ms of GPU per frame for it, most of a 120 Hz frame. Such a window
/// therefore draws no material; a content-translucent window, and every
/// window the shell itself makes translucent, keep it.
bool desktopWindowNeedsBackdropTexture({
  required DenialWindow window,
  required double shellOpacity,
  bool localContentTranslucent = false,
}) {
  if (shellOpacity <= 0.0) {
    return false;
  }

  if (window.isLocalFlutter) {
    return localContentTranslucent || shellOpacity < 1.0;
  }
  return window.isContentTranslucent || shellOpacity < 1.0;
}
