import 'dart:async';

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/models.dart' show DenialWindow;
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/desktop_workspace.dart';
import '../state/desktop_visibility.dart';
import '../state/reference_shell_controller.dart';
import 't3_code_client.dart';
import 't3_code_models.dart';

/// Shared T3 Code Dynamic Island & voice/text controller across both desktop
/// and tablet shell presentations.
final t3CodeControllerProvider =
    NotifierProvider<T3CodeController, T3IslandState>(T3CodeController.new);

class T3CodeController extends Notifier<T3IslandState> {
  final T3CodeClient _client = T3CodeClient();
  Timer? _reconnectTimer;
  Timer? _noticeTimer;
  T3InstallPaths? _paths;
  Future<bool>? _connectFuture;
  final Set<String> _denialCreatedThreadIds = <String>{};
  final Map<String, T3ThreadStatus> _previousStatuses =
      <String, T3ThreadStatus>{};
  final Map<String, T3ProjectInfo> _projectById = <String, T3ProjectInfo>{};
  final Map<String, T3ThreadSummary> _threadById = <String, T3ThreadSummary>{};

  @override
  T3IslandState build() {
    ref.listen<ShellT3CodeSettings>(
      shellSettingsProvider.select((s) => s.t3Code),
      (previous, next) {
        if (previous?.enabled != next.enabled ||
            previous?.installDir != next.installDir) {
          if (next.enabled) {
            unawaited(_connectIfAvailable());
          } else {
            unawaited(_disconnect());
          }
        }
      },
    );
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _noticeTimer?.cancel();
      unawaited(_client.dispose());
    });

    // Defer initial discovery until after build returns.
    Future<void>.microtask(_connectIfAvailable);
    return const T3IslandState();
  }

  ShellT3CodeSettings get _settings => ref.read(shellSettingsProvider).t3Code;

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _client.cancelVoiceStream();
    await _client.disconnectRpc();
    state = state.copyWith(
      connectionState: T3ConnectionState.serverStopped,
      expanded: false,
      voicePhase: T3VoicePhase.idle,
    );
  }

  Future<bool> _connectIfAvailable({bool launchIfStopped = false}) async {
    if (!_settings.enabled) return false;
    final inFlight = _connectFuture;
    if (inFlight != null) {
      final ok = await inFlight;
      if (ok || !launchIfStopped) return ok;
    }
    final future = _connectOnce(launchIfStopped: launchIfStopped);
    _connectFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_connectFuture, future)) {
        _connectFuture = null;
      }
    }
  }

  Future<bool> _connectOnce({required bool launchIfStopped}) async {
    try {
      final paths = T3CodeClient.discoverInstall(_settings);
      _paths = paths;
      if (paths == null) {
        state = state.copyWith(
          installed: false,
          installDir: '',
          connectionState: T3ConnectionState.notInstalled,
        );
        _scheduleReconnect(const Duration(seconds: 20));
        return false;
      }

      state = state.copyWith(
        installed: true,
        installDir: paths.installDir,
      );

      var origin = await _client.discoverRunningOrigin(paths);
      if (origin == null && launchIfStopped) {
        state = state.copyWith(
          connectionState: T3ConnectionState.connecting,
          statusNotice: 'Запуск T3 Code...',
          clearErrorMessage: true,
        );
        final launched = await _client.launchT3Code(paths);
        if (launched) {
          origin = _client.origin;
        }
      }
      if (origin == null) {
        state = state.copyWith(
          connectionState: T3ConnectionState.serverStopped,
          clearStatusNotice: true,
        );
        _scheduleReconnect(const Duration(seconds: 6));
        return false;
      }

      if (_client.rpcConnected) {
        return true;
      }

      state = state.copyWith(
        connectionState: T3ConnectionState.connecting,
        serverOrigin: origin,
        clearErrorMessage: true,
      );

      await _client.connectRpc(
        paths,
        onShellItem: _handleShellItem,
        onDisconnect: _handleRpcDisconnect,
      );

      final providers = await _client.fetchProviders();
      state = state.copyWith(
        connectionState: T3ConnectionState.connected,
        serverOrigin: origin,
        providers: providers,
        clearStatusNotice: true,
        clearErrorMessage: true,
      );

      // Re-subscribe to selected thread if one is expanded.
      if (state.expanded && state.selectedThreadId != null) {
        _client.subscribeThread(state.selectedThreadId, _handleThreadEvent);
      }
      return true;
    } catch (error) {
      debugPrint('T3CodeController connect failed: $error');
      state = state.copyWith(
        connectionState: T3ConnectionState.error,
        clearStatusNotice: true,
      );
      _scheduleReconnect(const Duration(seconds: 8));
      return false;
    }
  }

  void _handleRpcDisconnect() {
    if (!ref.mounted) return;
    state = state.copyWith(
      connectionState: T3ConnectionState.serverStopped,
    );
    _scheduleReconnect(const Duration(seconds: 4));
  }

  void _scheduleReconnect(Duration delay) {
    _reconnectTimer?.cancel();
    if (!_settings.enabled) return;
    _reconnectTimer = Timer(delay, () {
      if (ref.mounted && _settings.enabled && !_client.rpcConnected) {
        unawaited(_connectIfAvailable());
      }
    });
  }

  void _showTransientNotice(String message, {bool isError = false}) {
    _noticeTimer?.cancel();
    state = isError
        ? state.copyWith(errorMessage: message, clearStatusNotice: true)
        : state.copyWith(statusNotice: message, clearErrorMessage: true);
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (!ref.mounted) return;
      state = state.copyWith(clearStatusNotice: true, clearErrorMessage: true);
    });
  }

  /// Toggles voice dictation: starts recording when idle, finishes & sends
  /// when already recording.
  Future<void> toggleVoice({String? replyToThreadId}) async {
    if (!_settings.enabled) return;
    if (state.voicePhase == T3VoicePhase.recording) {
      await finishVoiceAndSend();
      return;
    }
    if (state.isVoiceActive) return;

    final connected = await _connectIfAvailable(launchIfStopped: true);
    final paths = _paths;
    if (!connected || paths == null) {
      _showTransientNotice(
        paths == null
            ? 'T3 Code не установлен (откройте Настройки → T3 Code)'
            : 'Не удалось подключиться к T3 Code',
        isError: true,
      );
      return;
    }

    state = state.copyWith(
      voicePhase: T3VoicePhase.connecting,
      voiceCommitted: '',
      voiceTentative: '',
      voiceLevel: 0,
      voiceWaveform: const <double>[
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
        0.12,
      ],
      voiceTargetThreadId: replyToThreadId,
      clearVoiceTargetThreadId: replyToThreadId == null,
      clearErrorMessage: true,
      clearStatusNotice: true,
    );

    try {
      await _client.startVoiceStream(
        paths,
        voiceModelId: _settings.voiceModelId,
        onTranscript: (committed, tentative) {
          if (!ref.mounted) return;
          state = state.copyWith(
            voiceCommitted: committed,
            voiceTentative: tentative,
          );
        },
        onLevel: (level) {
          if (!ref.mounted) return;
          final next = List<double>.of(state.voiceWaveform);
          if (next.isNotEmpty) next.removeAt(0);
          next.add(0.14 + level * 0.86);
          state = state.copyWith(voiceLevel: level, voiceWaveform: next);
        },
        onError: (msg) {
          if (!ref.mounted) return;
          state = state.copyWith(voicePhase: T3VoicePhase.idle);
          _showTransientNotice(msg, isError: true);
        },
      );
      if (ref.mounted) {
        state = state.copyWith(voicePhase: T3VoicePhase.recording);
      }
    } catch (error) {
      debugPrint('T3CodeController startVoiceStream failed: $error');
      if (ref.mounted) {
        state = state.copyWith(voicePhase: T3VoicePhase.idle);
        _showTransientNotice(
          'Ошибка запуска микрофона или GigaAM',
          isError: true,
        );
      }
    }
  }

  /// Stops voice capture, finalizes GigaAM transcription, and dispatches the
  /// prompt to T3 Code.
  Future<void> finishVoiceAndSend() async {
    if (state.voicePhase != T3VoicePhase.recording) return;
    final paths = _paths;
    if (paths == null) {
      await cancelVoice();
      return;
    }
    final targetThreadId = state.voiceTargetThreadId;
    final fallbackTranscript = state.liveTranscript;
    state = state.copyWith(voicePhase: T3VoicePhase.finishing);

    String finalText = '';
    try {
      finalText = await _client.finishVoiceStream(paths);
    } catch (error) {
      debugPrint('T3CodeController finishVoiceStream failed: $error');
    }
    if (finalText.trim().isEmpty) {
      finalText = fallbackTranscript.trim();
    }
    if (finalText.isEmpty) {
      state = state.copyWith(
        voicePhase: T3VoicePhase.idle,
        voiceCommitted: '',
        voiceTentative: '',
        clearVoiceTargetThreadId: true,
      );
      _showTransientNotice('Речь не распознана');
      return;
    }

    await sendTextPrompt(finalText, replyToThreadId: targetThreadId);
  }

  Future<void> cancelVoice() async {
    await _client.cancelVoiceStream();
    if (!ref.mounted) return;
    state = state.copyWith(
      voicePhase: T3VoicePhase.idle,
      voiceCommitted: '',
      voiceTentative: '',
      voiceLevel: 0,
      clearVoiceTargetThreadId: true,
    );
  }

  /// Sends a text prompt (from Search AI button, voice result, or Dynamic
  /// Island inline reply) to T3 Code with `full-access` (bypass permissions).
  Future<void> sendTextPrompt(
    String prompt, {
    String? replyToThreadId,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;

    final connected = await _connectIfAvailable(launchIfStopped: true);
    final paths = _paths;
    if (!connected || paths == null) {
      state = state.copyWith(voicePhase: T3VoicePhase.idle);
      _showTransientNotice(
        paths == null
            ? 'T3 Code не установлен (Настройки → T3 Code)'
            : 'T3 Code не отвечает',
        isError: true,
      );
      return;
    }

    state = state.copyWith(
      voicePhase: T3VoicePhase.sending,
      clearErrorMessage: true,
    );

    try {
      String threadId;
      if (replyToThreadId != null && replyToThreadId.isNotEmpty) {
        await _client.sendMessageToThread(
          threadId: replyToThreadId,
          prompt: trimmed,
        );
        threadId = replyToThreadId;
        _denialCreatedThreadIds.add(threadId);
      } else {
        final (driver, instanceId, model) = _resolveModelSelection();
        final projectId = await _client.ensureProjectForWorkspace(
          paths,
          _settings.workspaceRoot,
          state.projects,
        );
        threadId = await _client.launchThread(
          projectId: projectId,
          prompt: trimmed,
          providerDriver: driver,
          providerInstanceId: instanceId,
          model: model,
        );
        _denialCreatedThreadIds.add(threadId);
      }

      // Collapse into the sleek thinking pill in the taskbar/status bar while
      // T3 works; user can click it anytime to watch live steps, and it will
      // auto-expand when T3 finishes answering.
      final unread = Set<String>.of(state.unreadCompletedThreadIds)
        ..remove(threadId);
      state = state.copyWith(
        voicePhase: T3VoicePhase.idle,
        voiceCommitted: '',
        voiceTentative: '',
        clearVoiceTargetThreadId: true,
        selectedThreadId: threadId,
        expanded: false,
        unreadCompletedThreadIds: unread,
        clearStatusNotice: true,
        clearErrorMessage: true,
      );
      _client.subscribeThread(threadId, _handleThreadEvent);
    } catch (error) {
      debugPrint('T3CodeController sendTextPrompt failed: $error');
      state = state.copyWith(voicePhase: T3VoicePhase.idle);
      _showTransientNotice('Не удалось отправить запрос в T3', isError: true);
    }
  }

  (String driver, String instanceId, String model) _resolveModelSelection() {
    final providers = state.providers;
    final configuredInstance = _settings.providerInstanceId.trim();
    final configuredDriver = _settings.providerDriver.trim();
    final configuredModel = _settings.model.trim();

    T3ProviderOption? picked;
    if (configuredInstance.isNotEmpty) {
      for (final p in providers) {
        if (p.instanceId == configuredInstance) {
          picked = p;
          break;
        }
      }
    }
    if (picked == null && configuredDriver.isNotEmpty) {
      for (final p in providers) {
        if (p.driver == configuredDriver && p.enabled) {
          picked = p;
          break;
        }
      }
    }
    picked ??=
        providers.where((p) => p.enabled && p.ready).firstOrNull ??
        providers.where((p) => p.enabled).firstOrNull ??
        providers.firstOrNull;

    final instanceId = picked?.instanceId ??
        (configuredInstance.isNotEmpty ? configuredInstance : 'antigravity');
    final driver = picked?.driver ??
        (configuredDriver.isNotEmpty ? configuredDriver : instanceId);
    final model = configuredModel.isNotEmpty
        ? configuredModel
        : (picked?.resolvedDefaultModel ?? 'gemini-3-flash');
    return (driver, instanceId, model);
  }

  void toggleExpanded() {
    if (state.expanded) {
      collapse();
    } else {
      final target = state.primaryThread?.id;
      expand(threadId: target);
    }
  }

  void expand({String? threadId}) {
    final target = threadId ?? state.primaryThread?.id;
    final unread = Set<String>.of(state.unreadCompletedThreadIds);
    if (target != null) unread.remove(target);
    state = state.copyWith(
      expanded: true,
      selectedThreadId: target,
      unreadCompletedThreadIds: unread,
    );
    if (target != null) {
      _ensureThreadDetail(target);
    }
  }

  void selectThread(String threadId) {
    final unread = Set<String>.of(state.unreadCompletedThreadIds)
      ..remove(threadId);
    state = state.copyWith(
      selectedThreadId: threadId,
      clearSelectedThreadDetail: state.selectedThreadId != threadId,
      unreadCompletedThreadIds: unread,
    );
    _ensureThreadDetail(threadId);
  }

  void collapse() {
    final selected = state.selectedThreadId;
    if (selected != null && state.unreadCompletedThreadIds.contains(selected)) {
      final unread = Set<String>.of(state.unreadCompletedThreadIds)
        ..remove(selected);
      state = state.copyWith(expanded: false, unreadCompletedThreadIds: unread);
      return;
    }
    state = state.copyWith(expanded: false);
  }

  Future<void> stopThread(String threadId) async {
    final thread = _threadById[threadId];
    final runId = thread?.activeRunId;
    if (runId == null || runId.isEmpty) return;
    try {
      await _client.interruptRun(threadId: threadId, runId: runId);
    } catch (error) {
      debugPrint('T3CodeController stopThread failed: $error');
    }
  }

  /// Распознаёт открытое окно T3 Code по `appId` или заголовку.
  @visibleForTesting
  static bool isT3CodeWindow(DenialWindow window) {
    if (!window.isUserApp) return false;
    final appId = window.appId.trim().toLowerCase();
    final title = window.title.trim().toLowerCase();
    return appId == 'com.t3tools.t3code' ||
        appId.contains('t3code') ||
        appId.contains('t3-code') ||
        appId.contains('t3_code') ||
        title == 't3 code' ||
        title.contains('t3 code');
  }

  Future<void> openInT3Code({String? threadId}) async {
    // Сначала сворачиваем оверлей, чтобы ShellInputRegion не перехватывал фокус.
    collapse();
    final shellState = ref.read(referenceShellProvider);
    final shellNotifier = ref.read(referenceShellProvider.notifier);

    DenialWindow? existing;
    for (final window in shellState.allOpenAppWindows) {
      if (isT3CodeWindow(window)) {
        existing = window;
        break;
      }
    }

    if (existing != null) {
      final target = existing;
      final isDeskWindow = shellState.desk.openAppWindowsByObjectId.containsKey(
        target.objectId,
      );
      if (isDeskWindow) {
        final workspace = ref.read(desktopWorkspaceProvider);
        final workspaceNotifier = ref.read(desktopWorkspaceProvider.notifier);
        if (workspace.overviewActive) {
          workspaceNotifier.closeOverview();
        }
        workspaceNotifier.closePanels();
        ref.read(desktopVisibleProvider.notifier).restore();

        final placement = workspace.placements[target.objectId];
        if (placement != null &&
            !placement.minimized &&
            placement.monitorId >= 0 &&
            !workspace.isPlacementOnActiveWorkspace(placement)) {
          // В раскладке «На весь экран» каждое окно живёт на своём рабочем столе:
          // сначала переключаем рабочий стол, затем фокусируем окно.
          ref
              .read(denialBridgeProvider)
              .switchWorkspace(
                monitorId: placement.monitorId,
                workspaceId: placement.workspaceId,
              );
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 90), () {
              if (!ref.mounted) return;
              ref.read(desktopWorkspaceProvider.notifier).activate(
                target.objectId,
              );
              ref.read(referenceShellProvider.notifier).focusWindow(target);
            }),
          );
          return;
        }
        workspaceNotifier.activate(target.objectId);
      }
      shellNotifier.focusWindow(target);
      return;
    }

    final paths = _paths ?? T3CodeClient.discoverInstall(_settings);
    if (paths != null) {
      await _client.openDesktopApp(paths);
      return;
    }
    try {
      final repo = ref.read(desktopAppsRepositoryProvider);
      final app = await repo.loadApplication('com.t3tools.T3Code');
      if (app != null && ref.mounted) {
        await ref.read(appLauncherProvider).launch(app);
      }
    } catch (error) {
      debugPrint('T3CodeController openInT3Code fallback launch failed: $error');
    }
  }

  void _ensureThreadDetail(String threadId) {
    _client.subscribeThread(threadId, _handleThreadEvent);
    final paths = _paths;
    if (paths != null) {
      unawaited(
        _client.fetchThreadDetailHttp(paths, threadId).then((snapshot) {
          if (!ref.mounted || snapshot == null) return;
          final proj = snapshot['projection'];
          if (proj is Map && state.selectedThreadId == threadId) {
            final detail = _parseThreadProjection(
              threadId,
              Map<String, dynamic>.from(proj),
            );
            state = state.copyWith(selectedThreadDetail: detail);
          }
        }),
      );
    }
  }

  void _handleShellItem(Map<String, dynamic> item) {
    if (!ref.mounted) return;
    final kind = item['kind']?.toString();
    switch (kind) {
      case 'snapshot':
        final snapshot = item['snapshot'];
        if (snapshot is! Map) return;
        _projectById.clear();
        final rawProjects = snapshot['projects'];
        if (rawProjects is List) {
          for (final p in rawProjects) {
            if (p is! Map) continue;
            final info = _parseProject(Map<String, dynamic>.from(p));
            if (info != null) _projectById[info.id] = info;
          }
        }
        final rawThreads = snapshot['threads'];
        // T3 Code sends a follow-up project-metadata enrichment snapshot with
        // an empty `threads: []` list; keep existing threads when that arrives.
        if (rawThreads is List &&
            (rawThreads.isNotEmpty || _threadById.isEmpty)) {
          _threadById.clear();
          for (final t in rawThreads) {
            if (t is! Map) continue;
            final summary = _parseThreadShell(Map<String, dynamic>.from(t));
            if (summary != null) {
              _threadById[summary.id] = summary;
              _previousStatuses[summary.id] = summary.status;
            }
          }
        }
        _publishShellCollections();

      case 'project.updated':
        final p = item['project'];
        if (p is Map) {
          final info = _parseProject(Map<String, dynamic>.from(p));
          if (info != null) {
            _projectById[info.id] = info;
            _publishShellCollections();
          }
        }

      case 'project.removed':
        final pid = item['projectId']?.toString();
        if (pid != null) {
          _projectById.remove(pid);
          _publishShellCollections();
        }

      case 'thread.updated':
        final location = item['location']?.toString();
        final t = item['thread'];
        if (t is! Map) return;
        final summary = _parseThreadShell(Map<String, dynamic>.from(t));
        if (summary == null) return;
        if (location == 'archive') {
          _threadById.remove(summary.id);
          _publishShellCollections();
          return;
        }
        final prevStatus = _previousStatuses[summary.id];
        _previousStatuses[summary.id] = summary.status;
        _threadById[summary.id] = summary;

        // Detect transition from active/running -> completed or waiting!
        final justFinished =
            prevStatus != null &&
            prevStatus.isActive &&
            (summary.status == T3ThreadStatus.completed ||
                summary.status == T3ThreadStatus.failed ||
                summary.status == T3ThreadStatus.interrupted);
        final justNeedsInput =
            summary.needsAttention && prevStatus != T3ThreadStatus.waiting;

        _publishShellCollections(
          autoExpandThreadId: (justFinished || justNeedsInput)
              ? summary.id
              : null,
        );

      case 'thread.removed':
        final tid = item['threadId']?.toString();
        if (tid != null) {
          _threadById.remove(tid);
          _previousStatuses.remove(tid);
          _publishShellCollections();
        }
    }
  }

  void _publishShellCollections({String? autoExpandThreadId}) {
    final projects = _projectById.values.toList(growable: false);
    final threads = _threadById.values.toList(growable: false);
    final unread = Set<String>.of(state.unreadCompletedThreadIds);

    var shouldExpand = state.expanded;
    var selectedId = state.selectedThreadId;

    if (autoExpandThreadId != null) {
      // Auto-expand the Dynamic Island when a thread finishes answering!
      if (!state.isVoiceActive) {
        shouldExpand = true;
        selectedId = autoExpandThreadId;
        _ensureThreadDetail(autoExpandThreadId);
      } else {
        unread.add(autoExpandThreadId);
      }
    }

    state = state.copyWith(
      projects: projects,
      threads: threads,
      expanded: shouldExpand,
      selectedThreadId: selectedId,
      unreadCompletedThreadIds: unread,
    );
  }

  void _handleThreadEvent(String threadId, Map<String, dynamic> item) {
    if (!ref.mounted || state.selectedThreadId != threadId) return;
    final kind = item['kind']?.toString();
    if (kind == 'snapshot') {
      final proj = item['projection'];
      if (proj is Map) {
        final detail = _parseThreadProjection(
          threadId,
          Map<String, dynamic>.from(proj),
        );
        state = state.copyWith(selectedThreadDetail: detail);
      }
      return;
    }
    if (kind == 'event') {
      final event = item['event'];
      if (event is! Map) return;
      final type = event['type']?.toString() ?? '';
      // Incrementally merge streaming turn-item updates or refresh projection.
      if (type == 'turn-item.updated' ||
          type == 'turn-item.created' ||
          type == 'message.created' ||
          type == 'message.updated') {
        final payload = event['payload'];
        if (payload is Map) {
          final rawItem = payload['turnItem'] ?? payload['item'] ?? payload;
          if (rawItem is Map) {
            final parsed = _parseTurnItem(Map<String, dynamic>.from(rawItem));
            if (parsed != null) {
              _upsertDetailItem(threadId, parsed);
              return;
            }
          }
        }
      }
      if (type == 'run.updated' || type == 'run.created') {
        final paths = _paths;
        if (paths != null) {
          unawaited(
            _client.fetchThreadDetailHttp(paths, threadId).then((snap) {
              if (!ref.mounted || snap == null) return;
              final proj = snap['projection'];
              if (proj is Map && state.selectedThreadId == threadId) {
                state = state.copyWith(
                  selectedThreadDetail: _parseThreadProjection(
                    threadId,
                    Map<String, dynamic>.from(proj),
                  ),
                );
              }
            }),
          );
        }
      }
    }
  }

  void _upsertDetailItem(String threadId, T3TurnActivity activity) {
    final current =
        state.selectedThreadDetail ??
        T3ThreadDetail(
          threadId: threadId,
          title: _threadById[threadId]?.title ?? 'T3 Code',
          items: const <T3TurnActivity>[],
        );
    final nextItems = List<T3TurnActivity>.of(current.items);
    final idx = nextItems.indexWhere((e) => e.id == activity.id);
    if (idx >= 0) {
      nextItems[idx] = activity;
    } else {
      nextItems.add(activity);
    }
    state = state.copyWith(
      selectedThreadDetail: T3ThreadDetail(
        threadId: threadId,
        title: current.title,
        items: nextItems,
        activeStepSummary: _deriveActiveStep(nextItems),
      ),
    );
  }

  T3ProjectInfo? _parseProject(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    final workspaceRoot = raw['workspaceRoot']?.toString() ?? '';
    if (id.isEmpty) return null;
    final title = (raw['title']?.toString().trim().isNotEmpty ?? false)
        ? raw['title'].toString().trim()
        : workspaceRoot.split('/').last;
    return T3ProjectInfo(id: id, title: title, workspaceRoot: workspaceRoot);
  }

  T3ThreadSummary? _parseThreadShell(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    // Skip hidden subagent child threads; keep top-level threads only.
    final lineage = raw['lineage'];
    if (lineage is Map && lineage['kind'] == 'subagent') {
      return null;
    }
    final projectId = raw['projectId']?.toString() ?? '';
    final project = _projectById[projectId];
    final title = (raw['title']?.toString().trim().isNotEmpty ?? false)
        ? raw['title'].toString().trim()
        : 'Новый тред';
    final statusStr =
        raw['activityRunStatus']?.toString() ?? raw['status']?.toString();
    final status = T3ThreadStatus.parse(statusStr);
    final updatedStr =
        raw['updatedAt']?.toString() ??
        raw['latestRunCompletedAt']?.toString() ??
        raw['latestRunStartedAt']?.toString() ??
        raw['createdAt']?.toString();
    final updatedAt =
        DateTime.tryParse(updatedStr ?? '') ?? DateTime.now().toUtc();
    final modelSel = raw['modelSelection'];
    final model = modelSel is Map ? modelSel['model']?.toString() : null;
    final pendingReq = raw['pendingRuntimeRequest'];
    final pendingQuestion = pendingReq is Map
        ? (pendingReq['title']?.toString() ??
              pendingReq['summary']?.toString() ??
              'Требуется ответ')
        : null;

    return T3ThreadSummary(
      id: id,
      projectId: projectId,
      projectTitle: project?.title,
      workspaceRoot: project?.workspaceRoot,
      title: title,
      status: status,
      updatedAt: updatedAt,
      activeRunId: raw['activeRunId']?.toString(),
      providerInstanceId: raw['providerInstanceId']?.toString(),
      model: model,
      lastError: raw['lastError']?.toString(),
      pendingQuestion: pendingQuestion,
      createdByDenial: _denialCreatedThreadIds.contains(id),
    );
  }

  T3ThreadDetail _parseThreadProjection(
    String threadId,
    Map<String, dynamic> proj,
  ) {
    final threadMap = proj['thread'];
    final title = (threadMap is Map && threadMap['title'] is String)
        ? (threadMap['title'] as String).trim()
        : (_threadById[threadId]?.title ?? 'T3 Code');

    final messageTextById = <String, String>{};
    if (proj['messages'] is List) {
      for (final m in proj['messages'] as List) {
        if (m is! Map) continue;
        final id = m['id']?.toString() ?? '';
        final text = m['text']?.toString() ?? '';
        if (id.isNotEmpty && text.isNotEmpty) {
          messageTextById[id] = text;
        }
      }
    }

    final activities = <T3TurnActivity>[];
    final visible = proj['visibleTurnItems'];
    final turnItems = proj['turnItems'];
    final source = visible is List && visible.isNotEmpty
        ? visible
        : (turnItems is List ? turnItems : const <Object?>[]);
    for (final entry in source) {
      if (entry is! Map) continue;
      final inner = entry['item'] is Map
          ? Map<String, dynamic>.from(entry['item'] as Map)
          : Map<String, dynamic>.from(entry);
      final parsed = _parseTurnItem(inner, messageTextById: messageTextById);
      if (parsed != null) activities.add(parsed);
    }

    // Fallback to conversation messages if turnItems had no text.
    if (activities.isEmpty && proj['messages'] is List) {
      for (final m in proj['messages'] as List) {
        if (m is! Map) continue;
        final role = m['role']?.toString();
        final text = m['text']?.toString() ?? '';
        if (text.trim().isEmpty) continue;
        activities.add(
          T3TurnActivity(
            id: m['id']?.toString() ?? '${activities.length}',
            kind: role == 'user'
                ? T3ActivityKind.user
                : T3ActivityKind.assistant,
            text: text,
            streaming: m['streaming'] == true,
          ),
        );
      }
    }

    return T3ThreadDetail(
      threadId: threadId,
      title: title.isEmpty ? 'T3 Code' : title,
      items: activities,
      activeStepSummary: _deriveActiveStep(activities),
    );
  }

  T3TurnActivity? _parseTurnItem(
    Map<String, dynamic> item, {
    Map<String, String> messageTextById = const <String, String>{},
  }) {
    final id = item['id']?.toString() ?? item['itemId']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';
    if (type.isEmpty) return null;
    String resolveMessageText() {
      final direct = item['text']?.toString() ?? '';
      if (direct.isNotEmpty) return direct;
      final msgId = item['messageId']?.toString() ?? '';
      return messageTextById[msgId] ?? '';
    }

    switch (type) {
      case 'user_message':
        return T3TurnActivity(
          id: id.isEmpty ? 'u-${item['messageId']}' : id,
          kind: T3ActivityKind.user,
          text: resolveMessageText(),
        );
      case 'assistant_message':
        return T3TurnActivity(
          id: id.isEmpty ? 'a-${item['messageId']}' : id,
          kind: T3ActivityKind.assistant,
          text: resolveMessageText(),
          streaming: item['streaming'] == true,
        );
      case 'reasoning':
        final text = item['text']?.toString() ?? '';
        if (text.trim().isEmpty) return null;
        return T3TurnActivity(
          id: id.isEmpty ? 'r-${text.hashCode}' : id,
          kind: T3ActivityKind.reasoning,
          title: 'Размышление',
          text: text,
          streaming: item['streaming'] == true,
        );
      case 'notification':
        final text =
            item['message']?.toString() ?? item['title']?.toString() ?? '';
        if (text.trim().isEmpty) return null;
        return T3TurnActivity(
          id: id.isEmpty ? 'n-${text.hashCode}' : id,
          kind: T3ActivityKind.notification,
          title: item['title']?.toString() ?? '',
          text: text,
        );
      default:
        // Tool calls / command executions / file changes / MCP calls / subagents.
        final title =
            item['summary']?.toString() ??
            item['toolName']?.toString() ??
            item['title']?.toString() ??
            item['command']?.toString() ??
            type.replaceAll('_', ' ');
        final detail =
            item['detail']?.toString() ??
            item['command']?.toString() ??
            item['path']?.toString() ??
            '';
        return T3TurnActivity(
          id: id.isEmpty ? 't-$type-${title.hashCode}' : id,
          kind: T3ActivityKind.tool,
          title: title,
          text: detail,
          status: item['status']?.toString(),
          streaming: item['status'] == 'running' || item['status'] == 'pending',
        );
    }
  }

  static String? _deriveActiveStep(List<T3TurnActivity> items) {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item.kind == T3ActivityKind.tool && item.title.isNotEmpty) {
        return item.title;
      }
      if (item.kind == T3ActivityKind.reasoning && item.streaming) {
        return 'Думает...';
      }
      if (item.kind == T3ActivityKind.assistant && item.streaming) {
        return 'Отвечает...';
      }
    }
    return null;
  }
}
