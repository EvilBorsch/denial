import 'dart:async';

import 'package:denial_desktop/src/search/shell_search_view.dart';
import 'package:denial_desktop/src/t3_code/t3_code_controller.dart';
import 'package:denial_desktop/src/t3_code/t3_code_models.dart';
import 'package:denial_desktop/src/t3_code/t3_dynamic_island.dart';
import 'package:denial_desktop/src/t3_code/t3_voice_action.dart';
import 'package:denial_flutter_sdk/actions.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/platform.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/shell.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubServices implements ShellServices {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingActionsBridge extends DenialBridge {
  final StreamController<({int generation, String id, int? monitorId})>
  _actions = StreamController.broadcast(sync: true);
  final List<({int generation, List<Map<String, Object>> actions})> published =
      [];

  @override
  Stream<({int generation, String id, int? monitorId})> get pluginActions =>
      _actions.stream;

  @override
  void publishPluginActions(int generation, List<Map<String, Object>> actions) {
    published.add((generation: generation, actions: actions));
  }

  void emitAction(String id, {int? monitorId}) {
    final gen = published.last.generation;
    _actions.add((generation: gen, id: id, monitorId: monitorId));
  }

  Future<void> close() => _actions.close();
}

class _FixedT3Controller extends T3CodeController {
  _FixedT3Controller(this._initial);

  final T3IslandState _initial;

  @override
  T3IslandState build() => _initial;
}

DenialWindow _window({required String appId, required String title}) =>
    DenialWindow(
      objectId: 42,
      objectKind: 'toplevel',
      surfaceId: 42,
      windowId: 42,
      textureId: 1,
      title: title,
      appId: appId,
      width: 1200,
      height: 800,
      surfaceX: 0,
      surfaceY: 0,
      surfaceWidth: 1200,
      surfaceHeight: 800,
      textureSourceX: 0,
      textureSourceY: 0,
      textureSourceWidth: 1200,
      textureSourceHeight: 800,
      geometryX: 0,
      geometryY: 0,
      geometryWidth: 1200,
      geometryHeight: 800,
      monitorId: 0,
      transform: 0,
      scale120: 120,
    );

