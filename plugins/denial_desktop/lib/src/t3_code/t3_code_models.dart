import 'package:flutter/foundation.dart';

/// Connection status between the Denial shell and the local T3 Code server.
enum T3ConnectionState {
  notInstalled,
  serverStopped,
  connecting,
  connected,
  error,
}

/// Lifecycle phase of voice dictation triggered from Denial.
enum T3VoicePhase {
  idle,
  connecting,
  recording,
  finishing,
  sending,
  error,
}

/// Normalized execution state of a T3 Code thread.
enum T3ThreadStatus {
  idle,
  preparing,
  starting,
  running,
  queued,
  waiting,
  completed,
  interrupted,
  failed,
  cancelled,
  rolledBack;

  bool get isActive =>
      this == preparing ||
      this == starting ||
      this == running ||
      this == queued ||
      this == waiting;

  bool get isTerminal =>
      this == completed ||
      this == interrupted ||
      this == failed ||
      this == cancelled ||
      this == rolledBack;

  static T3ThreadStatus parse(String? raw) => switch (raw) {
    'preparing' => preparing,
    'starting' => starting,
    'running' => running,
    'queued' => queued,
    'waiting' => waiting,
    'completed' => completed,
    'interrupted' => interrupted,
    'failed' => failed,
    'cancelled' => cancelled,
    'rolled_back' => rolledBack,
    _ => idle,
  };
}

@immutable
class T3ModelOption {
  const T3ModelOption({required this.slug, required this.name});

  final String slug;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is T3ModelOption && other.slug == slug && other.name == name;

  @override
  int get hashCode => Object.hash(slug, name);
}

@immutable
class T3ProviderOption {
  const T3ProviderOption({
    required this.instanceId,
    required this.driver,
    required this.displayName,
    required this.enabled,
    required this.ready,
    required this.models,
    this.defaultModel,
  });

  final String instanceId;
  final String driver;
  final String displayName;
  final bool enabled;
  final bool ready;
  final List<T3ModelOption> models;
  final String? defaultModel;

  String? get resolvedDefaultModel {
    if (defaultModel != null && defaultModel!.isNotEmpty) return defaultModel;
    if (models.isNotEmpty) return models.first.slug;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is T3ProviderOption &&
      other.instanceId == instanceId &&
      other.driver == driver &&
      other.displayName == displayName &&
      other.enabled == enabled &&
      other.ready == ready &&
      other.defaultModel == defaultModel &&
      listEquals(other.models, models);

  @override
  int get hashCode => Object.hash(
    instanceId,
    driver,
    displayName,
    enabled,
    ready,
    defaultModel,
    Object.hashAll(models),
  );
}

@immutable
class T3ProjectInfo {
  const T3ProjectInfo({
    required this.id,
    required this.title,
    required this.workspaceRoot,
  });

  final String id;
  final String title;
  final String workspaceRoot;

  @override
  bool operator ==(Object other) =>
      other is T3ProjectInfo &&
      other.id == id &&
      other.title == title &&
      other.workspaceRoot == workspaceRoot;

  @override
  int get hashCode => Object.hash(id, title, workspaceRoot);
}

@immutable
class T3ThreadSummary {
  const T3ThreadSummary({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.projectTitle,
    this.workspaceRoot,
    this.activeRunId,
    this.providerInstanceId,
    this.model,
    this.lastError,
    this.pendingQuestion,
    this.createdByDenial = false,
  });

  final String id;
  final String projectId;
  final String title;
  final T3ThreadStatus status;
  final DateTime updatedAt;
  final String? projectTitle;
  final String? workspaceRoot;
  final String? activeRunId;
  final String? providerInstanceId;
  final String? model;
  final String? lastError;
  final String? pendingQuestion;
  final bool createdByDenial;

  bool get isRunning => status.isActive;
  bool get needsAttention =>
      pendingQuestion != null && pendingQuestion!.isNotEmpty;

