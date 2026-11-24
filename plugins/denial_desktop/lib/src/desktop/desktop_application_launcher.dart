import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/default_shell/panel_composition.dart';
import '../search/shell_search_backend.dart';
import 'desktop_workspace.dart';

/// Runtime adapter for a launcher plugin that replaces the one search as the
/// desktop's launcher. The shipped shell has none since eb19: a bare Super
/// and four fingers up open the one search. A plugin gets the apps of the
/// one index and does its own presentation.
class DesktopApplicationLauncher extends ConsumerStatefulWidget {
  const DesktopApplicationLauncher({
    super.key,
    required this.searchFocusNode,
    required this.onEnter,
    required this.onExit,
    required this.onDismiss,
    required this.onLaunch,
    required this.onLaunchLocal,
  });

  final FocusNode searchFocusNode;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onDismiss;
  final ValueChanged<DesktopApp> onLaunch;
  final ValueChanged<LocalFlutterApplication> onLaunchLocal;

  @override
  ConsumerState<DesktopApplicationLauncher> createState() =>
      _DesktopApplicationLauncherHostState();
}

class _DesktopApplicationLauncherHostState
    extends ConsumerState<DesktopApplicationLauncher> {
  final ShellSearchIndexCache _indexCache = ShellSearchIndexCache();
  ShellSearchIndex _index = ShellSearchIndex.empty;

  void _launch(String id) {
    final app = _index[id];
    if (app?.desktopApp case final desktop?) {
      widget.onLaunch(desktop);
    } else if (app?.localApp case final local?) {
      widget.onLaunchLocal(local);
    }
  }

  Widget _buildIcon(BuildContext context, String id) {
    final app = _index[id];
    if (app?.localApp case final local?) {
      return ExcludeSemantics(
        child: Icon(
          local.icon,
          size: 46,
          color: context.shellTheme.accentPalette.primary,
        ),
      );
    }
    return DeferredAppIcon(iconPath: app?.desktopApp?.iconPath);
  }

  @override
  Widget build(BuildContext context) {
    final plugin = ref.watch(desktopLauncherProvider);
    if (plugin == null) return const SizedBox.shrink();
    _index = _indexCache.resolve(context, ref);
    return plugin.build(
      context,
      launcher: LauncherContext(
        applications: _index.launcherApplications,
        recentApplicationIds: ref.watch(applicationRecentsProvider),
        visible: ref.watch(
          desktopWorkspaceProvider.select((state) => state.launcherOpen),
        ),
        searchFocusNode: widget.searchFocusNode,
        onEnter: widget.onEnter,
        onExit: widget.onExit,
        onDismiss: widget.onDismiss,
        onLaunch: _launch,
        buildIcon: _buildIcon,
        strings: _RuntimeLauncherStrings(context.l10n),
        linkCursor: ShellMouseCursors.link,
        textCursor: ShellMouseCursors.text,
      ),
    );
  }
}

class _RuntimeLauncherStrings implements LauncherStrings {
  const _RuntimeLauncherStrings(this.l10n);
  final AppLocalizations l10n;
  @override
  String get suggestionsTitle => l10n.desktopApplicationSuggestionsTitle;
  @override
  String get searchApplications => l10n.desktopSearchApplications;
  @override
  String get clearSearch => l10n.desktopClearApplicationSearch;
  @override
  String get noApplicationsFound => l10n.desktopNoApplicationsFound;
  @override
  String get loadingApplications => l10n.desktopLoadingApplications;
  @override
  String launchApplication(String name) => l10n.desktopLaunchApplication(name);
}
