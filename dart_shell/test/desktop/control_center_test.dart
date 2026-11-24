import 'dart:async';

import 'package:denial_desktop/src/desktop/desktop_control_center.dart';
import 'package:denial_desktop/src/desktop/desktop_dashboard.dart';
import 'package:denial_desktop/src/desktop/desktop_panel_overlay.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/widgets/shade/status_bar.dart';
import 'package:denial_flutter_sdk/glass_configuration.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_sdk/system.dart';
import 'package:denial_top_bar/denial_top_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import '../support/live_settings_transport.dart';
import '../support/mobile_shell_harness.dart';

// The desktop presentation's control center (eb19, owner's point 7): the
// dashboard opens from the bar's control-center icon and the clock, drops
// down under the bar at the top right, and closes on a click outside, Escape
// or a second click. A pointer resting at a screen edge never opens it, not
// even with the settings of the side panel it was before.

// The tablet at scale 2.5: 1357×960 logical, the owner's 33 px top bar.
const _view = Size(1357, 960);
const _barThickness = 33.0;

DisplayLayout _layout({
  SystemBarSide side = SystemBarSide.top,
  double thickness = _barThickness,
}) => DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: _view,
  pixelSize: const Size(3392, 2400),
  engineScale: 2.5,
  tickerMonitorId: 1,
  systemBarMonitorId: 1,
  systemBarMonitorIds: const [1],
  systemBarSide: side,
  systemBarThickness: thickness,
  // The dev fallback's breathing room: the panel ignores it.
  maximizePadding: 10,
  outputs: const [
    DisplayOutput(
      monitorId: 1,
      name: 'DSI-1',
      logicalRect: Rect.fromLTWH(0, 0, 1357, 960),
      pixelSize: Size(3392, 2400),
      scale: 2.5,
      refreshRate: 120,
    ),
  ],
);

/// The dashboard as the owner's settings.json has it from before eb19: a
/// side panel at the bottom left that a pointer resting at the left edge
/// opened.
const _oldDashboard = ShellPopupPlacement(
  anchor: ShellPopupAnchor.bottomLeft,
  width: 420,
  height: 740,
  margin: 8,
  hoverTriggerEnabled: true,
);
const _oldOverlays = <String, Object?>{
  'dashboard': <String, Object?>{
    'anchor': 'bottomLeft',
    'width': 420.0,
    'height': 740.0,
    'margin': 8.0,
    'hoverTriggerEnabled': true,
  },
  // The legacy switch of both panels' hover triggers, on.
  'hoverTriggersEnabled': true,
};

class _Bridge extends DenialBridge {}

/// What the bar needs of the shell: telemetry with nothing to show but the
/// clock, and the dashboard toggle as the desktop shell implements it.
class _BarServices implements ShellServices {
  _BarServices(this.container);

  final ProviderContainer container;
  final _accent = Provider<Color>((_) => const Color(0xff4a6fa5));
  final _battery = Provider<BatteryStatus>((_) => BatteryStatus.unknown);
  final _cpu = Provider<LoadSeries>((_) => const LoadSeries());
  final _gpus = Provider<List<GpuLoad>>((_) => const <GpuLoad>[]);
  final _clock = Provider<AsyncValue<DateTime>>(
    (_) => AsyncData(DateTime(2026, 11, 24, 19, 30)),
  );
  final _media = Provider<AsyncValue<MprisPlaybackState>>(
    (_) => const AsyncLoading(),
  );
  final _off = Provider<bool>((_) => false);

  DesktopWorkspaceController get _workspace =>
      container.read(desktopWorkspaceProvider.notifier);

  @override
  void toggleDashboard() {
    if (container.read(desktopWorkspaceProvider).dashboardOpen) {
      _workspace.closePanels();
    } else {
      _workspace.showPanel(DesktopPanel.dashboard);
    }
  }

