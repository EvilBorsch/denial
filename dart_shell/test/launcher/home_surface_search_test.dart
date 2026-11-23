import 'package:denial_desktop/src/launcher/home_surface.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/environment.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart' show denialBridgeProvider;
import 'package:denial_flutter_sdk/system_services.dart'
    show HapticsService, hapticsServiceProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_shell_harness.dart';

DesktopApp _app(String id, String name) => DesktopApp(
  id: id,
  name: name,
  exec: id,
  desktopPath: '/usr/share/applications/$id.desktop',
  categories: const <String>[],
);

/// Home with three apps and the drawer as the user left it.
class _Home extends HomeGridController {
  _Home({required this.drawer});
  final bool drawer;

  @override
  Future<HomeGridState> build() async => HomeGridState(
    slots: [
      HomeGridItem.app(_app('firefox', 'Firefox')),
      HomeGridItem.app(_app('org.gnome.Nautilus', 'Files')),
      HomeGridItem.app(_app('org.gnome.Console', 'Terminal')),
    ],
    drawer: drawer,
    drawerChosen: true,
  );

  @override
  void setLauncherActive(bool active) {}
}

class _Recents extends ApplicationRecentsController {
  @override
  List<String> build() => const [];
}

class _QuietHaptics extends HapticsService {
  _QuietHaptics(super.bridge);

  @override
  void prewarm() {}

  @override
  void pulse() {}
}

VoidCallback? _disposeHome;

void main() {
  final l10n = AppLocalizationsEn();

  Future<ProviderContainer> home(
    WidgetTester tester, {
    bool drawer = true,
  }) async {
    tester.view
      ..physicalSize = tabletView
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bridge = MobileShellBridge();
    final container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(bridge),
        startupEnvironmentProvider.overrideWithValue(
          StartupEnvironment(const {'DENIAL_SHELL_PROFILE': 'mobile'}),
        ),
        homeGridControllerProvider.overrideWith(() => _Home(drawer: drawer)),
        applicationRecentsProvider.overrideWith(_Recents.new),
        hapticsServiceProvider.overrideWith(
          (ref) => _QuietHaptics(ref.watch(denialBridgeProvider)),
        ),
      ],
    );
    _disposeHome = () {
      container.dispose();
      bridge.dispose();
    };
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: DenialLocalizationScope(
          locale: const Locale('en'),
          child: MediaQuery(
            data: const MediaQueryData(size: tabletView),
            child: ShellTheme(
              data: const ShellThemeData(
                transparencyMode: ShellTransparencyMode.off,
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(builder: (_) => const HomeSurface()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// The pull-down search's field: shown only while search is.
  Finder searchField() => find.text(l10n.homeSearchHint);

  /// The fake bridge answers no platform request: unmount, dispose, and let
  /// the requests time out.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    _disposeHome?.call();
    _disposeHome = null;
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('a pull down on home opens search, and Back closes it', (
    tester,
  ) async {
    await home(tester, drawer: false);
    expect(find.text('Firefox'), findsOneWidget);
    expect(searchField(), findsNothing);

    await tester.dragFrom(const Offset(678, 520), const Offset(0, 420));
    await settle(tester);
    expect(searchField(), findsOneWidget);
    expect(find.text(l10n.commonCancel), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.focusNode!.hasFocus, isTrue);

    // The edge Back swipe, from the left edge inward.
    await tester.dragFrom(const Offset(3, 500), const Offset(160, 0));
    await settle(tester);
    expect(searchField(), findsNothing);
    await finish(tester);
  });

  testWidgets('a short pull down springs back', (tester) async {
    await home(tester, drawer: false);
    await tester.timedDragFrom(
      const Offset(678, 520),
      const Offset(0, 120),
      const Duration(seconds: 1),
    );
    await settle(tester);
    expect(searchField(), findsNothing);
    await finish(tester);
  });

  testWidgets('a swipe up opens the drawer, whose search finds apps', (
    tester,
  ) async {
    await home(tester);
    await tester.dragFrom(const Offset(678, 700), const Offset(0, -520));
    await settle(tester);
    expect(searchField(), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'term');
    await tester.pump();
    expect(find.text(l10n.homeSearchApps), findsOneWidget);
    // Back closes the drawer.
    await tester.dragFrom(const Offset(3, 500), const Offset(160, 0));
    await settle(tester);
    expect(searchField(), findsNothing);
    await finish(tester);
  });

  testWidgets('without the drawer a swipe up opens nothing', (tester) async {
    await home(tester, drawer: false);
    await tester.dragFrom(const Offset(678, 700), const Offset(0, -520));
    await settle(tester);
    expect(searchField(), findsNothing);
    await finish(tester);
  });
}
