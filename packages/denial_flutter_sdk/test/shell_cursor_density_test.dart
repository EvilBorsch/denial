import 'dart:ui' as ui;

import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The bundled cursor comes at 32, 64 and 96 pixels. A 32-point cursor
// covers 32 × scale pixels: from 175 % to 325 % that is 56 to 104, so the
// 32-pixel frame alone was always enlarged, and blurred.
final _bibata = ShellCursorThemes.bibataModernIce;

// The bundled theme by the keys this package's own tests bundle it under.
final _theme = ShellCursorThemeData(
  id: _bibata.id,
  label: _bibata.label,
  author: _bibata.author,
  assetRoot: 'assets/cursors/bibata_modern_ice',
  roles: _bibata.roles,
  assetScales: _bibata.assetScales,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a frame is reduced from the next density up, never enlarged below 3',
    () {
      expect(
        {
          for (final scale in [1.0, 1.75, 2.0, 2.25, 2.5, 3.0, 3.25])
            scale: _bibata.assetScaleFor(scale),
        },
        {1.0: 1, 1.75: 2, 2.0: 2, 2.25: 3, 2.5: 3, 3.0: 3, 3.25: 3},
      );
    },
  );

  test('every role has its 64 and 96 pixel frames', () async {
    for (final kind in ShellCursorKind.values) {
      for (final (pixelScale, pixels) in [(2.25, 96), (2.0, 64), (1.0, 32)]) {
        final provider =
            _theme.imageProvider(kind, 0, pixelScale: pixelScale)!
                as ExactAssetImage;
        expect(provider.scale, pixels / 32);
        final bytes = await rootBundle.load(provider.assetName);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final image = (await codec.getNextFrame()).image;
        expect(
          (image.width, image.height),
          (pixels, pixels),
          reason: provider.assetName,
        );
      }
    }
  });

  test('an imported theme keeps its one density', () {
    final imported = ShellCursorThemeData(
      id: 'imported',
      label: 'Imported',
      author: 'Someone',
      assetRoot: null,
      fileRoot: '/tmp/theme',
      roles: _bibata.roles,
    );
    expect(imported.assetScaleFor(2.25), 1);
    expect(
      imported.imageProvider(ShellCursorKind.normal, 0, pixelScale: 2.25),
      isA<FileImage>(),
    );
  });
}