  @override
  void openDashboard() => _workspace.showPanel(DesktopPanel.dashboard);
  @override
  ProviderListenable<bool> get dashboardOpen =>
      desktopWorkspaceProvider.select((state) => state.dashboardOpen);
  @override
  void openPowerSettings() {}
  @override
  ProviderListenable<Color> get accent => _accent;
  @override
  ProviderListenable<BatteryStatus> get battery => _battery;
  @override
  ProviderListenable<LoadSeries> get cpu => _cpu;
  @override
  ProviderListenable<List<GpuLoad>> get gpus => _gpus;
  @override
  ProviderListenable<AsyncValue<DateTime>> get clock => _clock;
  @override
  ProviderListenable<AsyncValue<MprisPlaybackState>> get media => _media;
  @override
  ProviderListenable<bool> get trayVisible => _off;
  @override
  ProviderListenable<bool> get workspacesEnabled => _off;
  @override
  MouseCursor get linkCursor => SystemMouseCursors.click;
  @override
  MouseCursor get normalCursor => SystemMouseCursors.basic;
  @override
  ShellStrings strings(BuildContext context) => _Strings();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Strings implements ShellStrings {
  @override
  String time(DateTime value) => '19:30';
  @override
  String shortDate(DateTime value) => 'Tue 24';
  @override
  String get openDashboard => 'Open dashboard';
  @override
  String get controlCenter => 'Control Center';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The desktop's top bar and panel overlay over the owner's old settings.
class _Desk {
  _Desk({Map<String, Object?> overlays = _oldOverlays})
    : transport = LiveSettingsTransport({'overlays': overlays}) {
    container = ProviderContainer(
      overrides: [
        denialBridgeProvider.overrideWithValue(_Bridge()),
        settingsStoreProvider.overrideWithValue(NativeSettingsStore(transport)),
      ],
    );
    container.listen(shellSettingsProvider, (_, _) {});
  }

  final LiveSettingsTransport transport;
  late final ProviderContainer container;
  final _searchFocus = FocusNode();
  var dismissals = 0;

  DesktopWorkspaceState get state => container.read(desktopWorkspaceProvider);
  DesktopWorkspaceController get workspace =>
      container.read(desktopWorkspaceProvider.notifier);

  DesktopControlCenterGeometry get geometry =>
      DesktopControlCenterGeometry.resolve(
        viewSize: _view,
        displayLayout: _layout(),
        configured: container.read(shellSettingsProvider).overlays.dashboard,
      )!;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_view);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DenialLocalizationScope(
            locale: const Locale('en'),
            child: MediaQuery(
              data: const MediaQueryData(size: _view),
              // The test engine has no Denial blur.
              child: ShellTheme(
                data: const ShellThemeData(
                  transparencyMode: ShellTransparencyMode.off,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xff203040)),
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      height: _barThickness,
                      child: DesktopSystemBar(
                        monitorId: 1,
                        side: PanelEdge.top,
                        services: _BarServices(container),
                      ),
                    ),
                    Positioned.fill(
                      child: DesktopPanelOverlay(
                        viewSize: _view,
                        shellOutputRect: Offset.zero & _view,
                        displayLayout: _layout(),
                        panelTravel: 32,
                        panelDurationScale: 1,
                        applicationSearchFocusNode: _searchFocus,
                        onOpenLauncher: () {},
                        onHoverOpenLauncher: () {},
                        onDismissPanel: () {
                          dismissals += 1;
                          workspace.closePanels();
                        },
                        onOpenDashboard: () =>
                            workspace.showPanel(DesktopPanel.dashboard),
                        onOpenSettings: () {},
                        onCancelPanelClose: () {},
                        onSchedulePanelClose: () {},
                        onPanelOpened: () {},
                        onLaunchApp: (_) {},
                        onLaunchLocalApp: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the bar's entrance and the panel's motion finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// While the panel is open, the barrier over the whole scene takes a
  /// click on the bar: it closes the panel and the bar never sees it.
  Future<void> click(WidgetTester tester, Finder finder) async {
    await tester.tap(
      finder,
      kind: PointerDeviceKind.mouse,
      warnIfMissed: !state.dashboardOpen,
    );
    await settle(tester);
  }

  Future<void> clickAt(WidgetTester tester, Offset position) async {
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await settle(tester);
  }

  /// Ends a test: the fake bridge answers no platform request.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    _searchFocus.dispose();
    unawaited(transport.close());
    await tester.pump(const Duration(seconds: 5));
  }
}

final _icon = find.byKey(systemBarControlCenterButtonKey);
final _clock = find.byKey(systemBarClockButtonKey);
final _panel = find.byType(DesktopDashboard);

void main() {
  group('the control center\'s place', () {
    test('drops down under a top bar at the top right, whatever the old '
        'settings anchored, and only a finger swipes it in', () {
      final geometry = DesktopControlCenterGeometry.resolve(
        viewSize: _view,
        displayLayout: _layout(),
        configured: _oldDashboard,
      )!;
      // The size and edge distance stay the user's; the bar's trailing
      // card ends 8 px from the right edge, and so does the panel.
      expect(geometry.panel, const Rect.fromLTWH(929, 41, 420, 740));
      // It comes out from under the bar, never across it.
      expect(geometry.reveal, const Rect.fromLTRB(929, 33, 1349, 781));
      expect(geometry.entryDirection, const Offset(0, -1));
      expect(geometry.entryGap, 8);
      // From the top edge over the panel to the screen's corner.
      expect(geometry.swipe?.edge, InputEdge.top);
      expect(geometry.swipe?.rect, const Rect.fromLTRB(929, 0, 1357, 24));
    });

    test('comes out of a bar on any side, at its trailing end', () {
      DesktopControlCenterGeometry at(SystemBarSide side, double thickness) =>
          DesktopControlCenterGeometry.resolve(
            viewSize: _view,
            displayLayout: _layout(side: side, thickness: thickness),
            configured: _oldDashboard,
          )!;
      final bottom = at(SystemBarSide.bottom, 33);
      expect(bottom.panel, const Rect.fromLTWH(929, 179, 420, 740));
      expect(bottom.reveal, const Rect.fromLTRB(929, 179, 1349, 927));
      expect(bottom.entryDirection, const Offset(0, 1));
      expect(bottom.swipe?.edge, InputEdge.bottom);
      expect(bottom.swipe?.rect, const Rect.fromLTRB(929, 936, 1357, 960));

      final left = at(SystemBarSide.left, 48);
      expect(left.panel, const Rect.fromLTWH(56, 212, 420, 740));
      expect(left.reveal, const Rect.fromLTRB(48, 212, 476, 952));
      expect(left.entryDirection, const Offset(-1, 0));
      expect(left.swipe?.edge, InputEdge.left);

      final right = at(SystemBarSide.right, 48);
      expect(right.panel, const Rect.fromLTWH(881, 212, 420, 740));
      expect(right.reveal, const Rect.fromLTRB(881, 212, 1309, 952));
      expect(right.entryDirection, const Offset(1, 0));
      expect(right.swipe?.edge, InputEdge.right);
    });

    test('drops from the top right of the screen with the bar hidden or '
        'without the compositor', () {
      for (final layout in [_layout(side: SystemBarSide.hidden), null]) {
        final geometry = DesktopControlCenterGeometry.resolve(
          viewSize: _view,
          displayLayout: layout,
          configured: _oldDashboard,
        )!;
        expect(geometry.panel, const Rect.fromLTWH(929, 8, 420, 740));
        expect(geometry.reveal, const Rect.fromLTRB(929, 0, 1349, 748));
        expect(geometry.entryDirection, const Offset(0, -1));
        expect(geometry.swipe?.edge, InputEdge.top);
      }
    });
  });

  group('the control center', () {
    testWidgets('the icon opens it: it drops down from under the bar to '
        'its place under the icon', (tester) async {
      final desk = _Desk();
      await desk.pump(tester);
      await desk.settle(tester);
      expect(_icon, findsOneWidget);
      // Before the clock, as on macOS.
      expect(
        tester.getRect(_icon).right,
        lessThanOrEqualTo(tester.getRect(_clock).left),
      );
      expect(desk.state.dashboardOpen, isFalse);

      await tester.tap(_icon, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(desk.state.dashboardOpen, isTrue);
      final rest = desk.geometry.panel;
      // Under the icon: the panel's trailing edge lines up with the bar's.
      expect(rest.right, greaterThanOrEqualTo(tester.getRect(_clock).right));
      // On its way down: above its place, below the bar's edge, moving
      // down frame after frame.
      await tester.pump(const Duration(milliseconds: 40));
      final early = tester.getRect(_panel);
      await tester.pump(const Duration(milliseconds: 60));
      final later = tester.getRect(_panel);
      expect(early.left, rest.left);
      expect(early.top, lessThan(later.top));
      expect(later.top, lessThan(rest.top));
      expect(later.bottom, greaterThan(_barThickness));

      await desk.settle(tester);
      expect(tester.getRect(_panel), rest);
      await desk.finish(tester);
    });

    testWidgets('a second click on the icon closes it, and so does the '
        'clock', (tester) async {
      final desk = _Desk();
      await desk.pump(tester);
      await desk.settle(tester);

      await desk.click(tester, _icon);
      expect(desk.state.dashboardOpen, isTrue);
      await desk.click(tester, _icon);
      expect(desk.state.dashboardOpen, isFalse);

      await desk.click(tester, _clock);
      expect(desk.state.dashboardOpen, isTrue);
      await desk.click(tester, _clock);
      expect(desk.state.dashboardOpen, isFalse);

      // It slid back up under the bar and waits there offstage.
      expect(_panel, findsNothing);
      expect(
        tester.getRect(find.byType(DesktopDashboard, skipOffstage: false)),
        desk.geometry.panel.shift(
          Offset(0, -desk.geometry.panel.height - desk.geometry.entryGap),
        ),
      );
      await desk.finish(tester);
    });

    testWidgets('a click outside closes it; one inside does not', (
      tester,
    ) async {
      final desk = _Desk();
      await desk.pump(tester);
      await desk.settle(tester);

      await desk.click(tester, _icon);
      expect(desk.state.dashboardOpen, isTrue);
      final panel = tester.getRect(_panel);
      // An empty spot of the panel's header row: the panel keeps it.
      await desk.clickAt(tester, panel.topLeft + const Offset(200, 6));
      expect(desk.state.dashboardOpen, isTrue);

      await desk.clickAt(tester, const Offset(400, 500));
      expect(desk.state.dashboardOpen, isFalse);
      expect(desk.dismissals, 1);
      await desk.finish(tester);
    });

    testWidgets('it takes the keyboard: Escape closes it', (tester) async {
      final desk = _Desk();
      await desk.pump(tester);
      await desk.settle(tester);

      await desk.click(tester, _icon);
      expect(desk.state.dashboardOpen, isTrue);
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.debugLabel, 'desktop-dashboard');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await desk.settle(tester);
      expect(desk.state.dashboardOpen, isFalse);
      // The keyboard does not stay with the closed panel.
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('desktop-dashboard'),
      );

      // Opened again, it takes the keyboard again.
      await desk.click(tester, _clock);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'desktop-dashboard',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await desk.settle(tester);
      expect(desk.state.dashboardOpen, isFalse);
      await desk.finish(tester);
    });

    testWidgets('a pointer at a screen edge opens nothing, even with the old '
        'side placement and its hover trigger', (tester) async {
      final desk = _Desk();
      await desk.pump(tester);
      await desk.settle(tester);
      final dashboard = desk.container
          .read(shellSettingsProvider)
          .overlays
          .dashboard;
      expect(dashboard.anchor, ShellPopupAnchor.bottomLeft);
      expect(dashboard.hoverTriggerEnabled, isTrue);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ShellInputRegion &&
              (widget.debugLabel?.contains('dashboard edge') ?? false),
        ),
        findsNothing,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 500));
      addTearDown(mouse.removePointer);
      for (final edge in const [
        Offset(0, 100),
        Offset(0, 480),
        Offset(0, 900),
        Offset(1356, 480),
        Offset(680, 0),
        Offset(1300, 0),
        Offset(680, 959),
        Offset(0, 959),
      ]) {
        await mouse.moveTo(edge);
        await desk.settle(tester);
        expect(desk.state.panel, DesktopPanel.none, reason: 'hover at $edge');
      }
      // Nor does a mouse dragging down from the top right, where a finger
      // opens it.
      await mouse.moveTo(const Offset(1300, 2));
      await mouse.down(const Offset(1300, 2));
      for (var y = 10.0; y <= 300; y += 10) {
        await mouse.moveTo(Offset(1300, y));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await mouse.up();
      await desk.settle(tester);
      expect(desk.state.panel, DesktopPanel.none);
      await desk.finish(tester);
    });

    testWidgets('a finger swiping down from the top right opens it', (
      tester,
    ) async {
      final desk = _Desk();
      await desk.pump(tester);
      await desk.settle(tester);

      final finger = await tester.startGesture(
        const Offset(1300, 3),
        kind: PointerDeviceKind.touch,
      );
      for (var y = 13.0; y <= 200; y += 10) {
        await finger.moveTo(Offset(1300, y));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await finger.up();
      await desk.settle(tester);
      expect(desk.state.dashboardOpen, isTrue);

      // The same swipe at the left of the screen does nothing.
      await desk.clickAt(tester, const Offset(400, 500));
      final left = await tester.startGesture(
        const Offset(300, 3),
        kind: PointerDeviceKind.touch,
      );
      for (var y = 13.0; y <= 200; y += 10) {
        await left.moveTo(Offset(300, y));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await left.up();
      await desk.settle(tester);
      expect(desk.state.panel, DesktopPanel.none);
      await desk.finish(tester);
    });

    test('names its icon in every language', () {
      expect(AppLocalizationsEn().desktopControlCenter, 'Control Center');
      expect(AppLocalizationsRu().desktopControlCenter, 'Пункт управления');
      expect(AppLocalizationsZh().desktopControlCenter, '控制中心');
    });
  });

  group('the tablet presentation', () {
    testWidgets('its top shade still comes down from the status bar, apart '
        'from the desktop\'s control center', (tester) async {
      final shell = MobileShellHarness();
      await tester.binding.setSurfaceSize(tabletView);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: shell.container,
          child: DenialLocalizationScope(
            locale: const Locale('en'),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: const MediaQueryData(size: tabletView),
                child: ShellTheme(
                  data: const ShellThemeData(
                    transparencyMode: ShellTransparencyMode.off,
                  ),
                  child: const Stack(
                    fit: StackFit.expand,
                    children: [ShadeStatusBar()],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // A finger pulls the status bar down at the top right, where the
      // desktop's control center opens.
      final finger = await tester.startGesture(
        const Offset(1300, 4),
        kind: PointerDeviceKind.touch,
      );
      for (var y = 14.0; y <= 600; y += 20) {
        await finger.moveTo(Offset(1300, y));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await finger.up();
      await tester.pump();
      expect(
        shell.container.read(referenceShellProvider).quickSettingsVisible,
        isTrue,
      );
      expect(
        shell.container.read(desktopWorkspaceProvider).panel,
        DesktopPanel.none,
      );
      await shell.finish(tester);
      // The status bar's clock waits for the next minute.
      await tester.pump(const Duration(minutes: 1));
    });
  });
}
