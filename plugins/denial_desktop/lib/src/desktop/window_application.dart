import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/applications.dart';

import '../launcher/home_icon_locator.dart' show launcherAppIdentity;

/// The name and icon of the app a window belongs to: an installed app's, a
/// local Flutter app's, or none for an app the launcher does not know.
typedef WindowApplication = ({String? name, String? iconPath, IconData? icon});

/// [WindowApplication] by window app ID, shared by the overview's labels and
/// the app switcher.
final windowApplicationProvider = Provider.autoDispose
    .family<WindowApplication, String>((ref, appId) {
      final local = ref.watch(localFlutterApplicationRegistryProvider)[appId];
      if (local != null) {
        return (name: local.title, iconPath: null, icon: local.icon);
      }
      final id = launcherAppIdentity(appId);
      final launcher = ref.watch(appLauncherProvider);
      for (final item
          in ref.watch(homeGridControllerProvider).value?.apps ??
              const <HomeGridItem>[]) {
        final app = item.app;
        if (app == null) continue;
        if (launcher
            .expectedWindowAppIds(app)
            .any((candidate) => launcherAppIdentity(candidate) == id)) {
          return (name: app.name, iconPath: app.iconPath, icon: null);
        }
      }
      return (name: null, iconPath: null, icon: null);
    });
