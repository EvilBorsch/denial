import 'dart:convert';
import 'dart:io';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home app drawer is on unless the user turned it off (eb18). Files
/// written before then stored `drawer` on every save, chosen or not.
void main() {
  late Directory home;
  late RuntimePaths paths;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('home-drawer');
    paths = RuntimePaths(environment: {'HOME': home.path});
  });
  tearDown(() => home.delete(recursive: true));

  Future<void> writeFile(Map<String, Object?> json) async =>
      (await paths.layoutFile()).writeAsString(jsonEncode(json));

  Future<Map<String, Object?>> readFile() async =>
      jsonDecode(await (await paths.layoutFile()).readAsString())
          as Map<String, Object?>;

  Future<HomeSavedLayouts> read() =>
      HomeLayoutRepository(paths: paths).readSavedLayouts();

  group('reading', () {
    test('without a file the drawer is on and not chosen', () async {
      final saved = await read();
      expect(saved.drawer, isTrue);
      expect(saved.drawerChosen, isFalse);
    });

    test('an eb17 file with the stored default turns the drawer on', () async {
      await writeFile({'version': 5, 'slots': <Object?>[], 'drawer': false});
      final saved = await read();
      expect(saved.drawer, isTrue);
      expect(saved.drawerChosen, isFalse);
    });

    test('an eb17 file with the drawer on keeps it on', () async {
      await writeFile({'version': 5, 'drawer': true});
      final saved = await read();
      expect(saved.drawer, isTrue);
      expect(saved.drawerChosen, isFalse);
    });

    test('a file older than the drawer switch turns it on', () async {
      await writeFile({'version': 3, 'slots': <Object?>[]});
      expect((await read()).drawer, isTrue);
    });

    test('a drawer the user turned off stays off', () async {
      await writeFile({'version': 5, 'drawer': false, 'drawerChosen': true});
      final saved = await read();
      expect(saved.drawer, isFalse);
      expect(saved.drawerChosen, isTrue);
    });

    test('a drawer the user turned on stays on', () async {
      await writeFile({'version': 5, 'drawer': true, 'drawerChosen': true});
      final saved = await read();
      expect(saved.drawer, isTrue);
      expect(saved.drawerChosen, isTrue);
    });

    test('a malformed choice counts as not chosen', () async {
      await writeFile({'drawer': false, 'drawerChosen': 'yes'});
      final saved = await read();
      expect(saved.drawer, isTrue);
      expect(saved.drawerChosen, isFalse);
    });
  });

  group('writing', () {
    test('an unchosen drawer is written as the drawer eb17 shows', () async {
      await HomeLayoutRepository(paths: paths)
          .saveLayouts(const HomeSavedLayouts());
      final json = await readFile();
      // eb17's shell reads `drawer` alone: after a rollback the drawer
      // stays as the user last saw it.
      expect(json['drawer'], isTrue);
      expect(json.containsKey('drawerChosen'), isFalse);
      expect((await read()).drawerChosen, isFalse);
    });

    test('a chosen drawer is written with the choice', () async {
      await HomeLayoutRepository(
        paths: paths,
      ).saveLayouts(const HomeSavedLayouts(drawer: false, drawerChosen: true));
      final json = await readFile();
      expect(json['drawer'], isFalse);
      expect(json['drawerChosen'], isTrue);
      final saved = await read();
      expect(saved.drawer, isFalse);
      expect(saved.drawerChosen, isTrue);
    });
  });

  group('the home grid', () {
    late Directory data;
    late ProviderContainer container;

    setUp(() async {
      data = await Directory.systemTemp.createTemp('home-drawer-data');
      container = ProviderContainer(
        overrides: [
          startupEnvironmentProvider.overrideWithValue(
            StartupEnvironment({
              'HOME': home.path,
              'XDG_DATA_HOME': data.path,
              'XDG_DATA_DIRS': data.path,
            }),
          ),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await data.delete(recursive: true);
    });

    test('starts with the drawer on for an eb17 file', () async {
      await writeFile({'version': 5, 'slots': <Object?>[], 'drawer': false});
      final grid = await container.read(homeGridControllerProvider.future);
      expect(grid.drawer, isTrue);
    });

    test('the page editor switch is saved as the user\'s choice', () async {
      await writeFile({'version': 5, 'slots': <Object?>[], 'drawer': false});
      await container.read(homeGridControllerProvider.future);
      container.read(homeGridControllerProvider.notifier).setDrawer(false);
      expect(
        container.read(homeGridControllerProvider).asData!.value.drawer,
        isFalse,
      );
      // The save is asynchronous and best effort.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final json = await readFile();
        if (json['drawerChosen'] == true) break;
      }
      final json = await readFile();
      expect(json['drawer'], isFalse);
      expect(json['drawerChosen'], isTrue);
      final saved = await read();
      expect(saved.drawer, isFalse);
      expect(saved.drawerChosen, isTrue);
    });
  });
}