  T3ThreadSummary copyWith({
    String? title,
    T3ThreadStatus? status,
    DateTime? updatedAt,
    String? projectTitle,
    String? workspaceRoot,
    String? activeRunId,
    bool clearActiveRunId = false,
    String? providerInstanceId,
    String? model,
    String? lastError,
    bool clearLastError = false,
    String? pendingQuestion,
    bool clearPendingQuestion = false,
    bool? createdByDenial,
  }) {
    return T3ThreadSummary(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      projectTitle: projectTitle ?? this.projectTitle,
      workspaceRoot: workspaceRoot ?? this.workspaceRoot,
      activeRunId: clearActiveRunId ? null : (activeRunId ?? this.activeRunId),
      providerInstanceId: providerInstanceId ?? this.providerInstanceId,
      model: model ?? this.model,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      pendingQuestion: clearPendingQuestion
          ? null
          : (pendingQuestion ?? this.pendingQuestion),
      createdByDenial: createdByDenial ?? this.createdByDenial,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is T3ThreadSummary &&
      other.id == id &&
      other.projectId == projectId &&
      other.title == title &&
      other.status == status &&
      other.updatedAt == updatedAt &&
      other.projectTitle == projectTitle &&
      other.workspaceRoot == workspaceRoot &&
      other.activeRunId == activeRunId &&
      other.providerInstanceId == providerInstanceId &&
      other.model == model &&
      other.lastError == lastError &&
      other.pendingQuestion == pendingQuestion &&
      other.createdByDenial == createdByDenial;

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    title,
    status,
    updatedAt,
    projectTitle,
    workspaceRoot,
    activeRunId,
    providerInstanceId,
    model,
    lastError,
    pendingQuestion,
    createdByDenial,
  );
}

enum T3ActivityKind { user, assistant, reasoning, tool, notification }

@immutable
class T3TurnActivity {
  const T3TurnActivity({
    required this.id,
    required this.kind,
    required this.text,
    this.title = '',
    this.streaming = false,
    this.status,
  });

  final String id;
  final T3ActivityKind kind;
  final String title;
  final String text;
  final bool streaming;
  final String? status;

  @override
  bool operator ==(Object other) =>
      other is T3TurnActivity &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.text == text &&
      other.streaming == streaming &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, kind, title, text, streaming, status);
}

@immutable
class T3ThreadDetail {
  const T3ThreadDetail({
    required this.threadId,
    required this.title,
    required this.items,
    this.activeStepSummary,
  });

  final String threadId;
  final String title;
  final List<T3TurnActivity> items;
  final String? activeStepSummary;

  String get latestAssistantText {
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].kind == T3ActivityKind.assistant &&
          items[i].text.trim().isNotEmpty) {
        return items[i].text;
      }
    }
    return '';
  }

  String get latestUserText {
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].kind == T3ActivityKind.user &&
          items[i].text.trim().isNotEmpty) {
        return items[i].text;
      }
    }
    return '';
  }

  @override
  bool operator ==(Object other) =>
      other is T3ThreadDetail &&
      other.threadId == threadId &&
      other.title == title &&
      other.activeStepSummary == activeStepSummary &&
      listEquals(other.items, items);

  @override
  int get hashCode =>
      Object.hash(threadId, title, activeStepSummary, Object.hashAll(items));
}

