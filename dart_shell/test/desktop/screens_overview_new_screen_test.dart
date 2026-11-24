import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace_overview_deck.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The tablet's shell at scale 2.5: 1357×960 logical.
const _view = Size(1357, 960);
const _workArea = Rect.fromLTWH(0, 32, 1357, 928);
const _gap = 8.0;

Rect _screen(int index, int current) =>
    _workArea.shift(Offset((index - current) * (_workArea.width + _gap), 0));

DenialWindow _window(int id, String app, int screen, {Rect? frame}) {
  const current = 1;
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
  );
}

/// The owner's usual strip: a text editor and Files split screen 1, Firefox
/// on screen 2.
List<DenialWindow> _strip() {
  final split = _screen(1, 1);
  final half = (split.width - _gap) / 2;
  return [
    _window(
      1,
      'org.gnome.TextEditor',
      1,
      frame: Rect.fromLTWH(split.left, split.top, half, split.height),
    ),
    _window(
      2,
      'org.gnome.Nautilus',
      1,
      frame: Rect.fromLTWH(
        split.left + half + _gap,
        split.top,
        half,
        split.height,
      ),
    ),
    _window(3, 'firefox', 2),
  ];
}

class _Catalog extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: const <HomeGridItem>[]);
}

void main() {
  testWidgets('the new screen placeholder shows once a tile leaves its '
      'split card, and goes with the drag', (tester) async {
    final container = ProviderContainer(
      overrides: [homeGridControllerProvider.overrideWith(_Catalog.new)],
    );
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWindows(
      _strip(),
      _view,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.screens,
    );
    workspace.openScreensOverview(
      monitorId: 1,
      bounds: Offset.zero & _view,
      backgroundBounds: Offset.zero & _view,
      viewport: _workArea,
    );
    await tester.binding.setSurfaceSize(_view);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: DenialLocalizationScope(
          locale: const Locale('en'),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: _view),
              child: ShellTheme(
                data: const ShellThemeData(
                  transparencyMode: ShellTransparencyMode.off,
                ),
                child: Consumer(
                  builder: (context, ref, _) => DesktopWorkspaceOverviewDeck(
                    desktop: ref.watch(desktopWorkspaceProvider),
                    motion: const AlwaysStoppedAnimation<double>(1.0),
                    onSelectWorkspace: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('New screen'), findsNothing);

    // Dragged on its own card: nothing shows.
    workspace.beginOverviewDrag(1);
    workspace.moveOverviewBy(1, const Offset(4, 4));
    workspace.planScreensDrop(1);
    await tester.pumpAndSettle();
    expect(find.text('New screen'), findsNothing);

    // Out of its card, below it: the marker fades in after the split.
    final card = container
        .read(desktopWorkspaceProvider)
        .overview!
        .workspaces!
        .screens!
        .cardOfWindow(1)!
        .geometry
        .rect;
    workspace.moveOverviewBy(
      1,
      card.bottomCenter + const Offset(0, 40) - workspace.screensDragPoint!,
    );
    workspace.planScreensDrop(1);
    await tester.pump();
    expect(find.text('New screen'), findsOneWidget);
    await tester.pumpAndSettle();
    final slot = container
        .read(desktopWorkspaceProvider)
        .overview!
        .workspaces!
        .screens!
        .newScreen!;
    final label = tester.getRect(find.text('New screen'));
    expect(slot.labelRect.inflate(1).contains(label.center), isTrue);

    // A cancelled drag takes it away.
    workspace.cancelOverviewDrag(1);
    await tester.pumpAndSettle();
    expect(find.text('New screen'), findsNothing);
  });
}
