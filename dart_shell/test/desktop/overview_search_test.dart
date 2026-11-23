import 'package:denial_desktop/src/desktop/desktop_application_catalog.dart';
import 'package:denial_desktop/src/desktop/desktop_overview_hub.dart';
import 'package:denial_desktop/src/desktop/desktop_overview_layout.dart';
import 'package:denial_desktop/src/desktop/desktop_overview_motion.dart';
import 'package:denial_desktop/src/desktop/desktop_search_overlay.dart';
import 'package:denial_desktop/src/desktop/desktop_shell_search.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The tablet's shell at scale 2.5: 1357×960 logical.
const _view = Size(1357, 960);
const _workArea = Rect.fromLTWH(0, 32, 1357, 928);
const _gap = 8.0;

Rect _screen(int index, int current) =>
    _workArea.shift(Offset((index - current) * (_workArea.width + _gap), 0));

DenialWindow _window(
  int id, {
  required String app,
  required String title,
  required int screen,
  required int current,
  Rect? frame,
}) {
  final geometry = frame ?? _screen(screen, current);
  return DenialWindow(
    objectId: id,
    objectKind: 'xdg',
    surfaceId: id + 100,
    windowId: id + 200,
    textureId: id + 300,
    title: title,
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

/// Firefox on screens 1 and 3, Files and Console splitting screen 2 (the
/// current one), Settings on screen 4. Firefox's news window was used last.
List<DenialWindow> _strip() {
  const current = 2;
  final split = _screen(2, current);
  final half = (split.width - _gap) / 2;
  return [
    _window(
      1,
      app: 'firefox',
      title: 'Mozilla Firefox',
      screen: 1,
      current: current,
    ),
    _window(
      2,
      app: 'org.gnome.Nautilus',
      title: 'Documents',
      screen: 2,
      current: current,
      frame: Rect.fromLTWH(split.left, split.top, half, split.height),
    ),
    _window(
      3,
      app: 'org.gnome.Console',
      title: 'pingv@tablet: ~',
      screen: 2,
      current: current,
      frame: Rect.fromLTWH(
        split.left + half + _gap,
        split.top,
        half,
        split.height,
      ),
    ),
    _window(
      5,
      app: 'org.gnome.Settings',
      title: 'Settings',
      screen: 4,
      current: current,
    ),
    _window(
      4,
      app: 'firefox',
      title: 'News — Mozilla Firefox',
      screen: 3,
      current: current,
    ),
  ];
}

DesktopApp _app(String id, String name, {List<String> categories = const []}) =>
    DesktopApp(
      id: '$id.desktop',
      name: name,
      exec: id,
      desktopPath: '/usr/share/applications/$id.desktop',
      categories: categories,
    );

final _apps = <DesktopApp>[
  _app('firefox', 'Firefox', categories: ['Network', 'WebBrowser']),
  _app('org.gnome.Nautilus', 'Files'),
  _app('org.gnome.Console', 'Console'),
  _app('org.gnome.TextEditor', 'Text Editor', categories: ['TextEditor']),
];

class _Catalog extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: [for (final app in _apps) HomeGridItem.app(app)]);
}

class _Bridge extends DenialBridge {}

