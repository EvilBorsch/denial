# App Launcher

The reference desktop's launcher action, compiled as an independently
selectable Denial plugin. It provides one `ShellAction`,
`denial_launcher.openApplications`, which a bare Super and four fingers up are
bound to in the shortcut files, and depends only on public SDKs and Flutter.

Since the EvilBorsch fork's eb19 the plugin no longer provides `ShellLauncher`
and has no presentation or matching of its own: the shell has one search for
every way in (a bare Super, Super+S, Alt+F in the Mac preset, four fingers up),
and without a launcher plugin this action opens it. The search's index, matching
and ranking live in `plugins/denial_desktop/lib/src/search/`, and a test fails
when app filtering appears anywhere else. The action's id stays, so the shortcut
files of earlier builds keep working.

The built-in default preset and handwritten development entry point select this
plugin. Disabling it removes the action; Super+S and Alt+F still open the
search.

An alternative launcher can still implement `ShellLauncher` and supply
`@Provides(ShellLauncher)` in a `@Plugin()` library; the reference desktop then
shows it as its launcher panel instead of the search. Do not depend on this
package merely to implement an alternative—depend on the SDK contract instead.

Validation uses Dart analysis, the manager's
`integration_test/launcher_composition_test.dart` (after resolving the shell's
Pub dependencies), and a release bundle build. Visual validation belongs to the
user; the integration check does not launch any UI or use a debug engine.
