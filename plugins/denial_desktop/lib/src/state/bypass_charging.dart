import 'dart:async';
import 'dart:io';

import 'package:denial_flutter_sdk/motion.dart' show SelectedListenable;
import 'package:denial_flutter_sdk/state.dart' show batteryProvider;
import 'package:denial_sdk/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/shade/shade_progress.dart';

/// Bypass charging through the kernel's power-supply interface. A battery
/// whose `charge_behaviour` attribute offers `inhibit-charge` holds its
/// charging off while that behaviour is selected, and a connected charger
/// then powers the system directly. The kernel holds the choice, so it
/// outlives the session lock and a restart of the shell; the shell only
/// reads and switches it.
///
/// The kernel lists the behaviours it offers and brackets the selected one,
/// as in `[auto] inhibit-charge`. Returns whether `inhibit-charge` is
/// selected, or null when it is not offered.
bool? parseBypassCharging(String contents) {
  var offered = false;
  for (final word in contents.trim().split(_whitespace)) {
    if (word == '[$_inhibit]') return true;
    if (word == _inhibit) offered = true;
  }
  return offered ? false : null;
}

const _inhibit = 'inhibit-charge';
const _auto = 'auto';
final _whitespace = RegExp(r'\s+');

/// A battery's `charge_behaviour` that offers bypass charging and that this
/// user may write, with whether bypass is selected.
typedef BypassChargingReading = ({String attribute, bool on});

/// Finds, reads and writes the `charge_behaviour` of a battery that offers
/// bypass charging.
class BypassChargingService {
  const BypassChargingService({
    this.powerSupplyRoot = '/sys/class/power_supply',
    this.writeAttribute = _writeSysfs,
  });

  /// The tablet's battery manager, preferred when several batteries offer
  /// bypass charging.
  static const preferredSupply = 'qcom-battmgr-bat';

  final String powerSupplyRoot;

  /// Writes a value to an attribute. Throws [FileSystemException] when the
  /// kernel refuses it.
  final Future<void> Function(String path, String value) writeAttribute;

  /// The battery that offers bypass charging and whether bypass is selected,
  /// or null when no battery offers it or this user cannot write it.
  Future<BypassChargingReading?> probe() async {
    final List<String> supplies;
    try {
      supplies = [
        await for (final entity in Directory(powerSupplyRoot).list())
          entity.path,
      ];
    } on FileSystemException {
      return null;
    }
    supplies.sort((a, b) {
      final preferred =
          (_named(b, preferredSupply) ? 1 : 0) -
          (_named(a, preferredSupply) ? 1 : 0);
      return preferred != 0 ? preferred : a.compareTo(b);
    });
    for (final supply in supplies) {
      if ((await _read('$supply/type'))?.trim().toLowerCase() != 'battery') {
        continue;
      }
      final attribute = '$supply/charge_behaviour';
      final contents = await _read(attribute);
      final on = contents == null ? null : parseBypassCharging(contents);
      if (on != null && await _writable(attribute)) {
        return (attribute: attribute, on: on);
      }
    }
    return null;
  }

  /// Selects `inhibit-charge` when [on], else `auto`.
  Future<void> write(String attribute, bool on) =>
      writeAttribute(attribute, on ? _inhibit : _auto);

  static bool _named(String path, String name) => path.endsWith('/$name');