@immutable
class T3IslandState {
  const T3IslandState({
    this.connectionState = T3ConnectionState.serverStopped,
    this.installed = false,
    this.installDir = '',
    this.serverOrigin = 'http://127.0.0.1:3773',
    this.providers = const <T3ProviderOption>[],
    this.projects = const <T3ProjectInfo>[],
    this.threads = const <T3ThreadSummary>[],
    this.selectedThreadId,
    this.selectedThreadDetail,
    this.expanded = false,
    this.unreadCompletedThreadIds = const <String>{},
    this.voicePhase = T3VoicePhase.idle,
    this.voiceLevel = 0,
    this.voiceWaveform = const <double>[
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
    this.voiceCommitted = '',
    this.voiceTentative = '',
    this.voiceTargetThreadId,
    this.statusNotice,
    this.errorMessage,
  });

  final T3ConnectionState connectionState;
  final bool installed;
  final String installDir;
  final String serverOrigin;
  final List<T3ProviderOption> providers;
  final List<T3ProjectInfo> projects;
  final List<T3ThreadSummary> threads;
  final String? selectedThreadId;
  final T3ThreadDetail? selectedThreadDetail;
  final bool expanded;
  final Set<String> unreadCompletedThreadIds;
  final T3VoicePhase voicePhase;
  final double voiceLevel;
  final List<double> voiceWaveform;
  final String voiceCommitted;
  final String voiceTentative;
  final String? voiceTargetThreadId;
  final String? statusNotice;
  final String? errorMessage;

  bool get isVoiceActive =>
      voicePhase == T3VoicePhase.connecting ||
      voicePhase == T3VoicePhase.recording ||
      voicePhase == T3VoicePhase.finishing ||
      voicePhase == T3VoicePhase.sending;

  String get liveTranscript {
    final c = voiceCommitted.trim();
    final t = voiceTentative.trim();
    if (c.isEmpty) return t;
    if (t.isEmpty) return c;
    return '$c $t';
  }

  List<T3ThreadSummary> get runningThreads =>
      threads.where((thread) => thread.isRunning).toList(growable: false);

  /// Threads surfaced in the Dynamic Island: all running threads, all threads
  /// with unread completions, and the most recent threads (up to 8 total).
  List<T3ThreadSummary> get islandThreads {
    final list = List<T3ThreadSummary>.of(threads);
    list.sort((a, b) {
      if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
      final aUnread = unreadCompletedThreadIds.contains(a.id);
      final bUnread = unreadCompletedThreadIds.contains(b.id);
      if (aUnread != bUnread) return aUnread ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    if (list.length > 8) return list.sublist(0, 8);
    return list;
  }

  T3ThreadSummary? get primaryThread {
    if (selectedThreadId != null) {
      for (final thread in threads) {
        if (thread.id == selectedThreadId) return thread;
      }
    }
    final active = runningThreads;
    if (active.isNotEmpty) return active.first;
    final visible = islandThreads;
    return visible.isEmpty ? null : visible.first;
  }

  bool get hasIslandActivity =>
      isVoiceActive ||
      runningThreads.isNotEmpty ||
      unreadCompletedThreadIds.isNotEmpty ||
      errorMessage != null ||
      statusNotice != null;

  T3IslandState copyWith({
    T3ConnectionState? connectionState,
    bool? installed,
    String? installDir,
    String? serverOrigin,
    List<T3ProviderOption>? providers,
    List<T3ProjectInfo>? projects,
    List<T3ThreadSummary>? threads,
    String? selectedThreadId,
    bool clearSelectedThreadId = false,
    T3ThreadDetail? selectedThreadDetail,
    bool clearSelectedThreadDetail = false,
    bool? expanded,
    Set<String>? unreadCompletedThreadIds,
    T3VoicePhase? voicePhase,
    double? voiceLevel,
    List<double>? voiceWaveform,
    String? voiceCommitted,
    String? voiceTentative,
    String? voiceTargetThreadId,
    bool clearVoiceTargetThreadId = false,
    String? statusNotice,
    bool clearStatusNotice = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return T3IslandState(
      connectionState: connectionState ?? this.connectionState,
      installed: installed ?? this.installed,
      installDir: installDir ?? this.installDir,
      serverOrigin: serverOrigin ?? this.serverOrigin,
      providers: providers ?? this.providers,
      projects: projects ?? this.projects,
      threads: threads ?? this.threads,
      selectedThreadId: clearSelectedThreadId
          ? null
          : (selectedThreadId ?? this.selectedThreadId),
      selectedThreadDetail: clearSelectedThreadDetail
          ? null
          : (selectedThreadDetail ?? this.selectedThreadDetail),
      expanded: expanded ?? this.expanded,
      unreadCompletedThreadIds:
          unreadCompletedThreadIds ?? this.unreadCompletedThreadIds,
      voicePhase: voicePhase ?? this.voicePhase,
      voiceLevel: voiceLevel ?? this.voiceLevel,
      voiceWaveform: voiceWaveform ?? this.voiceWaveform,
      voiceCommitted: voiceCommitted ?? this.voiceCommitted,
      voiceTentative: voiceTentative ?? this.voiceTentative,
      voiceTargetThreadId: clearVoiceTargetThreadId
          ? null
          : (voiceTargetThreadId ?? this.voiceTargetThreadId),
      statusNotice: clearStatusNotice
          ? null
          : (statusNotice ?? this.statusNotice),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
