import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/rendering.dart';
import 'package:denial_flutter_sdk/shell_color_scheme.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';

import '../../launcher/window_application.dart';

/// The app icon and name above a card, aligned to its start edge. With
/// [showsTitle], for an app with several windows in Recents, the window's
/// title under the name tells its cards apart.
class OverviewCardLabel extends ConsumerWidget {
  const OverviewCardLabel({
    super.key,
    required this.window,
    this.trailingSpace = 0,
    this.showsTitle = false,
  });

  static const double height = iconSize;
  static const double iconSize = 48;
  static const double gap = 12;

  final DenialWindow window;

  /// Room kept free at the end of the row, for a button over it.
  final double trailingSpace;

  /// The window's title goes under the app's name.
  final bool showsTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(windowApplicationProvider(window.appId));
    final colors = context.shellColors;
    final icon = application.icon;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox.square(
            dimension: iconSize,
            child: icon != null
                ? FittedBox(child: Icon(icon, color: colors.textPrimary))
                : AppIconImage(iconPath: application.iconPath),
          ),
          const SizedBox(width: 12),
          Flexible(child: _names(context, application.name, colors)),
          if (trailingSpace > 0) SizedBox(width: trailingSpace),
        ],
      ),
    );
  }

  Widget _names(BuildContext context, String? app, ShellColorScheme colors) {
    final title = localizedWindowTitle(context, window);
    final name = Text(
      app ?? title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 17,
        fontWeight: showsTitle ? FontWeight.w600 : FontWeight.w400,
        height: showsTitle ? 1.15 : 1,
        letterSpacing: 0,
        decoration: TextDecoration.none,
      ),
    );
    if (!showsTitle || app == null || title.isEmpty || title == app) {
      return name;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        name,
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            height: 1.25,
            letterSpacing: 0,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
