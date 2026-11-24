import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_sdk/system.dart';
import 'package:denial_top_bar/denial_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

// A bar with nothing to report but the clock: no battery, meters, media,
// tray or workspaces. No real services are used.
class _QuietServices implements ShellServices {
  final _accent = Provider<Color>((_) => const Color(0xff4a6fa5));
  final _battery = Provider<BatteryStatus>((_) => BatteryStatus.unknown);
  final _cpu = Provider<LoadSeries>((_) => const LoadSeries());
  final _gpus = Provider<List<GpuLoad>>((_) => const <GpuLoad>[]);
  final _clock = Provider<AsyncValue<DateTime>>(
    (_) => AsyncData(DateTime(2026, 11, 22, 19, 30)),
  );
  final _media = Provider<AsyncValue<MprisPlaybackState>>(
    (_) => const AsyncLoading(),
  );
  final _off = Provider<bool>((_) => false);

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
  void openDashboard() {}
  @override
  void toggleDashboard() {}
  @override
  ProviderListenable<bool> get dashboardOpen => _off;
  @override
  void openPowerSettings() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Strings implements ShellStrings {
  @override
  String time(DateTime value) => '19:30';
  @override
  String shortDate(DateTime value) => 'Sun 22';
  @override
  String get openDashboard => 'Open dashboard';
  @override
  String get stayAwakeOn => 'Stay awake is on';
  @override
  String get controlCenter => 'Control Center';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(
  WidgetTester tester, {
  required bool stayAwake,
  PanelEdge side = PanelEdge.top,
}) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: side.isHorizontal ? 800 : 200,
          height: side.isHorizontal ? 44 : 600,
          // Opaque cards: the test engine lacks the blur of Denial's.
          child: ShellTheme(
            data: const ShellThemeData(cardOpacity: 1),
            child: DesktopSystemBar(
              monitorId: 1,
              side: side,
              services: _QuietServices(),
              stayAwake: stayAwake,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the desktop bar shows Stay awake beside the clock', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, stayAwake: false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.coffee_rounded), findsNothing);

    await _pump(tester, stayAwake: true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.coffee_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Stay awake is on'), findsOneWidget);
    // The cards gather at the trailing edge: the mark comes before the
    // clock.
    expect(
      tester.getTopRight(find.byIcon(Icons.coffee_rounded)).dx,
      lessThan(tester.getTopLeft(find.text('19:30')).dx),
    );

    await _pump(tester, stayAwake: false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.coffee_rounded), findsNothing);
    semantics.dispose();
  });

  testWidgets('a bar on a side edge stacks the mark above the clock', (
    tester,
  ) async {
    await _pump(tester, stayAwake: true, side: PanelEdge.right);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byIcon(Icons.coffee_rounded)).dy,
      lessThan(tester.getTopLeft(find.text('19:30')).dy),
    );
  });

  testWidgets('the panel plugin passes the setting to its bar', (tester) async {
    for (final stayAwake in [false, true]) {
      final environment = ShellSurfaceEnvironment(
        output: const DisplayOutput(
          monitorId: 1,
          name: 'DSI-1',
          logicalRect: Rect.fromLTWH(0, 0, 2261, 1600),
          pixelSize: Size(3392, 2400),
          scale: 1.5,
          refreshRate: 120,
        ),
        workArea: const Rect.fromLTWH(0, 0, 2261, 1600),
        isMainOutput: true,
        workspaceId: 1,
        fullscreen: false,
        overview: false,
        desktopVisible: false,
        wallpaperSelectorVisible: false,
        locked: false,
        settings: ShellSettings(
          power: ShellPowerSettings(stayAwake: stayAwake),
        ),
        defaultOutputSelected: true,
      );
      late Widget bar;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            bar = const TopBarPlugin().build(
              context,
              surface: ShellSurfaceContext(
                environment: environment,
                events: const Stream<ShellSurfaceEnvironment>.empty(),
                services: _QuietServices(),
              ),
            );
            return const SizedBox();
          },
        ),
      );
      expect((bar as DesktopSystemBar).stayAwake, stayAwake);
    }
  });
}
