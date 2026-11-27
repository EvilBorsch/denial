import 'dart:async';
import 'dart:convert';

import 'package:denial_flutter_sdk/actions.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/denial_bridge.dart';
import '../platform/denial_bridge_provider.dart';

/// Binds a generated action list to the native shortcut bridge. Custom shells
/// can use this host without adopting the reference desktop's widget hierarchy.
class ShellActionsBinding extends ConsumerStatefulWidget {
  const ShellActionsBinding({
    super.key,
    required this.actions,
    required this.services,
    required this.child,
  });
  final List<ShellAction> actions;
  final ShellServices services;
  final Widget child;
  @override
  ConsumerState<ShellActionsBinding> createState() =>
      _ShellActionsBindingState();
}

class _ShellActionsBindingState extends ConsumerState<ShellActionsBinding> {
  late final DenialBridge _bridge;
  StreamSubscription<({int generation, String id, int? monitorId})>?
  _subscription;
  Map<String, ShellAction> _handlers = const {};
  List<Map<String, Object>> _lastDescriptors = const [];
  int _generation = 0;
  String? _published;
  static int _nextGeneration = DateTime.now().microsecondsSinceEpoch;
  static final Map<DenialBridge, List<_ShellActionsBindingState>>
  _mountedByBridge =
      Map<DenialBridge, List<_ShellActionsBindingState>>.identity();
  static final Map<DenialBridge, _ShellActionsBindingState>
  _activeOwnerByBridge =
      Map<DenialBridge, _ShellActionsBindingState>.identity();

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(denialBridgeProvider);
    _mountedByBridge
        .putIfAbsent(_bridge, () => <_ShellActionsBindingState>[])
        .add(this);
    _subscription = _bridge.pluginActions.listen((event) {
      if (!mounted || event.generation != _generation) return;
      final handler = _handlers[event.id];
      if (handler == null) return;
      unawaited(
        Future<void>.sync(
          () => handler.invoke(
            ShellActionContext(
              services: widget.services,
              monitorId: event.monitorId,
            ),
          ),
        ).catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'Denial plugin actions',
              context: ErrorDescription('invoking ${event.id}'),
            ),
          );
        }),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publish();
  }

  @override
  void didUpdateWidget(covariant ShellActionsBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publish();
  }

  void _publish() {
    final handlers = <String, ShellAction>{};
    final descriptors = <Map<String, Object>>[];
    final identity = RegExp(r'^[a-z0-9_]+\.[A-Za-z0-9_.-]+$');
    if (widget.actions.length > 256) {
      throw StateError('Too many plugin actions (maximum 256)');
    }
    bool validText(String value, int limit, {bool required = false}) =>
        (!required || value.isNotEmpty) &&
        utf8.encode(value).length <= limit &&
        !value.runes.any((rune) => rune < 32 || (rune >= 127 && rune <= 159));
    for (final action in widget.actions) {
      if (action.id.length > 256 ||
          !identity.hasMatch(action.id) ||
          action.id.startsWith('native.') ||
          handlers.containsKey(action.id)) {
        throw StateError('Invalid or duplicate plugin action ID: ${action.id}');
      }
      final label = action.label(context);
      final description = action.description(context);
      if (!validText(label, 256, required: true) ||
          !validText(description, 2048) ||
          !validText(action.provider, 256, required: true)) {
        throw StateError('Invalid plugin action metadata: ${action.id}');
      }
      handlers[action.id] = action;
      descriptors.add({
        'id': action.id,
        'label': label,
        'description': description,
        'provider': action.provider,
      });
    }
    final signature = jsonEncode(descriptors);
    if (utf8.encode(signature).length > 128 * 1024) {
      throw StateError('Plugin action catalog exceeds 128 KiB');
    }
    _handlers = handlers;
    _lastDescriptors = descriptors;
    if (_activeOwnerByBridge[_bridge] == this && _published == signature) {
      return;
    }
    _published = signature;
    _activeOwnerByBridge[_bridge] = this;
    _generation = ++_nextGeneration;
    _bridge.publishPluginActions(_generation, descriptors);
  }

  void _republishCached() {
    if (!mounted) return;
    _activeOwnerByBridge[_bridge] = this;
    _generation = ++_nextGeneration;
    _bridge.publishPluginActions(_generation, _lastDescriptors);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _handlers = const {};
    final list = _mountedByBridge[_bridge];
    list?.remove(this);
    if (_activeOwnerByBridge[_bridge] == this) {
      _activeOwnerByBridge.remove(_bridge);
      // Во время переключения режимов (mobile <-> desktop) новый биндинг уже
      // смонтирован до dispose старого: передаём каталог выжившему биндингу
      // вместо затирания его пустым списком.
      if (list != null && list.isNotEmpty) {
        list.last._republishCached();
      } else {
        _mountedByBridge.remove(_bridge);
        _bridge.publishPluginActions(++_nextGeneration, const []);
      }
    } else if (list != null && list.isEmpty) {
      _mountedByBridge.remove(_bridge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