  static Future<String?> _read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// Opening an attribute for writing changes nothing: the kernel acts only
  /// on what is written.
  static Future<bool> _writable(String path) async {
    try {
      await (await File(path).open(mode: FileMode.writeOnlyAppend)).close();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// A sysfs attribute takes one plain write; nothing is written aside.
  static Future<void> _writeSysfs(String path, String value) =>
      File(path).writeAsString(value, mode: FileMode.writeOnly);
}

@immutable
class BypassChargingState {
  const BypassChargingState({
    this.available = false,
    this.on = false,
    this.busy = false,
    this.failed = false,
  });

  /// A battery offers bypass charging and this user may switch it.
  final bool available;

  /// The battery's charging is held off.
  final bool on;

  /// A switch is being written and read back.
  final bool busy;

  /// The last switch was refused. The tile shows it unavailable until the
  /// shade is next opened.
  final bool failed;

  @override
  bool operator ==(Object other) =>
      other is BypassChargingState &&
      other.available == available &&
      other.on == on &&
      other.busy == busy &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(available, on, busy, failed);
}

final bypassChargingServiceProvider = Provider<BypassChargingService>(
  (ref) => const BypassChargingService(),
);

final bypassChargingProvider =
    NotifierProvider<BypassChargingController, BypassChargingState>(
      BypassChargingController.new,
      isAutoDispose: true,
    );

/// Follows and switches bypass charging. The state is read again when the
/// shade starts to open, when the battery's state changes (the charger
/// plugged in or out, as the battery source samples it) and after every
/// switch, so a change made outside the shell shows too. Nothing polls on
/// its own.
class BypassChargingController extends Notifier<BypassChargingState> {
  late BypassChargingService _service;
  int _generation = 0;
  String? _attribute;
  bool _switching = false;
  Future<void> _queue = Future<void>.value();

  @override
  BypassChargingState build() {
    _service = ref.watch(bypassChargingServiceProvider);
    final generation = ++_generation;
    _attribute = null;
    _switching = false;
    _queue = Future<void>.value();

    final shade = ref.watch(shadeProgressProvider);
    final shown = SelectedListenable<bool>(shade, () => shade.value > 0);
    void opened() {
      if (shown.value) unawaited(refresh(clearFailure: true));
    }

    shown.addListener(opened);
    ref.onDispose(() {
      shown.removeListener(opened);
      shown.dispose();
    });
    ref.listen<BatteryStatus>(batteryProvider, (_, _) => unawaited(refresh()));
    scheduleMicrotask(() {
      if (_active(generation)) unawaited(refresh());
    });
    return const BypassChargingState();
  }

  bool _active(int generation) => ref.mounted && generation == _generation;

  /// Reads the state again. A refused switch stays shown until a refresh
  /// with [clearFailure].
  Future<void> refresh({bool clearFailure = false}) {
    final generation = _generation;
    return _serialized(() async {
      final reading = await _service.probe();
      if (!_active(generation)) return;
      _accept(reading, failed: !clearFailure && state.failed);
    });
  }

  /// Turns bypass charging on when it is off, and off when it is on.
  Future<void> toggle() {
    final attribute = _attribute;
    if (attribute == null || !state.available || state.busy || state.failed) {
      return Future<void>.value();
    }
    final on = !state.on;
    final generation = _generation;
    _switching = true;
    state = BypassChargingState(available: true, on: state.on, busy: true);
    return _serialized(() async {
      var failed = false;
      try {
        await _service.write(attribute, on);
      } on Object catch (error) {
        failed = true;
        final reason = error is FileSystemException
            ? (error.osError?.toString() ?? error.message)
            : '$error';
        debugPrint(
          'Bypass charging: writing ${on ? _inhibit : _auto} to $attribute '
          'failed: $reason',
        );
      }
      final reading = await _service.probe();
      if (!_active(generation)) return;
      _switching = false;
      _accept(reading, failed: failed);
    });
  }

  void _accept(BypassChargingReading? reading, {required bool failed}) {
    _attribute = reading?.attribute;
    final next = reading == null
        ? const BypassChargingState()
        : BypassChargingState(
            available: true,
            on: reading.on,
            // A read that lands before a pending switch keeps the tile
            // waiting for it.
            busy: _switching,
            failed: failed,
          );
    if (next != state) state = next;
  }

  /// One read or write at a time, in order: a read queued behind a write
  /// sees what the write left.
  Future<void> _serialized(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((Object _) {});
    return next;
  }
}