/// The shell around the hub and the search: windows, the app catalog, and
/// what choosing a result asks of the shell.
class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(_Bridge()),
        homeGridControllerProvider.overrideWith(_Catalog.new),
        desktopSearchWindowsProvider.overrideWithValue(_strip()),
      ],
    );
    workspace.syncWindows(
      _strip(),
      _view,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.screens,
    );
  }

  late final ProviderContainer container;
  final activated = <int>[];
  final launched = <String>[];
  final navigated = <DesktopOverviewDirection>[];
  var dismissed = 0;
  var activatedSelection = 0;

  DesktopWorkspaceController get workspace =>
      container.read(desktopWorkspaceProvider.notifier);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(_view);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: DenialLocalizationScope(
          locale: const Locale('en'),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: _view),
              // The test engine has no Denial blur; the search does not need
              // it to work.
              child: ShellTheme(
                data: const ShellThemeData(
                  transparencyMode: ShellTransparencyMode.off,
                ),
                child: Stack(children: [Positioned.fill(child: child)]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Widget hub() => DesktopOverviewHub(
    onActivateWindow: (window) => activated.add(window.objectId),
    onLaunchApplication: (app) => launched.add(app.id),
    onLaunchLocalApplication: (app) => launched.add(app.id),
    onDismiss: () {
      dismissed += 1;
      workspace.closeOverview();
    },
    onNavigate: navigated.add,
    onActivateSelection: () => activatedSelection += 1,
  );

  Widget overlay() => DesktopSearchOverlay(
    viewSize: _view,
    displayLayout: null,
    onActivateWindow: (window) => activated.add(window.objectId),
    onLaunchApplication: (app) => launched.add(app.id),
    onLaunchLocalApplication: (app) => launched.add(app.id),
  );

  Future<void> openOverview(WidgetTester tester) async {
    workspace.openScreensOverview(
      monitorId: 1,
      bounds: DesktopOverviewHubMetrics.contentBounds(
        Rect.fromLTRB(0, 44, _view.width, _view.height),
      ),
      backgroundBounds: Offset.zero & _view,
      viewport: _workArea,
      selectedObjectId: 2,
    );
    container.read(desktopOverviewMotionProvider).open(animate: false);
    await tester.pump();
    await tester.pump();
  }
}

FocusNode? _focused() => FocusManager.instance.primaryFocus;

bool _fieldFocused() => _focused()?.debugLabel == 'desktop-search';

void main() {
  group('the search listing', () {
    final windows = desktopSearchWindows(
      windows: _strip(),
      placements: {
        for (final (index, window) in _strip().indexed)
          window.objectId: DesktopWindowPlacement(
            objectId: window.objectId,
            frame: window.geometry!,
            z: window.objectId == 4 ? 99 : index,
            monitorId: 1,
          ),
      },
      catalog: DesktopApplicationCatalog.empty,
      titleOf: (window) => window.title,
    );

    test('windows come most recent first, named by their app', () {
      expect(windows.first.id, 4);
      expect(windows.first.appName, 'firefox');
    });

    test('windows, then apps; the first is what Enter acts on', () {
      final listing = DesktopSearchListing(
        searchShell(
          'fire',
          windows: windows,
          applications: const [
            LauncherApplication(
              id: 'desktop:firefox',
              name: 'Firefox',
              searchableText: 'firefox network',
            ),
          ],
        ),
      );
      expect(listing.searching, isTrue);
      expect(
        listing.entries.map(
          (entry) => switch (entry) {
            DesktopSearchWindowEntry(:final window) => window.id,
            DesktopSearchApplicationEntry(:final application) => application.id,
          },
        ),
        [4, 1, 'desktop:firefox'],
      );
      expect(listing.windowIds, {1, 4});
      expect(
        listing.entries.first,
        DesktopSearchWindowEntry(
          (listing.results.first! as ShellSearchWindowHit).window,
        ),
      );
    });

    test('nothing typed finds nothing and dims nothing', () {
      final listing = DesktopSearchListing(
        searchShell('  ', windows: windows, applications: const []),
      );
      expect(listing.searching, isFalse);
      expect(listing.entries, isEmpty);
      expect(listing.windowIds, isEmpty);
    });
  });

  group('the overview hub', () {
    testWidgets('typing finds windows and apps; Enter goes to the best', (
      tester,
    ) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      // The keyboard is in the field as soon as the overview opens.
      expect(_fieldFocused(), isTrue);

      await tester.enterText(find.byType(EditableText), 'doc');
      await tester.pump();
      expect(find.text('Windows'), findsOneWidget);
      expect(find.text('Documents'), findsWidgets);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(shell.activated, [2]);
      expect(shell.launched, isEmpty);
    });

    testWidgets('an app that is not open starts from the hub', (tester) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      await tester.enterText(find.byType(EditableText), 'edit');
      await tester.pump();
      expect(find.text('Apps'), findsOneWidget);
      expect(find.text('Text Editor'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(shell.launched, ['org.gnome.TextEditor.desktop']);
      expect(shell.dismissed, 1);
      expect(shell.activated, isEmpty);
    });

    testWidgets('the arrows choose another result', (tester) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      await tester.enterText(find.byType(EditableText), 'fire');
      await tester.pump();
      // Firefox's two windows, the one used last first, then the app.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(shell.activated, [1]);
      expect(shell.navigated, isEmpty);
    });

    testWidgets('Esc clears the query first, then closes', (tester) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      await tester.enterText(find.byType(EditableText), 'files');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      expect(shell.dismissed, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.dismissed, 1);
    });

    testWidgets('with nothing typed the keys move between the windows', (
      tester,
    ) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(shell.navigated, [
        DesktopOverviewDirection.right,
        DesktopOverviewDirection.down,
      ]);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(shell.activatedSelection, 1);
      expect(shell.activated, isEmpty);
    });

    testWidgets('the search key puts the keyboard back into the field', (
      tester,
    ) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      _focused()?.unfocus();
      await tester.pump();
      expect(_fieldFocused(), isFalse);
      shell.container
          .read(desktopOverviewSearchFocusProvider.notifier)
          .request();
      await tester.pump();
      await tester.pump();
      expect(_fieldFocused(), isTrue);
    });

    testWidgets('what the search does not find is dimmed', (tester) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      await shell.openOverview(tester);
      final desktop = shell.container.read(desktopWorkspaceProvider);
      final overview = desktop.overview!;
      List<DesktopOverviewVeil> veils(String query) =>
          desktopOverviewSearchVeils(
            overview: overview,
            desktop: desktop,
            dragged: null,
            listing: DesktopSearchListing(
              searchShell(
                query,
                windows: [
                  for (final window in _strip())
                    ShellSearchWindow(
                      id: window.objectId,
                      appId: window.appId,
                      appName: window.appId,
                      title: window.title,
                    ),
                ],
                applications: const [],
              ),
            ),
            windowRadius: 12,
            cardRadius: 20,
          );
      final cards = overview.workspaces!.screens!.cards;
      Rect cardVeil(int screen) => DesktopOverviewHubMetrics.cardVeil(
        cards.firstWhere((card) => card.screens.contains(screen)).geometry.rect,
      );

      expect(veils(''), isEmpty);
      // "doc" finds Files' window: Firefox's stack and Settings dim, and in
      // the split screen the console beside it.
      final doc = veils('doc');
      expect(doc.map((veil) => veil.rect), [
        cardVeil(1),
        overview.frames[3],
        cardVeil(4),
      ]);
      // A stack counts as found by any of its windows and stays bright.
      final news = veils('news');
      expect(news.map((veil) => veil.rect), [cardVeil(2), cardVeil(4)]);
      // A dragged window is never dimmed.
      expect(
        desktopOverviewSearchVeils(
          overview: overview,
          desktop: desktop,
          dragged: 3,
          listing: DesktopSearchListing(
            searchShell(
              'doc',
              windows: const [
                ShellSearchWindow(
                  id: 2,
                  appId: 'org.gnome.Nautilus',
                  appName: 'Files',
                  title: 'Documents',
                ),
              ],
              applications: const [],
            ),
          ),
          windowRadius: 12,
          cardRadius: 20,
        ).map((veil) => veil.rect),
        isNot(contains(overview.frames[3])),
      );
    });
  });

  group('the search over the desktop', () {
    testWidgets('opens with the keyboard in it and goes to what it finds', (
      tester,
    ) async {
      final shell = _Harness();
      await shell.pump(tester, shell.overlay());
      expect(find.byType(DesktopSearchField), findsNothing);

      shell.container.read(desktopSearchOverlayProvider.notifier).open(1);
      await tester.pump();
      await tester.pump();
      expect(find.byType(DesktopSearchField), findsOneWidget);
      expect(_fieldFocused(), isTrue);

      await tester.enterText(find.byType(EditableText), 'fire');
      await tester.pump();
      expect(find.text('News — Mozilla Firefox'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(shell.activated, [4]);
      expect(shell.container.read(desktopSearchOverlayProvider), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSearchField), findsNothing);
    });

    testWidgets('Esc clears, then closes; so does a click outside', (
      tester,
    ) async {
      final shell = _Harness();
      await shell.pump(tester, shell.overlay());
      final search = shell.container.read(
        desktopSearchOverlayProvider.notifier,
      );

      search.open(1);
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'term');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.container.read(desktopSearchOverlayProvider), 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.container.read(desktopSearchOverlayProvider), isNull);
      await tester.pumpAndSettle();

      // Opened again it starts empty; a click beside the panel closes it.
      search.open(1);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      await tester.tapAt(const Offset(20, 900));
      await tester.pump();
      expect(shell.container.read(desktopSearchOverlayProvider), isNull);
      await tester.pumpAndSettle();
      expect(shell.activated, isEmpty);
      expect(shell.launched, isEmpty);
    });
  });

  group('the app windows', () {
    test('leave room for a title under every window', () {
      const bounds = Rect.fromLTWH(0, 100, 1357, 820);
      final frames = DesktopOverviewLayout.arrange(
        items: [
          for (var id = 1; id <= 5; id += 1)
            DesktopOverviewItem(
              objectId: id,
              frame: const Rect.fromLTWH(0, 32, 1357, 928),
              z: id,
            ),
        ],
        bounds: bounds,
        mostRecentFirst: true,
        labelExtent: DesktopOverviewLayout.titleExtent,
      );
      expect(frames, hasLength(5));
      for (final frame in frames.values) {
        expect(
          frame.bottom + DesktopOverviewLayout.titleExtent,
          lessThanOrEqualTo(bounds.bottom + 1e-6),
        );
        for (final other in frames.values) {
          if (other.top > frame.top + 1) {
            expect(
              other.top,
              greaterThanOrEqualTo(
                frame.bottom + DesktopOverviewLayout.titleExtent - 1e-6,
              ),
            );
          }
        }
      }
    });

    testWidgets('name the app and every window by its title', (tester) async {
      final shell = _Harness();
      await shell.pump(tester, shell.hub());
      shell.workspace.toggleOverview(
        monitorId: 1,
        bounds: DesktopOverviewHubMetrics.contentBounds(
          Rect.fromLTRB(0, 44, _view.width, _view.height),
        ),
        backgroundBounds: Offset.zero & _view,
        objectIds: {1, 4},
        selectedObjectId: 4,
        appWindows: 'firefox',
      );
      // The catalog loads with the first view that needs it.
      await tester.pump();
      await tester.pump();
      expect(find.text('Firefox'), findsOneWidget);
      expect(find.text('2 windows'), findsOneWidget);
      expect(find.text('Mozilla Firefox'), findsOneWidget);
      expect(find.text('News — Mozilla Firefox'), findsOneWidget);
      // No search field in the app windows.
      expect(find.byType(DesktopSearchField), findsNothing);

      // A single window is shown and named too.
      shell.workspace.closeOverview();
      shell.container.read(desktopOverviewMotionProvider).close(animate: false);
      await tester.pump();
      shell.workspace.toggleOverview(
        monitorId: 1,
        bounds: DesktopOverviewHubMetrics.contentBounds(
          Rect.fromLTRB(0, 44, _view.width, _view.height),
        ),
        backgroundBounds: Offset.zero & _view,
        objectIds: {5},
        appWindows: 'org.gnome.Settings',
      );
      await tester.pump();
      expect(find.text('1 window'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);
    });
  });
}
