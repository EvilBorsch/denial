import 'package:denial_desktop/src/desktop/window_backdrop_blur_policy.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter_test/flutter_test.dart';

// The glass of the desktop presentation, made cheaper without changing what is
// seen (eb19 track F): windows whose translucency is only an edge band draw no
// material.

DenialWindow _window(
  DenialWindowOpacityClass opacityClass, {
  DenialWindowContentKind contentKind = DenialWindowContentKind.surfaceTree,
  int? heldBy,
}) => DenialWindow(
  objectId: 1,
  objectKind: 'xdg_toplevel',
  surfaceId: 2,
  windowId: 3,
  textureId: 4,
  title: 'Papers',
  appId: 'org.gnome.Papers',
  width: 1357,
  height: 917,
  surfaceX: 0,
  surfaceY: 43,
  surfaceWidth: 1357,
  surfaceHeight: 917,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 1357,
  textureSourceHeight: 917,
  geometryX: 0,
  geometryY: 43,
  geometryWidth: 1357,
  geometryHeight: 917,
  monitorId: 1,
  transform: 0,
  scale120: 300,
  opacityClass: opacityClass,
  contentKind: contentKind,
);

void main() {
  group('window glass', () {
    test('an edge-band translucent window draws no material', () {
      // Its material could show only in the antialiasing fringe of its
      // rounded corners, yet costs a live blur behind the whole window.
      expect(
        desktopWindowNeedsBackdropTexture(
          window: _window(DenialWindowOpacityClass.borderAlphaOnly),
          shellOpacity: 1,
        ),
        isFalse,
      );
      expect(
        desktopWindowNeedsBackdropTexture(
          window: _window(DenialWindowOpacityClass.fullyOpaque),
          shellOpacity: 1,
        ),
        isFalse,
      );
    });

    test('content-translucent and shell-faded windows keep their glass', () {
      expect(
        desktopWindowNeedsBackdropTexture(
          window: _window(DenialWindowOpacityClass.contentTranslucent),
          shellOpacity: 1,
        ),
        isTrue,
      );
      expect(
        desktopWindowNeedsBackdropTexture(
          window: _window(DenialWindowOpacityClass.borderAlphaOnly),
          shellOpacity: 0.9,
        ),
        isTrue,
      );
      expect(
        desktopWindowNeedsBackdropTexture(
          window: _window(DenialWindowOpacityClass.contentTranslucent),
          shellOpacity: 0,
        ),
        isFalse,
      );
    });
  });
}
