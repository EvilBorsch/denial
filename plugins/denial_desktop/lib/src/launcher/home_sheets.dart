/// The sheets a vertical drag on the tablet's home opens, as on iPadOS: up
/// the app drawer, down search.
enum HomeSheet { drawer, search }

/// One vertical drag on home: the sheet it moves, decided by its first
/// movement.
class HomeSheetDrag {
  HomeSheetDrag({required this.drawerAllowed});

  /// The user has the drawer; without it a drag up moves nothing.
  final bool drawerAllowed;

  /// The sheet this drag moves; null before it has moved, or when it moves
  /// none.
  HomeSheet? get sheet => _sheet;
  HomeSheet? _sheet;
  bool _decided = false;

  /// The drag moved [down] logical pixels (negative up): the sheet it
  /// moves, if any.
  HomeSheet? move(double down) {
    if (!_decided && down != 0) {
      _decided = true;
      _sheet = down < 0
          ? (drawerAllowed ? HomeSheet.drawer : null)
          : HomeSheet.search;
    }
    return _sheet;
  }
}

/// A release faster than this, in logical pixels per second, decides by
/// its direction alone.
const double homeSheetFlick = 600;

/// The share of its travel past which the drawer opens on a slow release.
const double homeDrawerOpenShare = 0.4;

/// The share of its travel past which search opens on a slow release: as on
/// iPadOS, a short pull suffices.
const double homeSearchOpenShare = 0.3;

/// Whether a sheet let go at [openness] (0 closed, 1 open), moving at
/// [openingVelocity] (logical pixels per second toward open), opens.
bool homeSheetOpens({
  required double openness,
  required double openingVelocity,
  required double openShare,
}) {
  if (openingVelocity > homeSheetFlick) return true;
  if (openingVelocity < -homeSheetFlick) return false;
  return openness > openShare;
}
