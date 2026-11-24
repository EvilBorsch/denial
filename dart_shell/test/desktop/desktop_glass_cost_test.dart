import 'package:denial_desktop/src/desktop/desktop_overview_hub.dart';
import 'package:denial_desktop/src/desktop/desktop_wallpaper_backdrop.dart';
import 'package:denial_desktop/src/desktop/window_backdrop_blur_policy.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/surface_hosting.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The glass of the desktop presentation, made cheaper without changing what is
// seen (eb19 track F): windows whose translucency is only an edge band draw no
// material, and the overview's glass comes from the wallpaper frosted once.

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

final class _Surface implements ShellSurface {
  const _Surface(this.layer, {required this.visible});

  @override
  final ShellSurfaceLayer layer;
  final bool visible;

  @override
  String get id => 'test.surface.${layer.name}';

  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) =>
      ShellSurfacePlacement(
        bounds: const Rect.fromLTWH(100, 100, 200, 200),
        visible: visible,
      );

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) =>
      const SizedBox.shrink();
}

ShellSurfaceEntry _entry(ShellSurfaceLayer layer, {required bool visible}) {
  const environment = ShellSurfaceEnvironment(
    output: DisplayOutput(
      monitorId: 1,
      name: 'DSI-1',
      logicalRect: Rect.fromLTWH(0, 0, 1357, 960),
      pixelSize: Size(3392, 2400),
      scale: 2.5,
      refreshRate: 120,
    ),
    workArea: Rect.fromLTWH(0, 43, 1357, 917),
    isMainOutput: true,
    workspaceId: 1,
    fullscreen: false,
    overview: true,
    desktopVisible: false,
    wallpaperSelectorVisible: false,
    locked: false,
    settings: ShellSettings(),
    defaultOutputSelected: true,
  );
  final surface = _Surface(layer, visible: visible);
  return ShellSurfaceEntry(
    surface: surface,
    environment: environment,
    placement: surface.place(environment)!,
  );
}

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

  group('the overview backdrop is the wallpaper', () {
    test('when nothing else lies between the wallpaper and the overview', () {
      expect(
        desktopBackdropIsWallpaper(
          coveredOutputs: const <String>{},
          layerSurfaces: const <DenialWindow>[],
          surfaceEntries: [
            // The desktop clock steps aside for the overview.
            _entry(ShellSurfaceLayer.desktop, visible: false),
            _entry(ShellSurfaceLayer.aboveWindows, visible: true),
          ],
          desktopPlaneWindows: 0,
        ),
        isTrue,
      );
    });

    test('not with a client wallpaper, a desktop surface or window', () {
      bool backdrop({
        Set<String> covered = const <String>{},
        List<DenialWindow> layers = const <DenialWindow>[],
        List<ShellSurfaceEntry> entries = const <ShellSurfaceEntry>[],
        int planeWindows = 0,
      }) => desktopBackdropIsWallpaper(
        coveredOutputs: covered,
        layerSurfaces: layers,
        surfaceEntries: entries,
        desktopPlaneWindows: planeWindows,
      );
      expect(backdrop(covered: const {'DSI-1'}), isFalse);
      expect(
        backdrop(
          layers: [
            _window(
              DenialWindowOpacityClass.fullyOpaque,
              contentKind: DenialWindowContentKind.layerShellBottom,
            ),
          ],
        ),
        isFalse,
      );
      expect(
        backdrop(
          layers: [
            _window(
              DenialWindowOpacityClass.fullyOpaque,
              contentKind: DenialWindowContentKind.layerShellTop,
            ),
          ],
        ),
        isTrue,
      );
      expect(
        backdrop(entries: [_entry(ShellSurfaceLayer.desktop, visible: true)]),
        isFalse,
      );
      expect(backdrop(planeWindows: 1), isFalse);
    });
  });

  testWidgets('without a frost the overview filters the scene live', (
    tester,
  ) async {
    // A frost made with the current material replaces the live filter with a
    // WindowBackdropSlice; resolving the material needs Denial's engine, so
    // that half is checked on the tablet (tools/tab/eb19-frames.sh).
    final opacity = ValueNotifier<double>(0.5);
    addTearDown(opacity.dispose);
    var live = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: desktopFrostedBackdrop(
          frost: null,
          scrim: const Color(0x66000000),
          opacity: opacity,
          live: () {
            live++;
            return const SizedBox.expand(key: ValueKey('live'));
          },
        ),
      ),
    );
    expect(find.byKey(const ValueKey('live')), findsOneWidget);
    expect(find.byType(WindowBackdropSlice), findsNothing);
    expect(live, 1);
  });
}
