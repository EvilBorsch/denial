import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/models.dart';

import '../desktop/desktop_workspace.dart';

/// One step deniald asks of the app switcher (Alt+Tab, Shift+Tab, `,
/// Shift+`).
enum DesktopAppSwitcherStep { next, previous, windowNext, windowPrevious }

/// Whether the app switcher shows: a quick Alt+Tab switches without it, as
/// ⌘Tab does on a Mac.
enum DesktopAppSwitcherPhase { pending, shown, closing }

/// An app in the app switcher: all its windows are one entry.
@immutable
class DesktopAppSwitcherApp {
  const DesktopAppSwitcherApp({required this.appId, required this.windowIds});

  /// The windows' app ID; empty for a window without one, which is then an
  /// app of its own.
  final String appId;

  /// Its windows, the most recently used first.
  final List<int> windowIds;

  @override
  bool operator ==(Object other) =>
      other is DesktopAppSwitcherApp &&
      other.appId == appId &&
      listEquals(other.windowIds, windowIds);

  @override
  int get hashCode => Object.hash(appId, Object.hashAll(windowIds));

  @override
  String toString() => 'DesktopAppSwitcherApp($appId, $windowIds)';
}

/// The apps of [windows] in the app switcher's order: the app used most
/// recently first, and each app's windows likewise.
///
/// Recency is the desktop's stacking order: activating a window raises it
/// ([DesktopWindowPlacement.z]), whatever the window layout, so the window
/// switcher and the overview use the same order. The focused window counts
/// as the most recent even when a floating window stands over it. Windows
/// the desktop has not placed yet come last, the newest first.
List<DesktopAppSwitcherApp> desktopAppSwitcherOrder({
  required Iterable<DenialWindow> windows,
  required Map<int, DesktopWindowPlacement> placements,
  required int? focusedObjectId,
}) {
  int compareRecency(int left, int right) {
    if (left == right) return 0;
    if (left == focusedObjectId) return -1;
    if (right == focusedObjectId) return 1;
    final byZ = (placements[right]?.z ?? -1).compareTo(
      placements[left]?.z ?? -1,
    );
    return byZ != 0 ? byZ : right.compareTo(left);
  }

  final byApp = <Object, List<int>>{};
  final appIds = <Object, String>{};
  for (final window in windows) {
    final Object key = window.appId.isEmpty ? window.objectId : window.appId;
    byApp.putIfAbsent(key, () => <int>[]).add(window.objectId);
    appIds[key] = window.appId;
  }
  final apps =
      <DesktopAppSwitcherApp>[
        for (final MapEntry(:key, :value) in byApp.entries)
          DesktopAppSwitcherApp(
            appId: appIds[key]!,
            windowIds: List<int>.unmodifiable(value..sort(compareRecency)),
          ),
      ]..sort(
        (left, right) =>
            compareRecency(left.windowIds.first, right.windowIds.first),
      );
  return List<DesktopAppSwitcherApp>.unmodifiable(apps);
}

@immutable
class DesktopAppSwitcherState {
  const DesktopAppSwitcherState({
    required this.sessionId,
    required this.apps,
    required this.selectedApp,
    required this.selectedWindow,
    required this.monitorId,
    required this.phase,
  });

  final int sessionId;

  /// The apps as the session began, without those closed since.
  final List<DesktopAppSwitcherApp> apps;
  final int selectedApp;

  /// The window ` chose among the selected app's, or null for its most
  /// recent one. Choosing another app forgets it.
  final int? selectedWindow;

  /// The output the switcher shows on.
  final int? monitorId;
  final DesktopAppSwitcherPhase phase;

  DesktopAppSwitcherApp get selected => apps[selectedApp];

  /// The window releasing the modifier activates.
  int get targetObjectId => selected.windowIds[selectedWindow ?? 0];

  bool get isSelecting => phase != DesktopAppSwitcherPhase.closing;

  DesktopAppSwitcherState copyWith({
    List<DesktopAppSwitcherApp>? apps,
    int? selectedApp,
    int? selectedWindow,
    bool clearSelectedWindow = false,
    DesktopAppSwitcherPhase? phase,
  }) {
    return DesktopAppSwitcherState(
      sessionId: sessionId,
      apps: apps ?? this.apps,
      selectedApp: selectedApp ?? this.selectedApp,
      selectedWindow: clearSelectedWindow
          ? null
          : selectedWindow ?? this.selectedWindow,
      monitorId: monitorId,
      phase: phase ?? this.phase,
    );
  }
}

final desktopAppSwitcherProvider =
    NotifierProvider<DesktopAppSwitcherController, DesktopAppSwitcherState?>(
      DesktopAppSwitcherController.new,
    );

/// The app switcher's session: deniald steps it while the modifier is held
/// and ends or cancels it.
class DesktopAppSwitcherController extends Notifier<DesktopAppSwitcherState?> {
  @override
  DesktopAppSwitcherState? build() => null;

