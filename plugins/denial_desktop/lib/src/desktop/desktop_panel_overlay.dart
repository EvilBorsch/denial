import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/default_shell/panel_composition.dart';
import 'desktop_application_launcher.dart';
import 'desktop_control_center.dart';
import 'desktop_dashboard.dart';
import 'desktop_panel_edges.dart';
import 'desktop_panel_transition.dart';
import 'desktop_workspace.dart';

/// The desktop's transient panels: the launcher of a launcher plugin and the
/// control center (the dashboard), the barrier that closes them on a click
/// outside, and the strips a finger swipes in from to open them.
///
/// A pointer resting at a screen edge never opens the control center: it
/// opens from its icon and the clock in the system bar (and Super's
/// dashboard shortcut), and by touch from the top right of the screen.
class DesktopPanelOverlay extends ConsumerStatefulWidget {
  const DesktopPanelOverlay({
    super.key,
    required this.viewSize,
    required this.shellOutputRect,
    required this.displayLayout,
    required this.panelTravel,
    required this.panelDurationScale,
    required this.applicationSearchFocusNode,
    required this.onOpenLauncher,
    required this.onHoverOpenLauncher,
    required this.onDismissPanel,
    required this.onOpenDashboard,
    required this.onOpenSettings,
    required this.onCancelPanelClose,
    required this.onSchedulePanelClose,
    required this.onPanelOpened,
    required this.onLaunchApp,
    required this.onLaunchLocalApp,
  });

  final Size viewSize;
  final Rect? shellOutputRect;

  /// Places the control center under the system bar's trailing end.
  final DisplayLayout? displayLayout;
  final double panelTravel;
  final double panelDurationScale;
  final FocusNode applicationSearchFocusNode;
  final VoidCallback onOpenLauncher;

  /// The pointer entered the launcher's hot edge: leaving the panel again
  /// closes it, unlike a launcher opened another way.
  final VoidCallback onHoverOpenLauncher;
  final VoidCallback onDismissPanel;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenSettings;
  final VoidCallback onCancelPanelClose;
  final VoidCallback onSchedulePanelClose;
  final VoidCallback onPanelOpened;
  final ValueChanged<DesktopApp> onLaunchApp;
  final ValueChanged<LocalFlutterApplication> onLaunchLocalApp;

  @override
  ConsumerState<DesktopPanelOverlay> createState() =>
      _DesktopPanelOverlayState();
}

class _DesktopPanelOverlayState extends ConsumerState<DesktopPanelOverlay> {
  DesktopApplicationLauncher? _applicationLauncher;
  DesktopDashboard? _dashboard;

  DesktopApplicationLauncher _cachedApplicationLauncher() {
    final cached = _applicationLauncher;
    if (cached != null &&
        identical(cached.searchFocusNode, widget.applicationSearchFocusNode) &&
        cached.onEnter == widget.onCancelPanelClose &&
        cached.onExit == widget.onSchedulePanelClose &&
        cached.onDismiss == widget.onDismissPanel &&
        cached.onLaunch == widget.onLaunchApp &&
        cached.onLaunchLocal == widget.onLaunchLocalApp) {
      return cached;
    }
    return _applicationLauncher = DesktopApplicationLauncher(
      searchFocusNode: widget.applicationSearchFocusNode,
      onEnter: widget.onCancelPanelClose,
      onExit: widget.onSchedulePanelClose,
      onDismiss: widget.onDismissPanel,
      onLaunch: widget.onLaunchApp,
      onLaunchLocal: widget.onLaunchLocalApp,
    );
  }

