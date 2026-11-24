@Plugin()
library;

import 'package:denial_sdk/composition.dart';
import 'package:denial_flutter_sdk/actions.dart';
import 'package:flutter/widgets.dart';

/// Opens the shell's launcher: a bare Super and four fingers up, whose
/// shortcuts name this action's id. Since eb19 the reference desktop has one
/// search for every way in (Super, Super+S, Alt+F, four fingers up), with no
/// launcher of its own beside it: without a launcher plugin, this action
/// opens that search. The id stays, so the shortcut files of earlier builds
/// keep working.
///
/// The launcher only routes the action; Rust only routes its stable
/// identity.
@Provides(ShellAction)
final class OpenApplicationsAction implements ShellAction {
  const OpenApplicationsAction();
  @override
  String get id => 'denial_launcher.openApplications';
  @override
  String get provider => 'Launcher';
  @override
  String label(BuildContext context) =>
      switch (Localizations.localeOf(context).languageCode) {
        'zh' => '打开应用列表',
        'ru' => 'Открыть приложения',
        _ => 'Open applications',
      };
  @override
  String description(BuildContext context) => '';
  @override
  void invoke(ShellActionContext context) => context.services.toggleLauncher();
}
