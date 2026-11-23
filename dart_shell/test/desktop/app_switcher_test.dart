import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_desktop/src/state/desktop_app_switcher.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The app switcher follows deniald's Alt+Tab steps (wire actions
// AppSwitcherNext/Previous/WindowNext/WindowPrevious/End/Cancel): which app
// and window a step selects, and which window the release activates.

DenialWindow _window(int id, String app) {
  const frame = Rect.fromLTWH(0, 40, 1357, 920);
  return DenialWindow(
    objectId: id,
    objectKind: 'xdg',
    surfaceId: id + 100,
    windowId: id + 200,
    textureId: id + 300,
    title: '$app $id',
    appId: app,
    width: frame.width.round(),
    height: frame.height.round(),
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: frame.width,
    surfaceHeight: frame.height,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: frame.width,
    textureSourceHeight: frame.height,
    geometryX: frame.left,
    geometryY: frame.top,
    geometryWidth: frame.width,
    geometryHeight: frame.height,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    serverSideDecorated: false,
  );
}

Map<int, DesktopWindowPlacement> _placements(Map<int, int> zByWindow) => {
  for (final MapEntry(key: id, value: z) in zByWindow.entries)
    id: DesktopWindowPlacement(
      objectId: id,
      frame: const Rect.fromLTWH(0, 40, 1357, 920),
      z: z,
      monitorId: 1,
    ),
};

/// Firefox (windows 1, 4), Files (2), a terminal (3, 5) and a window
/// without an app ID (6). Used last to first: 5, 1, 2, 4, 6, 3.
final _windows = [
  _window(1, 'firefox'),
  _window(2, 'org.gnome.Nautilus'),
  _window(3, 'org.gnome.Console'),
  _window(4, 'firefox'),
  _window(5, 'org.gnome.Console'),
  _window(6, ''),
];
final _z = _placements({1: 9, 2: 7, 3: 1, 4: 6, 5: 10, 6: 4});

List<DesktopAppSwitcherApp> _order({int? focused = 5}) =>
    desktopAppSwitcherOrder(
      windows: _windows,
      placements: _z,
      focusedObjectId: focused,
    );

