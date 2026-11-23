import 'package:denial_desktop/src/launcher/widgets/home_app_drawer.dart';
import 'package:denial_desktop/src/launcher/widgets/home_search_sheet.dart';
import 'package:denial_desktop/src/launcher/widgets/home_search_view.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:denial_flutter_sdk/platform.dart' show DenialBridge;
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DesktopApp _app(String id, String name) => DesktopApp(
  id: id,
  name: name,
  exec: id,
  desktopPath: '/usr/share/applications/$id.desktop',
  categories: const <String>[],
);

DenialWindow _window(int id, String appId, String title) => DenialWindow(
  objectId: id,
  objectKind: 'xdg_toplevel',
  surfaceId: id,
  windowId: id,
  textureId: id,
  title: title,
  appId: appId,
  width: 100,
  height: 100,
  surfaceX: 0,
  surfaceY: 0,
  surfaceWidth: 100,
  surfaceHeight: 100,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 100,
  textureSourceHeight: 100,
  geometryX: 0,
  geometryY: 0,
  geometryWidth: 100,
  geometryHeight: 100,
  monitorId: 1,
  transform: 0,
  scale120: 120,
);

final _firefox = HomeGridItem.app(_app('firefox', 'Firefox'));
final _files = HomeGridItem.app(_app('org.gnome.Nautilus', 'Files'));
final _terminal = HomeGridItem.app(_app('org.gnome.Console', 'Terminal'));
final _apps = [_terminal, _firefox, _files];

final _github = _window(1, 'firefox', 'GitHub — Mozilla Firefox');
final _mail = _window(2, 'firefox', 'Inbox — Mozilla Firefox');
final _shell = _window(3, 'org.gnome.Console', 'pingv@pad: ~');

class _Grid extends HomeGridController {
  @override
  Future<HomeGridState> build() async =>
      HomeGridState(slots: <HomeGridItem?>[..._apps]);
}

class _Recents extends ApplicationRecentsController {
  _Recents(this.ids);
  final List<String> ids;
  @override
  List<String> build() => ids;
}

class _Bridge implements DenialBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What the search widgets were asked to do.
class _Calls {
  final launched = <HomeGridItem>[];
  final opened = <DenialWindow>[];
  var closed = 0;
}

Widget _host({
  required Widget child,
  List<DenialWindow> windows = const [],
  List<String> recents = const [],
}) => ProviderScope(
  overrides: [
    denialBridgeProvider.overrideWithValue(_Bridge()),
    homeGridControllerProvider.overrideWith(_Grid.new),
    applicationRecentsProvider.overrideWith(() => _Recents(recents)),
    homeSearchWindowsProvider.overrideWithValue(windows),
  ],
  child: DenialLocalizationScope(
    locale: const Locale('en'),
    child: MediaQuery(
      data: const MediaQueryData(size: Size(1357, 960)),
      // Opaque panels: flutter_tester has no Denial glass blur.
      child: ShellTheme(
        data: const ShellThemeData(panelOpacity: 1),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
        ),
      ),
    ),
  ),
);

Widget _drawer(
  _Calls calls, {
  Animation<double> openness = const AlwaysStoppedAnimation(1),
}) => HomeAppDrawer(
  openness: openness,
  apps: _apps,
  columns: 6,
  onLaunch: (app, _) => calls.launched.add(app),
  onOpenWindow: (found, _) => calls.opened.add(found.window),
  onDrag: (_) {},
  onDragEnd: (_) {},
);

/// The tablet's landscape panel at the shell's scale.
void _tablet(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1357, 960)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

