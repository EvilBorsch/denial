import 'dart:typed_data';

import 'package:denial_flutter_sdk/models.dart' show DenialScreenSide;
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/wire.dart' hide InputWindowRegion;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _snapshot(List<WindowObjectBuilder> windows) => EnvelopeObjectBuilder(
  protocolVersion: 1,
  sequence: 1,
  payloadType: PayloadTypeId.WindowSnapshot,
  payload: WindowSnapshotObjectBuilder(windows: windows),
).toBytes('DENW');

WindowObjectBuilder _window(
  int id, {
  int screen = 0,
  WireRectObjectBuilder? rect,
  bool floating = false,
}) => WindowObjectBuilder(
  objectId: id,
  surfaceId: id,
  windowId: id,
  textureId: id,
  width: 100,
  height: 80,
  contentWidth: 100,
  contentHeight: 80,
  layoutScreen: screen,
  layoutScreenRect: rect,
  layoutScreenFloating: floating,
);

void main() {
  test('a window carries its screen of the full-screen apps layout', () {
    final codec = DenialWireCodec();
    final decoded = codec.decodeStructured(
      ByteData.sublistView(
        _snapshot(<WindowObjectBuilder>[
          _window(
            1,
            screen: 3,
            rect: WireRectObjectBuilder(
              x: 2016,
              y: 40,
              width: 1000,
              height: 600,
            ),
          ),
          _window(2, screen: 3, floating: true),
          // A rectangle without a screen is meaningless and dropped.
          _window(
            3,
            rect: WireRectObjectBuilder(x: 0, y: 0, width: 10, height: 10),
          ),
        ]),
      ),
    );
    final windows = codec.decodeWindows(decoded!.payload as WindowSnapshot)!;
    expect(windows[0].layoutScreen, 3);
    expect(
      windows[0].layoutScreenRect,
      const Rect.fromLTWH(2016, 40, 1000, 600),
    );
    expect(windows[0].layoutScreenFloating, isFalse);
    expect(windows[1].layoutScreen, 3);
    expect(windows[1].layoutScreenFloating, isTrue);
    expect(windows[2].layoutScreenRect, isNull);
    // Moving to another screen is a change of the window's description.
    expect(windows[0] == windows[1], isFalse);
  });

  test('screen joins and moves name the dragged window and its target', () {
    final join =
        Envelope(
              DenialWireCodec().encodeWindowRequest(
                WindowRequestKind.JoinScreen,
                windowId: 4,
                targetWindowId: 9,
                screenSide: DenialScreenSide.down.index,
              ),
            ).payload
            as WindowRequest;
    expect(join.kind, WindowRequestKind.JoinScreen);
    expect(join.windowId, 4);
    expect(join.targetWindowId, 9);
    expect(join.screenSide, 3);

    final move =
        Envelope(
              DenialWireCodec().encodeWindowRequest(
                WindowRequestKind.MoveToScreen,
                windowId: 4,
                targetWindowId: 9,
                before: true,
              ),
            ).payload
            as WindowRequest;
    expect(move.kind, WindowRequestKind.MoveToScreen);
    expect(move.before, isTrue);
  });

  test('the side order is the wire order', () {
    expect(DenialScreenSide.values.map((side) => side.index), [0, 1, 2, 3]);
    expect(DenialScreenSide.left.index, 0);
    expect(DenialScreenSide.right.index, 1);
    expect(DenialScreenSide.up.index, 2);
    expect(DenialScreenSide.down.index, 3);
  });

  test(
    'the full-screen apps layout reads from settings and has no workspaces',
    () {
      final settings = ShellSettings.fromJson(<String, dynamic>{
        'layout': <String, dynamic>{
          'windowLayout': 'screens',
          'workspacesEnabled': true,
        },
      });
      expect(settings.layout.windowLayout, DesktopWindowLayout.screens);
      expect(settings.layout.workspacesEnabled, isTrue);
      expect(settings.layout.effectiveWorkspacesEnabled, isFalse);
      final dwindle = settings.layout.copyWith(
        windowLayout: DesktopWindowLayout.dwindle,
      );
      expect(dwindle.effectiveWorkspacesEnabled, isTrue);
      expect((settings.toJson()['layout']! as Map)['windowLayout'], 'screens');

      // A layout this shell does not know falls back to the default.
      final unknown = ShellSettings.fromJson(<String, dynamic>{
        'layout': <String, dynamic>{'windowLayout': 'tiles'},
      });
      expect(unknown.layout.windowLayout, DesktopWindowLayout.stacking);
    },
  );
}