void main() {
  test('apps are ordered by their most recently used window', () {
    expect(_order(), const [
      DesktopAppSwitcherApp(appId: 'org.gnome.Console', windowIds: [5, 3]),
      DesktopAppSwitcherApp(appId: 'firefox', windowIds: [1, 4]),
      DesktopAppSwitcherApp(appId: 'org.gnome.Nautilus', windowIds: [2]),
      DesktopAppSwitcherApp(appId: '', windowIds: [6]),
    ]);
  });

  test('the focused window counts as the most recent', () {
    // Files is focused while a floating window stands over it.
    expect(_order(focused: 2).first.windowIds, [2]);
    expect(
      _order(focused: 4)[0],
      const DesktopAppSwitcherApp(appId: 'firefox', windowIds: [4, 1]),
    );
  });

  test('windows without an app ID are apps of their own', () {
    final apps = desktopAppSwitcherOrder(
      windows: [_window(7, ''), _window(8, '')],
      placements: _placements({7: 1, 8: 2}),
      focusedObjectId: null,
    );
    expect(apps.map((app) => app.windowIds), [
      [8],
      [7],
    ]);
  });

  test('windows the desktop has not placed come last, newest first', () {
    final apps = desktopAppSwitcherOrder(
      windows: [_window(1, 'a'), _window(2, 'b'), _window(3, 'c')],
      placements: _placements({1: 5}),
      focusedObjectId: null,
    );
    expect(apps.map((app) => app.appId), ['a', 'c', 'b']);
  });

  group('stepping', () {
    late ProviderContainer container;
    late DesktopAppSwitcherController controller;

    setUp(() {
      container = ProviderContainer();
      controller = container.read(desktopAppSwitcherProvider.notifier);
    });
    tearDown(() => container.dispose());

    DesktopAppSwitcherState? state() =>
        container.read(desktopAppSwitcherProvider);

    test('Alt+Tab selects the app used before and switches to it', () {
      final first = controller.step(
        DesktopAppSwitcherStep.next,
        apps: _order(),
        monitorId: 1,
      )!;
      expect(first.phase, DesktopAppSwitcherPhase.pending);
      expect(first.selected.appId, 'firefox');
      expect(first.monitorId, 1);
      // Tab again, and once more round the end.
      controller.step(DesktopAppSwitcherStep.next, apps: _order());
      controller.step(DesktopAppSwitcherStep.next, apps: _order());
      controller.step(DesktopAppSwitcherStep.next, apps: _order());
      expect(state()!.selected.appId, 'org.gnome.Console');
      controller.step(DesktopAppSwitcherStep.previous, apps: _order());
      expect(state()!.selected.windowIds, [6]);
      expect(controller.end(), 6);
      expect(state()!.phase, DesktopAppSwitcherPhase.closing);
      // The release came; nothing more to end.
      expect(controller.end(), isNull);
    });

    test('Alt+Shift+Tab begins on the last app', () {
      controller.step(DesktopAppSwitcherStep.previous, apps: _order());
      expect(state()!.selected.windowIds, [6]);
    });

    test('grave steps the selected app windows and Tab leaves them', () {
      controller.step(DesktopAppSwitcherStep.next, apps: _order());
      controller.step(DesktopAppSwitcherStep.windowNext, apps: _order());
      expect(state()!.selectedWindow, 1);
      expect(state()!.targetObjectId, 4);
      controller.step(DesktopAppSwitcherStep.windowNext, apps: _order());
      expect(state()!.targetObjectId, 1);
      controller.step(DesktopAppSwitcherStep.windowPrevious, apps: _order());
      expect(state()!.targetObjectId, 4);
      controller.step(DesktopAppSwitcherStep.next, apps: _order());
      expect(state()!.selectedWindow, isNull);
      expect(state()!.targetObjectId, 2);
    });

    test('Alt+grave alone steps the current app windows', () {
      controller.step(DesktopAppSwitcherStep.windowNext, apps: _order());
      expect(state()!.selected.appId, 'org.gnome.Console');
      expect(controller.end(), 3);
    });

    test('a quick Alt+Tab never shows, a held one does', () {
      final quick = controller.step(
        DesktopAppSwitcherStep.next,
        apps: _order(),
      )!;
      controller.end();
      controller.show(quick.sessionId);
      expect(state()!.phase, DesktopAppSwitcherPhase.closing);
      controller.clear(quick.sessionId);
      expect(state(), isNull);

      final held = controller.step(
        DesktopAppSwitcherStep.next,
        apps: _order(),
      )!;
      expect(held.sessionId, isNot(quick.sessionId));
      controller.show(quick.sessionId);
      expect(state()!.phase, DesktopAppSwitcherPhase.pending);
      controller.show(held.sessionId);
      expect(state()!.phase, DesktopAppSwitcherPhase.shown);
    });

    test('Escape closes without a window to activate', () {
      final session = controller.step(
        DesktopAppSwitcherStep.next,
        apps: _order(),
      )!;
      controller.cancel();
      expect(state()!.phase, DesktopAppSwitcherPhase.closing);
      expect(controller.end(), isNull);
      controller.clear(session.sessionId);
      expect(state(), isNull);
    });

    test('the order holds during a session; closed windows drop out', () {
      controller.step(DesktopAppSwitcherStep.next, apps: _order());
      controller.step(DesktopAppSwitcherStep.windowNext, apps: _order());
      expect(state()!.targetObjectId, 4);
      // Focus moved meanwhile and Firefox's window 1 closed.
      final changed = desktopAppSwitcherOrder(
        windows: _windows.where((window) => window.objectId != 1),
        placements: _z,
        focusedObjectId: 2,
      );
      controller.step(DesktopAppSwitcherStep.windowPrevious, apps: changed);
      expect(state()!.apps.map((app) => app.appId), [
        'org.gnome.Console',
        'firefox',
        'org.gnome.Nautilus',
        '',
      ]);
      expect(state()!.selected.windowIds, [4]);
      expect(state()!.targetObjectId, 4);
      // The selected app closed: the selection goes to the one before it.
      final firefoxGone = desktopAppSwitcherOrder(
        windows: _windows.where((window) => window.appId != 'firefox'),
        placements: _z,
        focusedObjectId: 5,
      );
      controller.step(DesktopAppSwitcherStep.next, apps: firefoxGone);
      expect(state()!.selected.appId, 'org.gnome.Nautilus');
    });

    test('no windows, no switcher', () {
      expect(
        controller.step(DesktopAppSwitcherStep.next, apps: const []),
        isNull,
      );
      expect(state(), isNull);
    });
  });
}
