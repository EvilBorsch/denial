import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/applications.dart';

import 'home_icon_locator.dart' show launcherAppIdentity;

/// The home application a window of [appId] belongs to: its name and icon,
/// and its home item when home has one. All null for a window of an app
/// that is not on home.
typedef WindowApplication = ({
  String? name,
  String? iconPath,
  IconData? icon,
  HomeGridItem? item,
});

/// [WindowApplication] by a window's app id, for labels and search.
final windowApplicationProvider = Provider.autoDispose
    .family<WindowApplication, String>((ref, appId) {
      final local = ref.watch(localFlutterApplicationRegistryProvider)[appId];
      final apps =
          ref.watch(homeGridControllerProvider).value?.apps ??
          const <HomeGridItem>[];
      if (local != null) {
        return (
          name: local.title,
          iconPath: null,
          icon: local.icon,
          item: apps.where((item) => item.localApp?.id == appId).firstOrNull,
        );
      }
      final id = launcherAppIdentity(appId);
      final launcher = ref.watch(appLauncherProvider);
      for (final item in apps) {
        final app = item.app;
        if (app == null) continue;
        if (launcher
            .expectedWindowAppIds(app)
            .any((candidate) => launcherAppIdentity(candidate) == id)) {
          return (
            name: app.name,
            iconPath: app.iconPath,
            icon: null,
            item: item,
          );
        }
      }
      return (name: null, iconPath: null, icon: null, item: null);
    });
