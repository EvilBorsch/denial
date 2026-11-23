import 'dart:typed_data';

import 'package:denial_flutter_sdk/wire.dart' hide InputWindowRegion;
import 'package:flutter_test/flutter_test.dart';

Uint8List _snapshot(List<WindowObjectBuilder> windows) => EnvelopeObjectBuilder(
  protocolVersion: 1,
  sequence: 1,
  payloadType: PayloadTypeId.WindowSnapshot,
  payload: WindowSnapshotObjectBuilder(windows: windows),
).toBytes('DENW');

WindowObjectBuilder _window(int id, {int partner = 0, double ratio = 0}) =>
    WindowObjectBuilder(
      objectId: id,
      surfaceId: id,
      windowId: id,
      textureId: id,
      width: 100,
      height: 80,
      contentWidth: 100,
      contentHeight: 80,
      splitViewPartnerId: partner,
      splitViewRatio: ratio,
    );

void main() {
  test('a window in Split View carries its partner and the share', () {
    final codec = DenialWireCodec();
    final decoded = codec.decodeStructured(
      ByteData.sublistView(
        _snapshot(<WindowObjectBuilder>[
          _window(1, partner: 2, ratio: 2 / 3),
          _window(2, partner: 1, ratio: 2 / 3),
          _window(3),
          // A share no pair can have is no pair.
          _window(4, partner: 5, ratio: 1.5),
        ]),
      ),
    );
    final windows = codec.decodeWindows(decoded!.payload as WindowSnapshot)!;
    expect(windows[0].splitViewPartnerObjectId, 2);
    expect(windows[0].splitViewRatio, closeTo(2 / 3, 1e-12));
    expect(windows[0].inSplitView, isTrue);
    expect(windows[1].splitViewPartnerObjectId, 1);
    expect(windows[2].splitViewPartnerObjectId, isNull);
    expect(windows[2].splitViewRatio, 0);
    expect(windows[2].inSplitView, isFalse);
    expect(windows[3].inSplitView, isFalse);
    // Joining or leaving a pair is a change of the window's description.
    final codec2 = DenialWireCodec();
    final alone = codec2.decodeWindows(
      codec2
              .decodeStructured(
                ByteData.sublistView(
                  _snapshot(<WindowObjectBuilder>[_window(1)]),
                ),
              )!
              .payload
          as WindowSnapshot,
    )!;
    expect(alone[0] == windows[0], isFalse);
  });

  test('Split View requests name both windows, the side and the share', () {
    final split =
        Envelope(
              DenialWireCodec().encodeWindowRequest(
                WindowRequestKind.SplitView,
                windowId: 4,
                targetWindowId: 9,
                screenSide: 1,
                splitRatio: 1 / 3,
              ),
            ).payload
            as WindowRequest;
    expect(split.kind, WindowRequestKind.SplitView);
    expect(split.windowId, 4);
    expect(split.targetWindowId, 9);
    expect(split.screenSide, 1);
    expect(split.splitRatio, closeTo(1 / 3, 1e-12));

    final leave =
        Envelope(
              DenialWireCodec().encodeWindowRequest(
                WindowRequestKind.LeaveSplitView,
                windowId: 9,
              ),
            ).payload
            as WindowRequest;
    expect(leave.kind, WindowRequestKind.LeaveSplitView);
    expect(leave.windowId, 9);
  });
}
