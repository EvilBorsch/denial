import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The search over the desktop (a bare Super, Super+S, Alt+F in the Mac
/// preset, four fingers up): the monitor it is open on, or null while it is
/// closed. Its results come from the shell's one search backend
/// (`search/shell_search_backend.dart`).
final desktopSearchOverlayProvider =
    NotifierProvider<DesktopSearchOverlayController, int?>(
      DesktopSearchOverlayController.new,
    );

class DesktopSearchOverlayController extends Notifier<int?> {
  @override
  int? build() => null;

  void open(int monitorId) => state = monitorId;

  void close() => state = null;
}