  int _nextSessionId = 1;

  /// One step. Without a session one begins from [apps] (in
  /// [desktopAppSwitcherOrder]): Tab selects the previous app, the one used
  /// before the current; Shift+Tab the last; ` the current app's next
  /// window. Within a session [apps] only drops what closed meanwhile.
  DesktopAppSwitcherState? step(
    DesktopAppSwitcherStep step, {
    required List<DesktopAppSwitcherApp> apps,
    int? monitorId,
  }) {
    final current = state;
    if (current == null || !current.isSelecting) {
      if (apps.isEmpty) {
        return null;
      }
      final windows = apps.first.windowIds.length;
      final (app, window) = switch (step) {
        DesktopAppSwitcherStep.next => (apps.length > 1 ? 1 : 0, null),
        DesktopAppSwitcherStep.previous => (apps.length - 1, null),
        DesktopAppSwitcherStep.windowNext => (0, windows > 1 ? 1 : 0),
        DesktopAppSwitcherStep.windowPrevious => (0, windows - 1),
      };
      return state = DesktopAppSwitcherState(
        sessionId: _nextSessionId++,
        apps: apps,
        selectedApp: app,
        selectedWindow: window,
        monitorId: monitorId,
        phase: DesktopAppSwitcherPhase.pending,
      );
    }

    final reconciled = _withoutClosed(current, apps);
    if (reconciled == null) {
      state = null;
      return null;
    }
    final count = reconciled.apps.length;
    final windows = reconciled.selected.windowIds.length;
    final selectedWindow = reconciled.selectedWindow ?? 0;
    return state = switch (step) {
      DesktopAppSwitcherStep.next => reconciled.copyWith(
        selectedApp: (reconciled.selectedApp + 1) % count,
        clearSelectedWindow: true,
      ),
      DesktopAppSwitcherStep.previous => reconciled.copyWith(
        selectedApp: (reconciled.selectedApp - 1 + count) % count,
        clearSelectedWindow: true,
      ),
      DesktopAppSwitcherStep.windowNext => reconciled.copyWith(
        selectedWindow: (selectedWindow + 1) % windows,
      ),
      DesktopAppSwitcherStep.windowPrevious => reconciled.copyWith(
        selectedWindow: (selectedWindow - 1 + windows) % windows,
      ),
    };
  }

  /// The hold delay passed: the switcher shows.
  void show(int sessionId) {
    final current = state;
    if (current?.sessionId == sessionId &&
        current!.phase == DesktopAppSwitcherPhase.pending) {
      state = current.copyWith(phase: DesktopAppSwitcherPhase.shown);
    }
  }

  /// The modifier went up: the window to activate. The switcher closes.
  int? end() {
    final current = state;
    if (current == null || !current.isSelecting) {
      return null;
    }
    state = current.copyWith(phase: DesktopAppSwitcherPhase.closing);
    return current.targetObjectId;
  }

  /// Escape: the switcher closes without switching.
  void cancel() {
    final current = state;
    if (current != null && current.isSelecting) {
      state = current.copyWith(phase: DesktopAppSwitcherPhase.closing);
    }
  }

  /// The closing animation ended.
  void clear(int sessionId) {
    if (state?.sessionId == sessionId) {
      state = null;
    }
  }

  /// The session's apps without the windows [open] no longer has, keeping
  /// the selection on the same app and window where they remain.
  static DesktopAppSwitcherState? _withoutClosed(
    DesktopAppSwitcherState current,
    List<DesktopAppSwitcherApp> open,
  ) {
    final openIds = <int>{for (final app in open) ...app.windowIds};
    final selectedApp = current.selected;
    final selectedWindowId = current.selectedWindow == null
        ? null
        : selectedApp.windowIds[current.selectedWindow!];
    final apps = <DesktopAppSwitcherApp>[];
    var selectedIndex = 0;
    for (final (index, app) in current.apps.indexed) {
      final windows = app.windowIds.where(openIds.contains).toList();
      if (windows.isEmpty) {
        continue;
      }
      // The selection stays on its app, or goes to the one before it when
      // that app closed.
      if (index <= current.selectedApp) {
        selectedIndex = apps.length;
      }
      apps.add(
        windows.length == app.windowIds.length
            ? app
            : DesktopAppSwitcherApp(
                appId: app.appId,
                windowIds: List<int>.unmodifiable(windows),
              ),
      );
    }
    if (apps.isEmpty) {
      return null;
    }
    final windowIndex = selectedWindowId == null
        ? -1
        : apps[selectedIndex].windowIds.indexOf(selectedWindowId);
    return current.copyWith(
      apps: List<DesktopAppSwitcherApp>.unmodifiable(apps),
      selectedApp: selectedIndex,
      selectedWindow: windowIndex < 0 ? null : windowIndex,
      clearSelectedWindow: windowIndex < 0,
    );
  }
}
