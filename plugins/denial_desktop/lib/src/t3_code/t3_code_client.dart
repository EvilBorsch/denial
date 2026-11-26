import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:denial_flutter_sdk/settings.dart';

import 't3_code_models.dart';

/// Resolved local paths for an EvilBorsch T3 Code installation.
class T3InstallPaths {
  const T3InstallPaths({
    required this.installDir,
    required this.stateDir,
    required this.serverBinPath,
    required this.launchPath,
    required this.nodeRuntimePath,
    required this.nodeIsElectron,
  });

  final String installDir;
  final String stateDir;
  final String serverBinPath;
  final String? launchPath;
  final String nodeRuntimePath;
  final bool nodeIsElectron;

  bool get exists => File(serverBinPath).existsSync();
}

/// Callback invoked when the T3 Code Effect RPC stream emits a shell or thread
/// update.
typedef T3ShellEventHandler = void Function(Map<String, dynamic> item);
typedef T3ThreadEventHandler =
    void Function(String threadId, Map<String, dynamic> item);

/// Pure `dart:io` HTTP + Effect RPC WebSocket + GigaAM Voice streaming client
/// for the local T3 Code server.
class T3CodeClient {
  T3CodeClient();

  static const String _protocolVersion = '2';
  static const int _defaultPort = 3773;
  static const int _speechSampleRate = 16000;
  // 200 ms of 16 kHz mono Float32 PCM (3200 samples * 4 bytes = 12800 bytes).
  static const int _speechChunkBytes = 12800;
  static const Map<String, Object> _ruSpeechOptions = <String, Object>{
    'speechLanguage': 'ru',
    'speechTranslateToEnglish': false,
    'speechCustomWords': <Object>[],
    'speechRemoveFillerWords': true,
    'speechSilenceFiltering': true,
  };

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6);

  String? _bearerToken;
  String _origin = 'http://127.0.0.1:$_defaultPort';
  WebSocket? _rpcSocket;
  StreamSubscription<dynamic>? _rpcSubscription;
  int _nextReqSeq = 1;
  final Map<String, Completer<Object?>> _pendingUnary =
      <String, Completer<Object?>>{};
  final Map<String, void Function(Object? value)> _streamHandlers =
      <String, void Function(Object? value)>{};
  String? _threadSubId;
  String? _subscribedThreadId;

  // Voice recording state.
  Process? _recorderProcess;
  WebSocket? _voiceSocket;
  StreamSubscription<List<int>>? _recorderSub;
  StreamSubscription<dynamic>? _voiceSub;
  final BytesBuilder _pcmOverflow = BytesBuilder(copy: false);
  final BytesBuilder _pcmBackup = BytesBuilder(copy: false);
  Completer<String>? _voiceFinishCompleter;
  bool _voiceReady = false;
  bool _disposed = false;

  String get origin => _origin;
  bool get rpcConnected =>
      _rpcSocket != null && _rpcSocket!.readyState == WebSocket.open;

  static String get homeDir =>
      Platform.environment['HOME'] ?? '/home/dmitry';

  static String expandPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '~') return homeDir;
    if (trimmed.startsWith('~/')) {
      return '$homeDir/${trimmed.substring(2)}';
    }
    return trimmed;
  }

  /// Resolves the local T3 Code installation from [settings] or standard paths.
  static T3InstallPaths? discoverInstall(ShellT3CodeSettings settings) {
    final candidates = <String>[
      if (settings.installDir.trim().isNotEmpty)
        expandPath(settings.installDir),
      '$homeDir/.local/share/t3code-evilborsch',
      '$homeDir/.t3code',
    ];
    for (final root in candidates) {
      final serverBin = '$root/app/apps/server/dist/bin.mjs';
      if (!File(serverBin).existsSync()) continue;
      final stateDir = Directory('$root/state').existsSync()
          ? '$root/state'
          : '$homeDir/.t3';
      final launch = File('$root/launch').existsSync() ? '$root/launch' : null;
      final runtime = _findNodeRuntime(root);
      if (runtime == null) continue;
      return T3InstallPaths(
        installDir: root,
        stateDir: stateDir,
        serverBinPath: serverBin,
        launchPath: launch,
        nodeRuntimePath: runtime.$1,
        nodeIsElectron: runtime.$2,
      );
    }
    return null;
  }

  static (String, bool)? _findNodeRuntime(String installRoot) {
    final directElectron = <String>[
      '$installRoot/app/apps/desktop/node_modules/electron/dist/electron',
      '$installRoot/app/node_modules/electron/dist/electron',
    ];
    for (final candidate in directElectron) {
      if (File(candidate).existsSync()) {
        return (candidate, true);
      }
    }
    final pnpmDir = Directory('$installRoot/app/node_modules/.pnpm');
    if (pnpmDir.existsSync()) {
      try {
        for (final entry in pnpmDir.listSync(followLinks: false)) {
          final name = entry.path.split('/').last;
          if (!name.startsWith('electron@')) continue;
          final bin =
              '${entry.path}/node_modules/electron/dist/electron';
          if (File(bin).existsSync()) {
            return (bin, true);
          }
        }
      } catch (_) {}
    }
    for (final bin in const <String>[
      '/usr/bin/node',
      '/usr/local/bin/node',
    ]) {
      if (File(bin).existsSync()) return (bin, false);
    }
    return null;
  }

  /// Discovers the live server origin (`server-runtime.json` or port 3773).
  Future<String?> discoverRunningOrigin(T3InstallPaths paths) async {
    final runtimeFiles = <String>[
      '${paths.stateDir}/userdata/server-runtime.json',
      '${paths.stateDir}/server-runtime.json',
      '$homeDir/.t3/userdata/server-runtime.json',
    ];
    for (final filePath in runtimeFiles) {
      final file = File(filePath);
      if (!file.existsSync()) continue;
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map && raw['origin'] is String) {
          final candidate = (raw['origin'] as String).trim();
          if (await _probeOrigin(candidate)) {
            _origin = candidate;
            return candidate;
          }
        }
      } catch (_) {}
    }
    const fallback = 'http://127.0.0.1:$_defaultPort';
    if (await _probeOrigin(fallback)) {
      _origin = fallback;
      return fallback;
    }
    return null;
  }

  Future<bool> _probeOrigin(String candidateOrigin) async {
    try {
      final uri = Uri.parse('$candidateOrigin/.well-known/t3/environment');
      final req = await _http.getUrl(uri).timeout(const Duration(seconds: 2));
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Launches T3 Code Desktop (or server) when installed but not yet running.
  Future<bool> launchT3Code(T3InstallPaths paths) async {
    try {
      if (paths.launchPath != null) {
        await Process.start(
          paths.launchPath!,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start(
          paths.nodeRuntimePath,
          <String>[
            paths.serverBinPath,
            'start',
            '--no-browser',
            '--base-dir',
            paths.stateDir,
          ],
          environment: paths.nodeIsElectron
              ? const <String, String>{'ELECTRON_RUN_AS_NODE': '1'}
              : null,
          mode: ProcessStartMode.detached,
        );
      }
      // Wait up to 15 s for the local server to bind.
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await discoverRunningOrigin(paths) != null) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Focuses or opens the T3 Code Desktop app (optionally targeting a thread).
  Future<void> openDesktopApp(
    T3InstallPaths paths, {
    String? workspaceRoot,
  }) async {
    if (paths.launchPath == null) return;
    try {
      final args = <String>[
        if (workspaceRoot != null && workspaceRoot.isNotEmpty) workspaceRoot,
      ];
      await Process.start(
        paths.launchPath!,
        args,
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  String get _sessionTokenFilePath {
    final xdgState =
        Platform.environment['XDG_STATE_HOME'] ?? '$homeDir/.local/state';
    return '$xdgState/denial/t3-session.json';
  }

  /// Returns a valid bearer token for the local T3 Code server, minting one
  /// through T3's CLI `auth session issue` when absent or expired.
  Future<String> ensureBearerToken(
    T3InstallPaths paths, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _bearerToken != null && _bearerToken!.isNotEmpty) {
      if (await _validateToken(_bearerToken!)) {
        return _bearerToken!;
      }
    }
    if (!forceRefresh) {
      final cached = await _readCachedToken();
      if (cached != null && await _validateToken(cached)) {
        _bearerToken = cached;
        return cached;
      }
    }
    final env = <String, String>{
      ...Platform.environment,
      'T3CODE_HOME': paths.stateDir,
      if (paths.nodeIsElectron) 'ELECTRON_RUN_AS_NODE': '1',
    };
    final result = await Process.run(
      paths.nodeRuntimePath,
      <String>[
        paths.serverBinPath,
        'auth',
        'session',
        'issue',
        '--base-dir',
        paths.stateDir,
        '--label',
        'Denial Shell',
        '--ttl',
        '30d',
        '--token-only',
      ],
      environment: env,
    ).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError(
        'T3 Code auth failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    final token = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .lastOrNull;
    if (token == null || token.isEmpty) {
      throw StateError('T3 Code auth returned an empty session token.');
    }
    _bearerToken = token;
    await _writeCachedToken(token);
    return token;
  }

  Future<bool> _validateToken(String token) async {
    try {
      final req = await _http.getUrl(Uri.parse('$_origin/api/auth/session'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await utf8.decodeStream(res);
      if (res.statusCode != 200) return false;
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['authenticated'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readCachedToken() async {
    final file = File(_sessionTokenFilePath);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['token'] is String) {
        final token = (decoded['token'] as String).trim();
        return token.isEmpty ? null : token;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeCachedToken(String token) async {
    try {
      final file = File(_sessionTokenFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object>{
          'origin': _origin,
          'token': token,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await Process.run('chmod', <String>['600', file.path]);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _httpJson(
    String method,
    String path, {
    required T3InstallPaths paths,
    Object? body,
    Map<String, String>? extraHeaders,
    bool retried = false,
  }) async {
    final token = await ensureBearerToken(paths, forceRefresh: retried);
    final uri = Uri.parse('$_origin$path');
    final req = await _http.openUrl(method, uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (extraHeaders != null) {
      extraHeaders.forEach(req.headers.set);
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decodeStream(res);
    if (res.statusCode == 401 && !retried) {
      return _httpJson(
        method,
        path,
        paths: paths,
        body: body,
        extraHeaders: extraHeaders,
        retried: true,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'T3 HTTP ${res.statusCode} on $method $path: $text',
        uri: uri,
      );
    }
    if (text.trim().isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }

  Future<String> _mintWsTicket(T3InstallPaths paths, String use) async {
    final json = await _httpJson(
      'POST',
      '/api/auth/websocket-ticket/$use',
      paths: paths,
    );
    final ticket = json['ticket'];
    if (ticket is! String || ticket.isEmpty) {
      throw StateError('T3 server did not return a WebSocket ticket.');
    }
    return ticket;
  }

  /// Connects the persistent Effect RPC WebSocket and subscribes to the global
  /// shell stream (all projects and threads, including those opened in T3 UI).
  Future<void> connectRpc(
    T3InstallPaths paths, {
    required T3ShellEventHandler onShellItem,
    required void Function() onDisconnect,
  }) async {
    await disconnectRpc();
    final ticket = await _mintWsTicket(paths, 'rpc');
    final wsOrigin = _origin
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl =
        '$wsOrigin/ws?orchestrationProtocol=$_protocolVersion&ticket=${Uri.encodeQueryComponent(ticket)}';
    final socket = await WebSocket.connect(
      wsUrl,
    ).timeout(const Duration(seconds: 8));
    _rpcSocket = socket;
    _rpcSubscription = socket.listen(
      _handleRpcFrame,
      onError: (_) => _handleRpcClosed(onDisconnect),
      onDone: () => _handleRpcClosed(onDisconnect),
      cancelOnError: false,
    );

    // Subscribe to the live shell projection stream.
    _sendStreamRequest(
      'orchestration.subscribeShell',
      const <String, Object>{},
      (value) {
        if (value is Map<String, dynamic>) {
          onShellItem(value);
        } else if (value is Map) {
          onShellItem(Map<String, dynamic>.from(value));
        }
      },
    );
  }

  void _handleRpcClosed(void Function() onDisconnect) {
    final socket = _rpcSocket;
    _rpcSocket = null;
    _threadSubId = null;
    _subscribedThreadId = null;
    _streamHandlers.clear();
    for (final pending in _pendingUnary.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('T3 WebSocket closed.'));
      }
    }
    _pendingUnary.clear();
    if (socket != null && !_disposed) {
      onDisconnect();
    }
  }

  Future<void> disconnectRpc() async {
    _threadSubId = null;
    _subscribedThreadId = null;
    _streamHandlers.clear();
    await _rpcSubscription?.cancel();
    _rpcSubscription = null;
    final socket = _rpcSocket;
    _rpcSocket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  void _handleRpcFrame(dynamic raw) {
    if (raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          _dispatchRpcMessage(Map<String, dynamic>.from(item));
        }
      }
    } else if (decoded is Map) {
      _dispatchRpcMessage(Map<String, dynamic>.from(decoded));
    }
  }

  void _dispatchRpcMessage(Map<String, dynamic> msg) {
    final tag = msg['_tag'];
    if (tag == 'Ping') {
      _sendRpcJson(const <String, Object>{'_tag': 'Pong'});
      return;
    }
    if (tag == 'Pong') return;
    final reqId = msg['requestId']?.toString();
    if (reqId == null) return;

    if (tag == 'Chunk') {
      final handler = _streamHandlers[reqId];
      final values = msg['values'];
      if (handler != null && values is List) {
        for (final value in values) {
          handler(value);
        }
      }
      // Effect RpcServer requires an Ack to emit subsequent stream chunks.
      _sendRpcJson(<String, Object>{'_tag': 'Ack', 'requestId': reqId});
      return;
    }

    if (tag == 'Exit') {
      _streamHandlers.remove(reqId);
      final completer = _pendingUnary.remove(reqId);
      if (completer == null || completer.isCompleted) return;
      final exit = msg['exit'];
      if (exit is Map && exit['_tag'] == 'Success') {
        completer.complete(exit['value']);
      } else {
        completer.completeError(
          StateError('T3 RPC error: ${jsonEncode(exit)}'),
        );
      }
    }
  }

  void _sendRpcJson(Map<String, Object?> payload) {
    final socket = _rpcSocket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(payload));
  }

  String _sendStreamRequest(
    String tag,
    Map<String, Object?> payload,
    void Function(Object? value) onValue,
  ) {
    final id = 'denial-${_nextReqSeq++}';
    _streamHandlers[id] = onValue;
    _sendRpcJson(<String, Object?>{
      '_tag': 'Request',
      'id': id,
      'tag': tag,
      'payload': payload,
      'headers': const <Object>[],
    });
    return id;
  }

  Future<Object?> callRpc(
    String tag,
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!rpcConnected) {
      throw StateError('Not connected to T3 Code RPC.');
    }
    final id = 'denial-${_nextReqSeq++}';
    final completer = Completer<Object?>();
    _pendingUnary[id] = completer;
    _sendRpcJson(<String, Object?>{
      '_tag': 'Request',
      'id': id,
      'tag': tag,
      'payload': payload,
      'headers': const <Object>[],
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingUnary.remove(id);
        throw TimeoutException('T3 RPC $tag timed out');
      },
    );
  }

  /// Subscribes to real-time updates for a single thread (replacing any
  /// previous thread subscription).
  void subscribeThread(
    String? threadId,
    T3ThreadEventHandler onEvent,
  ) {
    if (_subscribedThreadId == threadId && _threadSubId != null) {
      return;
    }
    if (_threadSubId != null) {
      final oldId = _threadSubId!;
      _threadSubId = null;
      _subscribedThreadId = null;
      _streamHandlers.remove(oldId);
      _sendRpcJson(<String, Object>{
        '_tag': 'Interrupt',
        'requestId': oldId,
      });
    }
    if (threadId == null || !rpcConnected) return;
    _subscribedThreadId = threadId;
    _threadSubId = _sendStreamRequest(
      'orchestration.subscribeThread',
      <String, Object>{'threadId': threadId},
      (value) {
        if (value is Map<String, dynamic>) {
          onEvent(threadId, value);
        } else if (value is Map) {
          onEvent(threadId, Map<String, dynamic>.from(value));
        }
      },
    );
  }

  /// Fetches available harnesses (provider instances) and their models.
  Future<List<T3ProviderOption>> fetchProviders() async {
    final result = await callRpc('server.getConfig', const <String, Object>{});
    if (result is! Map) return const <T3ProviderOption>[];
    final providersRaw = result['providers'];
    if (providersRaw is! List) return const <T3ProviderOption>[];
    final parsed = <T3ProviderOption>[];
    for (final entry in providersRaw) {
      if (entry is! Map) continue;
      final instanceId = entry['instanceId']?.toString() ?? '';
      final driver = entry['driver']?.toString() ?? instanceId;
      if (instanceId.isEmpty) continue;
      final displayName =
          (entry['displayName']?.toString().trim().isNotEmpty ?? false)
          ? entry['displayName'].toString().trim()
          : instanceId;
      final enabled = entry['enabled'] != false;
      final status = entry['status']?.toString() ?? 'ready';
      final ready = status == 'ready' || status == 'warning';
      final models = <T3ModelOption>[];
      String? defaultModelFromList;
      final rawModels = entry['models'];
      if (rawModels is List) {
        for (final m in rawModels) {
          if (m is! Map) continue;
          final slug = m['slug']?.toString() ?? '';
          if (slug.isEmpty) continue;
          final name = (m['name']?.toString().trim().isNotEmpty ?? false)
              ? m['name'].toString().trim()
              : slug;
          if (m['isDefault'] == true && defaultModelFromList == null) {
            defaultModelFromList = slug;
          }
          models.add(T3ModelOption(slug: slug, name: name));
        }
      }
      final defaultModel =
          entry['defaultModel']?.toString() ?? defaultModelFromList;
      parsed.add(
        T3ProviderOption(
          instanceId: instanceId,
          driver: driver,
          displayName: displayName,
          enabled: enabled,
          ready: ready,
          models: models,
          defaultModel: defaultModel,
        ),
      );
    }
    return parsed;
  }

  /// Fetches a thread's detailed projection over HTTP as a fallback or
  /// immediate snapshot.
  Future<Map<String, dynamic>?> fetchThreadDetailHttp(
    T3InstallPaths paths,
    String threadId,
  ) async {
    try {
      return await _httpJson(
        'GET',
        '/api/orchestration/threads/${Uri.encodeComponent(threadId)}',
        paths: paths,
        extraHeaders: const <String, String>{
          'x-t3-orchestration-protocol': _protocolVersion,
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Ensures a T3 Code project exists for [workspaceRoot] (defaults to `~`),
  /// returning its `projectId`.
  Future<String> ensureProjectForWorkspace(
    T3InstallPaths paths,
    String workspaceRoot,
    List<T3ProjectInfo> knownProjects,
  ) async {
    final target = expandPath(workspaceRoot);
    for (final project in knownProjects) {
      if (project.workspaceRoot == target) return project.id;
    }
    // Check live project list via HTTP before creating.
    try {
      final snapshot = await _httpJson('GET', '/api/projects', paths: paths);
      final projects = snapshot['projects'];
      if (projects is List) {
        for (final p in projects) {
          if (p is Map && p['workspaceRoot']?.toString() == target) {
            final id = p['id']?.toString();
            if (id != null && id.isNotEmpty) return id;
          }
        }
      }
    } catch (_) {}

    final projectId = _newId('proj');
    final title = target == homeDir ? '~' : target.split('/').last;
    await _httpJson(
      'POST',
      '/api/projects/mutate',
      paths: paths,
      body: <String, Object>{
        'type': 'project.create',
        'commandId': _newId('cmd'),
        'projectId': projectId,
        'title': title.isEmpty ? 'Home' : title,
        'workspaceRoot': target,
      },
    );
    return projectId;
  }

  /// Launches a new T3 Code thread in [projectId] with bypass permissions
  /// (`full-access`) and dispatches [prompt].
  Future<String> launchThread({
    required String projectId,
    required String prompt,
    required String providerDriver,
    required String providerInstanceId,
    required String model,
  }) async {
    final trimmed = prompt.trim();
    final title = trimmed.length > 60
        ? '${trimmed.substring(0, 57).trim()}...'
        : trimmed;
    final result = await callRpc('orchestration.launchThread', <String, Object>{
      'commandId': _newId('cmd'),
      'projectId': projectId,
      'title': title.isEmpty ? 'Voice prompt' : title,
      'generateTitle': true,
      'modelSelection': <String, Object>{
        'provider': providerDriver,
        'instanceId': providerInstanceId,
        'model': model,
      },
      'runtimeMode': 'full-access',
      'interactionMode': 'default',
      'workspaceStrategy': const <String, Object>{'type': 'root'},
      'initialMessage': <String, Object>{
        'messageId': _newId('msg'),
        'text': trimmed,
        'attachments': const <Object>[],
      },
    });
    if (result is Map && result['threadId'] is String) {
      return result['threadId'] as String;
    }
    throw StateError('T3 launchThread returned unexpected response: $result');
  }

  /// Sends a follow-up user message to an existing thread.
  Future<void> sendMessageToThread({
    required String threadId,
    required String prompt,
  }) async {
    await callRpc('orchestration.dispatchCommand', <String, Object>{
      'type': 'message.dispatch',
      'commandId': _newId('cmd'),
      'threadId': threadId,
      'messageId': _newId('msg'),
      'text': prompt.trim(),
      'attachments': const <Object>[],
      'dispatchMode': const <String, Object>{'type': 'start_immediately'},
    });
  }

  /// Interrupts the active run on [threadId].
  Future<void> interruptRun({
    required String threadId,
    required String runId,
  }) async {
    await callRpc('orchestration.dispatchCommand', <String, Object>{
      'type': 'run.interrupt',
      'commandId': _newId('cmd'),
      'threadId': threadId,
      'runId': runId,
      'reason': 'Stopped from Denial Dynamic Island',
    });
  }

  /// Ensures T3 Code's selected local speech model is GigaAM (when downloaded).
  Future<void> ensureVoiceModelSelected(
    T3InstallPaths paths,
    String voiceModelId,
  ) async {
    if (voiceModelId.isEmpty) return;
    try {
      final status = await _httpJson('GET', '/api/voice/status', paths: paths);
      final selected =
          status['modelId']?.toString() ??
          status['selectedModelId']?.toString();
      if (selected == voiceModelId) return;
      final modelsRes = await _httpJson(
        'GET',
        '/api/voice/models',
        paths: paths,
      );
      final models = modelsRes['models'];
      if (models is List) {
        final hasInstalled = models.any(
          (m) =>
              m is Map &&
              m['id'] == voiceModelId &&
              (m['installed'] == true || m['state'] == 'installed'),
        );
        if (hasInstalled) {
          await _httpJson(
            'POST',
            '/api/voice/models/select',
            paths: paths,
            body: <String, Object>{'modelId': voiceModelId},
          );
        }
      }
    } catch (_) {}
  }

  /// Starts streaming microphone audio (`pw-record` f32le 16 kHz mono) to
  /// T3 Code's `/ws/voice` WebSocket for real-time GigaAM transcription.
  Future<void> startVoiceStream(
    T3InstallPaths paths, {
    required String voiceModelId,
    required void Function(String committed, String tentative) onTranscript,
    required void Function(double level) onLevel,
    required void Function(String message) onError,
  }) async {
    await cancelVoiceStream();
    await ensureVoiceModelSelected(paths, voiceModelId);

    final ticket = await _mintWsTicket(paths, 'media');
    final wsOrigin = _origin
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl =
        '$wsOrigin/ws/voice?ticket=${Uri.encodeQueryComponent(ticket)}';

    final readyCompleter = Completer<void>();
    _voiceReady = false;
    _pcmOverflow.clear();
    _pcmBackup.clear();
    _voiceFinishCompleter = Completer<String>();

    final socket = await WebSocket.connect(
      wsUrl,
    ).timeout(const Duration(seconds: 8));
    _voiceSocket = socket;

    _voiceSub = socket.listen(
      (dynamic raw) {
        if (raw is! String) return;
        Map<String, dynamic> event;
        try {
          event = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          return;
        }
        switch (event['type']) {
          case 'ready':
            _voiceReady = true;
            if (!readyCompleter.isCompleted) readyCompleter.complete();
          case 'update':
            final text = event['text'];
            if (text is Map) {
              onTranscript(
                text['committed']?.toString() ?? '',
                text['tentative']?.toString() ?? '',
              );
            }
          case 'finished':
            final text = event['text']?.toString() ?? '';
            if (_voiceFinishCompleter != null &&
                !_voiceFinishCompleter!.isCompleted) {
              _voiceFinishCompleter!.complete(text);
            }
          case 'error':
            final message =
                event['message']?.toString() ?? 'Voice transcription failed';
            if (!readyCompleter.isCompleted) {
              readyCompleter.completeError(StateError(message));
            }
            if (_voiceFinishCompleter != null &&
                !_voiceFinishCompleter!.isCompleted) {
              _voiceFinishCompleter!.completeError(StateError(message));
            }
            onError(message);
        }
      },
      onError: (Object err) {
        if (!readyCompleter.isCompleted) readyCompleter.completeError(err);
        if (_voiceFinishCompleter != null &&
            !_voiceFinishCompleter!.isCompleted) {
          _voiceFinishCompleter!.completeError(err);
        }
      },
      onDone: () {
        if (_voiceFinishCompleter != null &&
            !_voiceFinishCompleter!.isCompleted) {
          _voiceFinishCompleter!.complete('');
        }
      },
    );

    socket.add(
      jsonEncode(<String, Object>{
        'type': 'start',
        'options': _ruSpeechOptions,
      }),
    );

    await readyCompleter.future.timeout(const Duration(seconds: 15));

    // Spawn PipeWire microphone capture (16 kHz mono Float32 LE).
    Process proc;
    try {
      proc = await Process.start('pw-record', const <String>[
        '--format=f32',
        '--rate=$_speechSampleRate',
        '--channels=1',
        '-',
      ]);
    } catch (_) {
      proc = await Process.start('arecord', const <String>[
        '-q',
        '-f',
        'FLOAT_LE',
        '-r',
        '$_speechSampleRate',
        '-c',
        '1',
        '-t',
        'raw',
        '-',
      ]);
    }
    _recorderProcess = proc;

    _recorderSub = proc.stdout.listen((List<int> chunk) {
      if (chunk.isEmpty) return;
      _pcmOverflow.add(chunk);
      if (_pcmBackup.length < _speechSampleRate * 4 * 120) {
        _pcmBackup.add(chunk);
      }
      if (_pcmOverflow.length >= _speechChunkBytes) {
        final all = _pcmOverflow.takeBytes();
        final alignedLen = all.length - (all.length % 4);
        if (alignedLen > 0) {
          final frame = Uint8List.sublistView(all, 0, alignedLen);
          onLevel(_computeRmsLevel(frame));
          if (_voiceReady &&
              _voiceSocket != null &&
              _voiceSocket!.readyState == WebSocket.open) {
            _voiceSocket!.add(frame);
          }
        }
        if (alignedLen < all.length) {
          _pcmOverflow.add(Uint8List.sublistView(all, alignedLen));
        }
      }
    });
  }

  /// Stops recording, flushes remaining PCM to T3 Code, and returns the final
  /// GigaAM Russian transcription.
  Future<String> finishVoiceStream(T3InstallPaths paths) async {
    await _stopRecorderProcess();

    // Flush trailing aligned samples.
    final tail = _pcmOverflow.takeBytes();
    final alignedLen = tail.length - (tail.length % 4);
    if (alignedLen > 0 &&
        _voiceReady &&
        _voiceSocket != null &&
        _voiceSocket!.readyState == WebSocket.open) {
      _voiceSocket!.add(Uint8List.sublistView(tail, 0, alignedLen));
    }

    String transcript = '';
    try {
      if (_voiceSocket != null && _voiceSocket!.readyState == WebSocket.open) {
        _voiceSocket!.add(jsonEncode(const <String, Object>{'type': 'finish'}));
        transcript = await (_voiceFinishCompleter?.future ?? Future.value(''))
            .timeout(const Duration(seconds: 25));
      }
    } catch (_) {
      // Fallback to one-shot HTTP transcription if WS dropped mid-flight.
      transcript = await _transcribeFallbackHttp(paths);
    } finally {
      await _closeVoiceSocket();
      _pcmBackup.clear();
    }
    return transcript.trim();
  }

  Future<String> _transcribeFallbackHttp(T3InstallPaths paths) async {
    final pcm = _pcmBackup.takeBytes();
    final alignedLen = pcm.length - (pcm.length % 4);
    if (alignedLen < 1600) return '';
    try {
      final token = await ensureBearerToken(paths);
      final optionsBytes = utf8.encode(jsonEncode(_ruSpeechOptions));
      final body = Uint8List(4 + optionsBytes.length + alignedLen);
      ByteData.view(body.buffer).setUint32(0, optionsBytes.length, Endian.little);
      body.setRange(4, 4 + optionsBytes.length, optionsBytes);
      body.setRange(
        4 + optionsBytes.length,
        body.length,
        Uint8List.sublistView(pcm, 0, alignedLen),
      );
      final req = await _http.postUrl(Uri.parse('$_origin/api/voice/transcribe'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.contentType = ContentType.binary;
      req.headers.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decodeStream(res);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['text'] is String) {
          return (decoded['text'] as String).trim();
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> cancelVoiceStream() async {
    await _stopRecorderProcess();
    await _closeVoiceSocket();
    _pcmOverflow.clear();
    _pcmBackup.clear();
  }

  Future<void> _stopRecorderProcess() async {
    await _recorderSub?.cancel();
    _recorderSub = null;
    final proc = _recorderProcess;
    _recorderProcess = null;
    if (proc != null) {
      proc.kill(ProcessSignal.sigint);
      try {
        await proc.exitCode.timeout(const Duration(milliseconds: 500));
      } catch (_) {
        proc.kill(ProcessSignal.sigkill);
      }
    }
  }

  Future<void> _closeVoiceSocket() async {
    _voiceReady = false;
    await _voiceSub?.cancel();
    _voiceSub = null;
    final socket = _voiceSocket;
    _voiceSocket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _voiceFinishCompleter = null;
  }

  static double _computeRmsLevel(Uint8List f32Bytes) {
    final samples = f32Bytes.length ~/ 4;
    if (samples == 0) return 0;
    final data = ByteData.sublistView(f32Bytes);
    var sumSq = 0.0;
    // Sample every 4th value for negligible CPU cost.
    var count = 0;
    for (var i = 0; i < samples; i += 4) {
      final s = data.getFloat32(i * 4, Endian.little);
      if (s.isFinite) {
        sumSq += s * s;
        count++;
      }
    }
    if (count == 0) return 0;
    final rms = math.sqrt(sumSq / count);
    // Boost speech range (typical mic RMS 0.01..0.25) into 0.0..1.0.
    return (rms * 5.5).clamp(0.0, 1.0);
  }

  static String _newId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = math.Random.secure().nextInt(1 << 30).toRadixString(36);
    return '$prefix-$now-$rand';
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancelVoiceStream();
    await disconnectRpc();
    _http.close(force: true);
  }
}
