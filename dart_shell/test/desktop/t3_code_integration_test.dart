import 'package:denial_desktop/src/search/shell_search_view.dart';
import 'package:denial_desktop/src/t3_code/t3_code_models.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