void main() {
  final l10n = AppLocalizationsEn();

  group('the drawer', () {
    testWidgets('lists every app by name with nothing typed', (tester) async {
      _tablet(tester);
      final calls = _Calls();
      await tester.pumpWidget(_host(windows: [_github], child: _drawer(calls)));
      await tester.pump();
      expect(find.text(l10n.homeSearchHint), findsOneWidget);
      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where(['Files', 'Firefox', 'Terminal'].contains)
          .toList();
      expect(names, ['Files', 'Firefox', 'Terminal']);
      // No windows without a query: the drawer is for apps.
      expect(find.byType(HomeSearchWindowRow), findsNothing);
    });

    testWidgets('typing filters to matching windows and apps', (tester) async {
      _tablet(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _host(windows: [_mail, _github, _shell], child: _drawer(calls)),
      );
      await tester.pump();
      await _type(tester, 'fire');
      expect(find.text(l10n.homeSearchWindows), findsOneWidget);
      expect(find.text(l10n.homeSearchApps), findsOneWidget);
      expect(find.byType(HomeSearchWindowRow), findsNWidgets(2));
      expect(find.text('Inbox — Mozilla Firefox'), findsOneWidget);
      expect(find.text('GitHub — Mozilla Firefox'), findsOneWidget);
      expect(find.text('Terminal'), findsNothing);
      expect(find.text('Files'), findsNothing);
      expect(find.byType(HomeLaunchTile), findsOneWidget);

      await tester.tap(find.text('GitHub — Mozilla Firefox'));
      expect(calls.opened, [_github]);
      await tester.tap(find.byType(HomeLaunchTile));
      expect(calls.launched, [_firefox]);
    });

    testWidgets('a window title alone finds its window', (tester) async {
      _tablet(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _host(windows: [_mail, _github, _shell], child: _drawer(calls)),
      );
      await tester.pump();
      await _type(tester, 'inbox');
      expect(find.byType(HomeSearchWindowRow), findsOneWidget);
      expect(find.text(l10n.homeSearchApps), findsNothing);
      // Enter goes to the best match.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(calls.opened, [_mail]);
    });

    testWidgets('says so when nothing matches', (tester) async {
      _tablet(tester);
      await tester.pumpWidget(_host(child: _drawer(_Calls())));
      await tester.pump();
      await _type(tester, 'zzz');
      expect(find.text(l10n.homeSearchNoResults), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(l10n.homeSearchClear));
      await tester.pump();
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text(l10n.homeSearchNoResults), findsNothing);
    });

    testWidgets('closed, it forgets its search', (tester) async {
      _tablet(tester);
      final openness = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(openness.dispose);
      await tester.pumpWidget(
        _host(child: _drawer(_Calls(), openness: openness)),
      );
      openness.forward();
      await tester.pumpAndSettle();
      await _type(tester, 'fire');
      expect(find.text('Terminal'), findsNothing);
      openness.reverse();
      await tester.pumpAndSettle();
      openness.forward();
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isFalse);
      expect(find.text('Terminal'), findsOneWidget);
    });
  });

  group('the pull down', () {
    Widget sheet(_Calls calls, Animation<double> openness) => HomeSearchSheet(
      openness: openness,
      apps: _apps,
      columns: 6,
      onLaunch: (app, _) => calls.launched.add(app),
      onOpenWindow: (found, _) => calls.opened.add(found.window),
      onClose: () => calls.closed++,
      onDrag: (_) {},
      onDragEnd: (_) {},
    );

    testWidgets('suggests open windows and recent apps before typing', (
      tester,
    ) async {
      _tablet(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _host(
          windows: [_shell, _github],
          recents: [desktopApplicationRecentId('org.gnome.Nautilus')],
          child: sheet(calls, const AlwaysStoppedAnimation(1)),
        ),
      );
      await tester.pump();
      expect(find.text(l10n.homeSearchWindows), findsOneWidget);
      expect(find.byType(HomeSearchWindowRow), findsNWidgets(2));
      expect(find.text(l10n.homeSearchRecentApps), findsOneWidget);
      expect(find.byType(HomeLaunchTile), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);

      await tester.tap(find.text('pingv@pad: ~'));
      expect(calls.opened, [_shell]);
    });

    testWidgets('typing searches windows and apps', (tester) async {
      _tablet(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _host(
          windows: [_shell, _github],
          child: sheet(calls, const AlwaysStoppedAnimation(1)),
        ),
      );
      await tester.pump();
      await _type(tester, 'term');
      expect(find.byType(HomeSearchWindowRow), findsOneWidget);
      expect(find.text(l10n.homeSearchApps), findsOneWidget);
      await tester.tap(find.byType(HomeLaunchTile));
      expect(calls.launched, [_terminal]);
    });

    testWidgets('opened, its field takes the focus', (tester) async {
      _tablet(tester);
      final openness = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(openness.dispose);
      await tester.pumpWidget(_host(child: sheet(_Calls(), openness)));
      await tester.pump();
      FocusNode focus() => tester
          .widget<TextField>(find.byType(TextField, skipOffstage: false))
          .focusNode!;
      expect(focus().hasFocus, isFalse);
      openness.forward();
      await tester.pumpAndSettle();
      expect(focus().hasFocus, isTrue);
      openness.reverse();
      await tester.pump();
      expect(focus().hasFocus, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel and a tap on empty space close it', (tester) async {
      _tablet(tester);
      final calls = _Calls();
      await tester.pumpWidget(
        _host(child: sheet(calls, const AlwaysStoppedAnimation(1))),
      );
      await tester.pump();
      await tester.tap(find.text(l10n.commonCancel));
      expect(calls.closed, 1);
      await tester.tapAt(const Offset(600, 900));
      expect(calls.closed, 2);
      // A tap on a result is the result's.
      await _type(tester, 'files');
      await tester.tap(find.byType(HomeLaunchTile));
      expect(calls.closed, 2);
      expect(calls.launched, [_files]);
    });
  });
}