  DesktopDashboard _cachedDashboard() {
    final cached = _dashboard;
    if (cached != null &&
        cached.onDismiss == widget.onDismissPanel &&
        cached.onOpenSettings == widget.onOpenSettings) {
      return cached;
    }
    return _dashboard = DesktopDashboard(
      onDismiss: widget.onDismissPanel,
      onOpenSettings: widget.onOpenSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelState = ref.watch(
      desktopWorkspaceProvider.select(
        (state) => (panel: state.panel, overviewActive: state.overviewActive),
      ),
    );
    final overlaySettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.overlays),
    );
    final launcherRect = DesktopMetrics.launcherRect(
      widget.viewSize,
      outputRect: widget.shellOutputRect,
      placement: overlaySettings.launcher,
    );
    final controlCenter = DesktopControlCenterGeometry.resolve(
      viewSize: widget.viewSize,
      displayLayout: widget.displayLayout,
      configured: overlaySettings.dashboard,
    );
    final launcherTriggerRect = DesktopMetrics.launcherTriggerRect(
      widget.viewSize,
      outputRect: widget.shellOutputRect,
      placement: overlaySettings.launcher,
    );
    final hasLauncher = ref.watch(desktopLauncherProvider) != null;
    final swipes = DesktopMetrics.panelSwipes(
      widget.viewSize,
      outputRect: widget.shellOutputRect,
      overlays: overlaySettings,
      hasLauncher: hasLauncher,
      dashboard: controlCenter?.swipe,
    );
    final launcherOpen =
        hasLauncher && panelState.panel == DesktopPanel.launcher;
    final dashboardOpen = panelState.panel == DesktopPanel.dashboard;
    final panelOpen = launcherOpen || dashboardOpen;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          key: const ValueKey<String>('desktop-panel-dismiss-barrier'),
          child: ShellInputRegion(
            debugLabel: 'Desktop panel dismiss barrier',
            active: panelOpen,
            pointerPolicy: ShellPointerPolicy.fullScene,
            keyboardPolicy: ShellKeyboardPolicy.none,
            child: IgnorePointer(
              ignoring: !panelOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismissPanel,
              ),
            ),
          ),
        ),
        if (hasLauncher && !launcherRect.isEmpty)
          Positioned.fromRect(
            key: const ValueKey<String>('desktop-launcher-position'),
            rect: launcherRect,
            child: DesktopPanelTransition(
              key: const ValueKey<String>('desktop-launcher-panel'),
              inputDebugLabel: 'Desktop application launcher',
              keyboardPolicy: ShellKeyboardPolicy.capture,
              maintainState: true,
              visible: launcherOpen,
              entryDirection: desktopPanelEntryDirection(
                overlaySettings.launcher.anchor.horizontal,
                overlaySettings.launcher.anchor.vertical,
              ),
              entryDistance: widget.panelTravel,
              durationScale: widget.panelDurationScale,
              onOpened: widget.onPanelOpened,
              child: _cachedApplicationLauncher(),
            ),
          ),
        if (controlCenter != null)
          Positioned.fromRect(
            key: const ValueKey<String>('desktop-dashboard-position'),
            rect: controlCenter.reveal,
            child: DesktopControlCenter(
              geometry: controlCenter,
              visible: dashboardOpen,
              durationScale: widget.panelDurationScale,
              onOpened: widget.onPanelOpened,
              child: _cachedDashboard(),
            ),
          ),
        if (hasLauncher &&
            !panelState.overviewActive &&
            !launcherTriggerRect.isEmpty)
          Positioned.fromRect(
            rect: launcherTriggerRect,
            child: ShellInputRegion(
              debugLabel: 'Desktop launcher edge trigger',
              child: DesktopPanelEdgeTrigger(
                onEnter: widget.onHoverOpenLauncher,
                onExit: widget.onSchedulePanelClose,
              ),
            ),
          ),
        // Above the hover trigger: a finger has no hover. The compositor
        // hands a swipe over a window to the shell once it moves inward.
        if (!panelState.overviewActive) ...[
          if (swipes.launcher case final swipe?)
            Positioned.fromRect(
              rect: swipe.rect,
              child: DesktopPanelEdgeSwipe(
                edge: swipe.edge,
                onSwipe: widget.onOpenLauncher,
              ),
            ),
          if (swipes.dashboard case final swipe?)
            Positioned.fromRect(
              rect: swipe.rect,
              child: DesktopPanelEdgeSwipe(
                edge: swipe.edge,
                onSwipe: widget.onOpenDashboard,
              ),
            ),
        ],
      ],
    );
  }
}
