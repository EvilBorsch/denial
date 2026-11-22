import 'package:denial_desktop/src/widgets/shade/quick_settings_tiles.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

QuickTile _square([String title = 'square']) => QuickTile(
  key: ValueKey(title),
  icon: Icons.circle,
  title: title,
  active: false,
  onTap: () {},
);

QuickTile _wide([String title = 'wide']) => QuickTile(
  key: ValueKey(title),
  icon: Icons.circle,
  title: title,
  active: false,
  onTap: () {},
  wide: true,
);

void main() {
  test('footer tiles fill a row of four columns left to right', () {
    expect(quickSettingsFooterCells(const []), isEmpty);
    // Two square tiles beside the wide Desktop mode tile fill one row.
    expect(quickSettingsFooterCells([_square(), _square(), _wide()]), [
      (0, 0),
      (0, 1),
      (0, 2),
    ]);
    expect(quickSettingsFooterCells([_wide(), _wide()]), [(0, 0), (0, 2)]);
  });

  test('a tile that does not fit starts the next footer row', () {
    // A third square tile, such as Screen recording, moves Desktop mode to a
    // second row.
    expect(
      quickSettingsFooterCells([_square(), _square(), _square(), _wide()]),
      [(0, 0), (0, 1), (0, 2), (1, 0)],
    );
    expect(
      quickSettingsFooterCells([
        _square(),
        _square(),
        _square(),
        _square(),
        _square(),
      ]),
      [(0, 0), (0, 1), (0, 2), (0, 3), (1, 0)],
    );
    expect(quickSettingsFooterCells([_wide(), _square(), _wide()]), [
      (0, 0),
      (0, 2),
      (1, 0),
    ]);
  });

  testWidgets('a wrapped footer lays its second row below the first', (
    tester,
  ) async {
    // The landscape tablet's control column: 554 wide, tiles half again as
    // tall as the reference. The grid keeps its reference spacing.
    const width = 554.0;
    const gutter = 14.0;
    const capsule = 62 * 1.5;
    const row = capsule + 14;
    const column = (width - gutter * 3) / 4;
    await tester.pumpWidget(
      DenialLocalizationScope(
        locale: const Locale('en'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: QuickSettingsTiles(
                heightFactor: 1.5,
                footerTiles: [
                  _square('a'),
                  _square('b'),
                  _square('c'),
                  _wide('d'),
                ],
                wifi: false,
                wifiSubtitle: '',
                wifiEnabled: true,
                wifiBusy: false,
                bluetooth: false,
                bluetoothSubtitle: '',
                bluetoothEnabled: true,
                bluetoothBusy: false,
                dnd: false,
                dndReady: true,
                profile: null,
                onToggleWifi: () {},
                onOpenWifi: () {},
                onToggleBluetooth: () {},
                onOpenBluetooth: () {},
                onToggleDnd: () {},
                onCycleProfile: () {},
              ),
            ),
          ),
        ),
      ),
    );

    const firstTop = row * 3 + gutter;
    const secondTop = firstTop + row + gutter;
    Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
    expect(at('a'), const Rect.fromLTWH(0, firstTop, column, row));
    expect(
      at('b'),
      const Rect.fromLTWH(column + gutter, firstTop, column, row),
    );
    expect(
      at('c'),
      const Rect.fromLTWH((column + gutter) * 2, firstTop, column, row),
    );
    // A row of wide tiles alone is a capsule tall.
    expect(
      at('d'),
      const Rect.fromLTWH(0, secondTop, column * 2 + gutter, capsule),
    );
    expect(
      tester.getSize(find.byType(QuickSettingsTiles)).height,
      secondTop + capsule,
    );
  });
}
