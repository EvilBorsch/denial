import 'package:denial_desktop/src/desktop/desktop_screens_overview_layout.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _view = Size(2000, 1300);
const _workArea = Rect.fromLTWH(0, 40, 2000, 1200);
const _gap = 8.0;

Rect _screen(int index, int current) =>
    _workArea.shift(Offset((index - current) * (_workArea.width + _gap), 0));

DenialWindow _window(
  int id, {
  required String app,
  required int screen,
  required int current,
  Rect? frame,
  bool floating = false,
}) {
  final geometry = frame ?? _screen(screen, current);
  return DenialWindow(
    objectId: id,
    objectKind: 'xdg',
    surfaceId: id + 100,
    windowId: id + 200,
    textureId: id + 300,
    title: '$app $id',
    appId: app,
    width: geometry.width.round(),
    height: geometry.height.round(),
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: geometry.width,
    surfaceHeight: geometry.height,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: geometry.width,
    textureSourceHeight: geometry.height,
    geometryX: geometry.left,
    geometryY: geometry.top,
    geometryWidth: geometry.width,
    geometryHeight: geometry.height,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    serverSideDecorated: false,
    layoutScreen: screen,
    layoutScreenRect: _screen(screen, current),
    layoutScreenFloating: floating,
  );
}

/// Firefox on screens 1 and 3, Files and a terminal splitting screen 2 (the
/// current one), Settings on screen 4.
List<DenialWindow> _strip() {
  const current = 2;
  final split = _screen(2, current);
  final half = (split.width - _gap) / 2;
  return [
    _window(1, app: 'firefox', screen: 1, current: current),
    _window(
      2,
      app: 'files',
      screen: 2,
      current: current,
      frame: Rect.fromLTWH(split.left, split.top, half, split.height),
    ),
    _window(
      3,
      app: 'terminal',
      screen: 2,
      current: current,
      frame: Rect.fromLTWH(
        split.left + half + _gap,
        split.top,
        half,
        split.height,
      ),
    ),
    _window(4, app: 'firefox', screen: 3, current: current),
    _window(5, app: 'settings', screen: 4, current: current),
  ];
}

(ProviderContainer, DesktopWorkspaceController) _desktop() {
  final container = ProviderContainer();
  final workspace = container.read(desktopWorkspaceProvider.notifier);
  workspace.syncWindows(
    _strip(),
    _view,
    1,
    snapshotSequence: 1,
    windowLayout: DesktopWindowLayout.screens,
  );
  return (container, workspace);
}

void main() {
  test('the screens overview shows the strip as cards with a stack', () {
    final (container, workspace) = _desktop();
    addTearDown(container.dispose);
    workspace.openScreensOverview(
      monitorId: 1,
      bounds: Offset.zero & _view,
      backgroundBounds: Offset.zero & _view,
      viewport: _workArea,
      selectedObjectId: 3,
    );
    final overview = container.read(desktopWorkspaceProvider).overview!;
    final screens = overview.workspaces!.screens!;
    expect(screens.cards.map((card) => card.screens), [
      [1, 3],
      [2],
      [4],
    ]);
    expect(screens.currentCardId, 2);
    expect(overview.selectedObjectId, 3);
    // Every window has a frame on its card; the stack's back window too.
    expect(overview.frames.keys, containsAll(<int>[1, 2, 3, 4, 5]));
    // The camera puts any card where the current screen is.
    final card = screens.cards.last.geometry;
    final camera = overview.workspaces!.cameraRect(
      card.contentRect,
      card.workspaceId,
    );
    expect(camera.left, closeTo(_workArea.left, 1e-6));
    expect(camera.top, closeTo(_workArea.top, 1e-6));
    expect(camera.right, closeTo(_workArea.right, 1e-6));
    expect(camera.bottom, closeTo(_workArea.bottom, 1e-6));

    workspace.expandScreenStack('firefox');
    final expanded = container.read(desktopWorkspaceProvider).overview!;
    expect(expanded.workspaces!.screens!.cards, hasLength(4));

    // Closing forgets the expansion.
    workspace.closeOverview();
    workspace.openScreensOverview(
      monitorId: 1,
      bounds: Offset.zero & _view,
      backgroundBounds: Offset.zero & _view,
      viewport: _workArea,
    );
    expect(
      container
          .read(desktopWorkspaceProvider)
          .overview!
          .workspaces!
          .screens!
          .cards,
      hasLength(3),
    );
  });

  test('dragging a window highlights where it lands and plans the drop', () {
    final (container, workspace) = _desktop();
    addTearDown(container.dispose);
    workspace.openScreensOverview(
      monitorId: 1,
      bounds: Offset.zero & _view,
      backgroundBounds: Offset.zero & _view,
      viewport: _workArea,
    );
    var overview = container.read(desktopWorkspaceProvider).overview!;
    final settings = overview.workspaces!.screens!.cards.last.geometry;
    workspace.beginOverviewDrag(2);
    final from = overview.frames[2]!.center;
    final to = settings.contentRect.centerLeft + const Offset(6, 0);
    workspace.moveOverviewBy(2, to - from);
    final drop = workspace.planScreensDrop(2);
    expect(
      drop,
      isA<DesktopScreensJoin>()
          .having((join) => join.targetObjectId, 'target', 5)
          .having((join) => join.side, 'side', DenialScreenSide.left),
    );
    overview = container.read(desktopWorkspaceProvider).overview!;
    expect(overview.workspaces!.dropSlot, drop!.highlight);

    // Between the rows, off every card and gap: nothing to highlight.
    final first = overview.workspaces!.screens!.cards.first.geometry.rect;
    final outside = first.bottomCenter + const Offset(0, 6);
    workspace.moveOverviewBy(
      2,
      outside -
          container.read(desktopWorkspaceProvider).overview!.frames[2]!.center,
    );
    expect(workspace.planScreensDrop(2), isNull);
    expect(
      container.read(desktopWorkspaceProvider).overview!.workspaces!.dropSlot,
      isNull,
    );
    workspace.cancelOverviewDrag(2);
    expect(
      container.read(desktopWorkspaceProvider).placements[2]!.dragging,
      isFalse,
    );
  });

  test('the app windows view lists one app, the most recent first', () {
    final (container, workspace) = _desktop();
    addTearDown(container.dispose);
    workspace.activate(1);
    workspace.activate(4);
    workspace.toggleOverview(
      monitorId: 1,
      bounds: Offset.zero & _view,
      backgroundBounds: Offset.zero & _view,
      objectIds: <int>{1, 4},
      selectedObjectId: 4,
      appWindows: 'firefox',
    );
    final overview = container.read(desktopWorkspaceProvider).overview!;
    expect(overview.appWindows, 'firefox');
    expect(overview.frames.keys.toSet(), <int>{1, 4});
    // Most recent first: window 4, focused last, reads before window 1.
    final recent = overview.frames[4]!;
    final older = overview.frames[1]!;
    expect(
      recent.top < older.top ||
          (recent.top == older.top && recent.left < older.left),
      isTrue,
    );
    // Even a single window is shown.
    workspace.closeOverview();
    workspace.toggleOverview(
      monitorId: 1,
      bounds: Offset.zero & _view,
      backgroundBounds: Offset.zero & _view,
      objectIds: <int>{5},
      appWindows: 'settings',
    );
    expect(container.read(desktopWorkspaceProvider).overview!.frames.keys, [5]);
  });
}
