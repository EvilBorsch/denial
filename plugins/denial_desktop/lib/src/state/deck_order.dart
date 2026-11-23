/// Recents lays the windows of one app side by side.
library;

/// [order], windows from least to most recently in front, with the windows
/// of each app together: apps in the order of their most recent window,
/// and each app's windows in their own order. The most recent window stays
/// last, so the screen still rests on it, and the window next to it is
/// another of its app's, which a swipe of the home pill reaches first.
///
/// [appOf] names a window's app; windows it gives no app to stay apps of
/// their own.
List<int> groupedByApp(List<int> order, String? Function(int window) appOf) {
  final groups = <Object, List<int>>{};
  // From the most recent: an app's place is that of its newest window.
  for (final id in order.reversed) {
    final Object key = appOf(id) ?? _Alone(id);
    (groups[key] ??= <int>[]).add(id);
  }
  return [
    for (final windows in groups.values.toList().reversed) ...windows.reversed,
  ];
}

/// The windows of [order] that belong to the app of [window], in order.
List<int> windowsOfAppOf(
  int window,
  List<int> order,
  String? Function(int window) appOf,
) {
  final app = appOf(window);
  if (app == null) return [window];
  return [
    for (final id in order)
      if (appOf(id) == app) id,
  ];
}

/// The group key of a window without an app.
final class _Alone {
  const _Alone(this.id);
  final int id;

  @override
  bool operator ==(Object other) => other is _Alone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
