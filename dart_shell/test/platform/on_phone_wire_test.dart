import 'dart:typed_data';

import 'package:denial_flutter_sdk/wire.dart' hide InputWindowRegion;
import 'package:flutter_test/flutter_test.dart';

Uint8List _snapshot(List<WindowObjectBuilder> windows) => EnvelopeObjectBuilder(
  protocolVersion: 1,
  sequence: 1,
  payloadType: PayloadTypeId.WindowSnapshot,
  payload: WindowSnapshotObjectBuilder(windows: windows),
).toBytes('DENW');

WindowObjectBuilder _window(int id, {bool? onPhone}) => WindowObjectBuilder(
  objectId: id,
  surfaceId: id,
  windowId: id,
  textureId: id,
  width: 100,
  height: 80,
  contentWidth: 100,
  contentHeight: 80,
  onPhone: onPhone,
);

void main() {
  test('a window says whether deniald lays it out for the phone', () {
    final codec = DenialWireCodec();
    final decoded = codec.decodeStructured(
      ByteData.sublistView(
        _snapshot(<WindowObjectBuilder>[
          _window(1, onPhone: true),
          _window(2, onPhone: false),
          // An older deniald does not say: the desktop's.
          _window(3),
        ]),
      ),
    );
    final windows = codec.decodeWindows(decoded!.payload as WindowSnapshot)!;
    expect(windows[0].onPhone, isTrue);
    expect(windows[1].onPhone, isFalse);
    expect(windows[2].onPhone, isFalse);
    // Being laid out anew is a change of the window's description, even at
    // the same size.
    expect(windows[0].hasSameSceneDescriptionAs(windows[0]), isTrue);
    final codec2 = DenialWireCodec();
    final desktop = codec2.decodeWindows(
      codec2
              .decodeStructured(
                ByteData.sublistView(
                  _snapshot(<WindowObjectBuilder>[_window(1, onPhone: false)]),
                ),
              )!
              .payload
          as WindowSnapshot,
    )!;
    expect(desktop.single == windows[0], isFalse);
  });
}
