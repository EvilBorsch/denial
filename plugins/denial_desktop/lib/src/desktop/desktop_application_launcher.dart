import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/default_shell/panel_composition.dart';
import 'desktop_application_catalog.dart';
import 'desktop_workspace.dart';

/// Runtime adapter for the statically selected launcher presentation.
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
  final DesktopApplicationCatalogCache _catalogCache =
      DesktopApplicationCatalogCache();
  DesktopApplicationCatalog _catalog = DesktopApplicationCatalog.empty;

  void _launch(String id) {
    if (_catalog.desktopApps[id] case final app?) {
      widget.onLaunch(app);
    } else if (_catalog.localApps[id] case final app?) {
      widget.onLaunchLocal(app);
    }
  }

  Widget _buildIcon(BuildContext context, String id) {
    if (_catalog.localApps[id] case final app?) {
      return ExcludeSemantics(
        child: Icon(
          app.icon,
          size: 46,
          color: context.shellTheme.accentPalette.primary,
        ),
      );
    }
    return DeferredAppIcon(iconPath: _catalog.desktopApps[id]?.iconPath);
  }

  @override
  Widget build(BuildContext context) {
    final plugin = ref.watch(desktopLauncherProvider);
    if (plugin == null) return const SizedBox.shrink();
    _catalog = _catalogCache.resolve(
      context,
      slots: ref.watch(
        homeGridControllerProvider.select((state) => state.asData?.value.slots),
      ),
      registry: ref.watch(localFlutterApplicationRegistryProvider),
      launcher: ref.watch(appLauncherProvider),
    );
    return plugin.build(
      context,
      launcher: LauncherContext(
        applications: _catalog.applications,
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
