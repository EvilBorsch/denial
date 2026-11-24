import 'dart:async';

import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The cursor's size is in logical pixels (docs/SCALING.md): it keeps its
// look at every display scale, as clients size theirs from XCURSOR_SIZE. On
// the tablet it was drawn at the size in physical pixels instead, about 14
// logical px at scale 2 and 10 at scale 3 for the setting's 32.

DisplayOutput _output(int id, double left, double scale) => DisplayOutput(
  monitorId: id,
  name: 'out-$id',
  logicalRect: Rect.fromLTWH(left, 0, 1000, 800),
  pixelSize: Size(1000 * scale, 800 * scale),
  scale: scale,
  refreshRate: 120,
);

final _layout = DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: const Size(2000, 800),
  pixelSize: const Size(6000, 2400),
  engineScale: 3,
  tickerMonitorId: 1,
  systemBarMonitorId: 1,
  systemBarSide: SystemBarSide.top,
  outputs: [_output(1, 0, 2), _output(2, 1000, 3)],
);

// The bundled theme, by the keys this package's own tests bundle it under.
final _theme = ShellCursorThemeData(
  id: ShellCursorThemes.bibataModernIce.id,
  label: ShellCursorThemes.bibataModernIce.label,
  author: ShellCursorThemes.bibataModernIce.author,
  assetRoot: 'assets/cursors/bibata_modern_ice',
  roles: ShellCursorThemes.bibataModernIce.roles,
);

void main() {
  testWidgets(
    'the cursor keeps its logical size on displays at scale 2 and 3',
    (tester) async {
      final positions = StreamController<Offset>(sync: true);
      addTearDown(positions.close);
      Future<void> show(double cursorSize) => tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(2000, 800),
            devicePixelRatio: 3,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ShellCursorHost(
              theme: _theme,
              displayLayout: _layout,
              cursorSize: cursorSize,
              platformCursorPositions: positions.stream,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      await show(32);
      for (final position in const [Offset(500, 400), Offset(1500, 400)]) {
        positions.add(position);
        await tester.pump();
        expect(
          tester.getSize(find.byType(Image)),
          const Size(32, 32),
          reason: 'at $position',
        );
      }

      await show(48);
      expect(tester.getSize(find.byType(Image)), const Size(48, 48));
    },
  );
}