void main() {
  test('T3IslandState prioritizes running and external T3 threads', () {
    final now = DateTime.utc(2026, 11, 27, 1, 0, 0);
    final runningExternal = T3ThreadSummary(
      id: 'thr-ext-run',
      projectId: 'proj-1',
      title: 'External T3 thread',
      status: T3ThreadStatus.running,
      updatedAt: now.subtract(const Duration(minutes: 2)),
      createdByDenial: false,
    );
    final recentCompleted = T3ThreadSummary(
      id: 'thr-denial-done',
      projectId: 'proj-home',
      title: 'Voice request',
      status: T3ThreadStatus.completed,
      updatedAt: now,
      createdByDenial: true,
    );
    final state = T3IslandState(
      installed: true,
      connectionState: T3ConnectionState.connected,
      threads: <T3ThreadSummary>[recentCompleted, runningExternal],
    );

    expect(state.hasIslandActivity, isTrue);
    expect(state.runningThreads, hasLength(1));
    expect(state.islandThreads.first.id, 'thr-ext-run');
    expect(state.primaryThread?.id, 'thr-ext-run');
  });

  testWidgets('ShellSearchField AI button sends typed prompt to callback', (
    tester,
  ) async {
    String? sentPrompt;
    final session = ShellSearchSession(debugLabel: 'test-ai-search')
      ..onAskAi = (prompt) => sentPrompt = prompt;
    addTearDown(session.dispose);

    await tester.pumpWidget(
      DenialLocalizationScope(
        locale: const Locale('ru'),
        child: ShellTheme(
          data: const ShellThemeData(panelOpacity: 1),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Material(
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => ShellSearchField(
                  style: ShellSearchStyle.desktop,
                  controller: session.query,
                  focusNode: session.focus,
                  hint: 'Поиск',
                  onSubmitted: session.submit,
                  aiMode: session.aiMode,
                  onAskAi: session.toggleAiMode,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('AI'), findsOneWidget);
    // Tap AI with empty input toggles AI mode on.
    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(session.aiMode, isTrue);

    // Typing and pressing AI sends prompt immediately.
    session.query.text = 'проверь статус диска';
    await tester.pump();
    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(sentPrompt, 'проверь статус диска');
  });

  testWidgets(
    'ShellActionsBinding mode switch does not wipe T3VoiceToggleAction catalog',
    (tester) async {
      final bridge = _RecordingActionsBridge();
      addTearDown(bridge.close);
      final services = _StubServices();
      var desktopToggled = 0;

      Widget buildTree({required bool desktop}) {
        return ProviderScope(
          overrides: [denialBridgeProvider.overrideWithValue(bridge)],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: desktop
                ? ShellActionsBinding(
                    key: const ValueKey('desktop-binding'),
                    actions: <ShellAction>[
                      T3VoiceToggleAction(() => desktopToggled++),
                    ],
                    services: services,
                    child: const SizedBox.shrink(),
                  )
                : ShellActionsBinding(
                    key: const ValueKey('mobile-binding'),
                    actions: <ShellAction>[T3VoiceToggleAction(() {})],
                    services: services,
                    child: const SizedBox.shrink(),
                  ),
          ),
        );
      }

      // Mount mobile first, then switch to desktop (exact boot/keyboard attach
      // sequence where old ShellActionsBinding.dispose() runs after new mount).
      await tester.pumpWidget(buildTree(desktop: false));
      expect(bridge.published.last.actions, hasLength(1));

      await tester.pumpWidget(buildTree(desktop: true));
      expect(bridge.published.last.actions, hasLength(1));
      expect(
        bridge.published.last.actions.single['id'],
        T3VoiceToggleAction.actionId,
      );

      bridge.emitAction(T3VoiceToggleAction.actionId);
      await tester.pump();
      expect(desktopToggled, 1);
    },
  );

  testWidgets('T3DynamicIslandPill stays hidden when there are no active threads', (
    tester,
  ) async {
    final completedThread = T3ThreadSummary(
      id: 'thr-done',
      projectId: 'proj-home',
      title: 'Старый завершённый тред',
      status: T3ThreadStatus.completed,
      updatedAt: DateTime.utc(2026, 11, 27, 1, 0, 0),
    );
    final runningThread = T3ThreadSummary(
      id: 'thr-run',
      projectId: 'proj-home',
      title: 'Активная задача',
      status: T3ThreadStatus.running,
      updatedAt: DateTime.utc(2026, 11, 27, 1, 5, 0),
    );

    Widget wrap(T3IslandState state, {required bool compact}) {
      return ProviderScope(
        overrides: [
          t3CodeControllerProvider.overrideWith(() => _FixedT3Controller(state)),
        ],
        child: ShellTheme(
          data: const ShellThemeData(panelOpacity: 1),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: T3DynamicIslandPill(compact: compact),
          ),
        ),
      );
    }

    // Idle with completed threads -> hidden in both desktop and tablet bars.
    final idleState = T3IslandState(
      installed: true,
      connectionState: T3ConnectionState.connected,
      threads: <T3ThreadSummary>[completedThread],
    );
    await tester.pumpWidget(wrap(idleState, compact: false));
    expect(find.byType(GestureDetector), findsNothing);

    await tester.pumpWidget(wrap(idleState, compact: true));
    expect(find.byType(GestureDetector), findsNothing);

    // Running thread -> visible capsule with thread title.
    final activeState = T3IslandState(
      installed: true,
      connectionState: T3ConnectionState.connected,
      threads: <T3ThreadSummary>[completedThread, runningThread],
    );
    await tester.pumpWidget(wrap(activeState, compact: false));
    expect(find.text('Активная задача'), findsOneWidget);
  });

  test('T3CodeController.isT3CodeWindow matches T3 Code desktop windows', () {
    expect(
      T3CodeController.isT3CodeWindow(
        _window(appId: 'com.t3tools.T3Code', title: 'T3 Code'),
      ),
      isTrue,
    );
    expect(
      T3CodeController.isT3CodeWindow(
        _window(appId: 't3code-desktop', title: 'Workspace'),
      ),
      isTrue,
    );
    expect(
      T3CodeController.isT3CodeWindow(
        _window(appId: 'electron', title: 'erhai — T3 Code'),
      ),
      isTrue,
    );
    expect(
      T3CodeController.isT3CodeWindow(
        _window(appId: 'google-chrome', title: 'Google Chrome'),
      ),
      isFalse,
    );
  });
}
