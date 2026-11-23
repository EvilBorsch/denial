import 'dart:math' as math;

import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_shell_search.dart';

/// The search over the desktop (the search key; Alt+F in the Mac preset):
/// the overview's search field and results, over the current screen.
///
/// Typing finds open windows by app and title, and apps to start; Enter
/// goes to the best one, the arrows choose another; Esc clears what was
/// typed, then closes, as does a click outside.
class DesktopSearchOverlay extends ConsumerStatefulWidget {
  const DesktopSearchOverlay({
    super.key,
    required this.viewSize,
    required this.displayLayout,
    required this.onActivateWindow,
    required this.onLaunchApplication,
    required this.onLaunchLocalApplication,
  });

  final Size viewSize;
  final DisplayLayout? displayLayout;
  final ValueChanged<DenialWindow> onActivateWindow;
  final ValueChanged<DesktopApp> onLaunchApplication;
  final ValueChanged<LocalFlutterApplication> onLaunchLocalApplication;

  /// Where the search's panel sits on an output's [workArea]: centred, a
  /// little above the middle, as wide as reads comfortably.
  static Rect panelBounds(Rect workArea) {
    final width = math.min(640.0, math.max(0.0, workArea.width - 48.0));
    return Rect.fromLTWH(
      workArea.center.dx - width / 2.0,
      workArea.top + workArea.height * 0.16,
      width,
      workArea.height * 0.68,
    );
  }

  @override
  ConsumerState<DesktopSearchOverlay> createState() =>
      _DesktopSearchOverlayState();
}

class _DesktopSearchOverlayState extends ConsumerState<DesktopSearchOverlay>
    with
        SingleTickerProviderStateMixin<DesktopSearchOverlay>,
        DesktopSearchHost<DesktopSearchOverlay> {
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: Motion.desktopPanelOpen,
    reverseDuration: Motion.desktopPanelFadeClose,
  )..addStatusListener(_presenceChanged);
  late final Animation<double> _scale = Tween<double>(begin: 0.96, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _presence,
          curve: Motion.md3EmphasizedDecelerate,
          reverseCurve: Motion.md3EmphasizedAccelerate,
        ),
      );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _presence,
    curve: Motion.standard,
  );

  /// The monitor the search is shown on, kept while it fades out.
  int? _monitorId;

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  void _presenceChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _monitorId = null);
    }
  }

  void _show(int monitorId) {
    _monitorId = monitorId;
    startSearch();
    if (MediaQuery.disableAnimationsOf(context)) {
      _presence.value = 1.0;
    } else {
      _presence.forward();
    }
  }

  void _hide() {
    searchFocusNode.unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _presence.value = 0.0;
    } else {
      _presence.reverse();
    }
  }

  void _close() => ref.read(desktopSearchOverlayProvider.notifier).close();

  @override
  void activateSearchWindow(int objectId) {
    final window = searchWindowOf(objectId);
    _close();
    if (window != null) {
      widget.onActivateWindow(window);
    }
  }

  @override
  void launchSearchApplication(String id) {
    final desktopApp = searchCatalog.desktopApps[id];
    final localApp = searchCatalog.localApps[id];
    _close();
    if (desktopApp != null) {
      widget.onLaunchApplication(desktopApp);
    } else if (localApp != null) {
      widget.onLaunchLocalApplication(localApp);
    }
  }

  @override
  void dismissSearch() => _close();

  Rect _workArea(int monitorId) {
    final canvas = Offset.zero & widget.viewSize;
    final layout = widget.displayLayout;
    if (layout == null) {
      return canvas;
    }
    DisplayOutput? output;
    for (final candidate in layout.outputs) {
      if (candidate.monitorId == monitorId) {
        output = candidate;
      }
    }
    output ??= layout.mainOutput;
    if (output == null) {
      return canvas;
    }
    final area = layout.workAreaOf(output).intersect(canvas);
    return area.isEmpty ? canvas : area;
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(desktopSearchOverlayProvider);
    ref.listen<int?>(desktopSearchOverlayProvider, (previous, next) {
      if (next != null && (previous == null || _monitorId == null)) {
        _show(next);
        setState(() {});
      } else if (next == null && previous != null) {
        _hide();
      }
    });
    final monitorId = _monitorId;
    if (monitorId == null) {
      return const SizedBox.shrink();
    }
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final workArea = _workArea(monitorId);
    final panel = DesktopSearchOverlay.panelBounds(workArea);
    final listing = resolveSearch(context);
    final listHeight = listing.searching
        ? DesktopSearchResultList.heightFor(
            listing,
            panel.height - DesktopSearchMetrics.fieldHeight - 24.0,
          )
        : 0.0;
    final radius = BorderRadius.circular(theme.panelRadius);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scrim = colors.overviewScrim;
    return ShellInputRegion(
      debugLabel: 'Desktop search',
      active: open != null,
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      compositorPolicy: ShellCompositorPolicy.exclusive,
      child: IgnorePointer(
        ignoring: open == null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: FadeTransition(
                  opacity: _fade,
                  child: ColoredBox(
                    color: scrim.withValues(alpha: scrim.a * 0.4),
                  ),
                ),
              ),
            ),
            Positioned(
              left: panel.left,
              top: panel.top,
              width: panel.width,
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: Alignment.topCenter,
                  child: ShellBackdropBlur(
                    blur: theme.effectivePanelOpacity < 1.0,
                    borderRadius: radius,
                    blendMode: BlendMode.srcOver,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.panelColor(colors.panelBackground),
                        borderRadius: radius,
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DesktopSearchField(
                              controller: searchController,
                              focusNode: searchFocusNode,
                              onSubmitted: submitSearch,
                              onClear: clearSearch,
                            ),
                            AnimatedSize(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : Motion.desktopPanelFadeOpen,
                              curve: Motion.md3EmphasizedDecelerate,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                height: listHeight,
                                child: listing.searching
                                    ? DesktopSearchResultList(
                                        listing: listing,
                                        selected: searchSelected,
                                        catalog: searchCatalog,
                                        onSelect: selectSearchEntry,
                                        onActivate: activateSearchEntry,
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
