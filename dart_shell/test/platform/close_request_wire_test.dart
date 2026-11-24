import 'dart:typed_data';

import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/wire.dart' as wire;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Recents closes an app as the window's own close button does: deniald
  // turns this request into xdg_toplevel.close (WM_DELETE_WINDOW for X11),
  // which the app may answer with a question. Nothing in the wire protocol
  // kills a client.
  test('closing a window is a close request to its app, not a kill', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final sent = <wire.Envelope>[];
    messenger.setMockMessageHandler(wire.denialWireToNativeChannel, (
      data,
    ) async {
      sent.add(
        wire.Envelope(
          Uint8List.fromList(
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        ),
      );
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMessageHandler(wire.denialWireToNativeChannel, null),
    );
    final bridge = DenialBridge();
    addTearDown(bridge.dispose);
    final window = phoneWindow(4, 'org.gnome.TextEditor');

    bridge.closeWindow(window);
    await Future<void>.delayed(Duration.zero);

    expect(sent, hasLength(1));
    expect(sent.single.payloadType, wire.PayloadTypeId.WindowRequest);
    final request = sent.single.payload as wire.WindowRequest;
    expect(request.kind, wire.WindowRequestKind.CloseWindow);
    expect(request.windowId, window.windowId);
  });
}
