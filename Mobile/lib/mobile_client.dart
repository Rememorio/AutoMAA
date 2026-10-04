import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
typedef MobileConnector = Future<WebSocket> Function(Uri endpoint);

abstract class MobileStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureMobileStore implements MobileStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  @override
  Future<String?> read() => _storage.read(key: 'automaa.hosts.v1');
  @override
  Future<void> write(String value) =>
      _storage.write(key: 'automaa.hosts.v1', value: value);
}

class MobileFailure implements Exception {
  final String message;
  const MobileFailure(this.message);
  @override
  String toString() => message;
}

class MobileRejection extends MobileFailure {
  const MobileRejection(super.message);
}

bool validEndpoint(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'wss' &&
      uri.host.endsWith('.ts.net') &&
      uri.host.split('.').length >= 4 &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.path == '/mobile' &&
      uri.hasPort &&
      uri.port >= 1024 &&
      uri.port <= 65535;
}

class PairedHost {
  final String id;
  final String name;
  final String endpoint;
  final String deviceID;
  final String secret;
  Json? pending;
  PairedHost({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.deviceID,
    required this.secret,
    this.pending,
  });
  factory PairedHost.fromJson(Json json) {
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['deviceID'] is! String ||
        json['secret'] is! String ||
        json['endpoint'] is! String ||
        !validEndpoint(json['endpoint'])) {
      throw const MobileFailure('已保存的设备信息无效，请检查安全存储');
    }
    return PairedHost(
      id: json['id'],
      name: json['name'],
      endpoint: json['endpoint'],
      deviceID: json['deviceID'],
      secret: json['secret'],
      pending: json['pending'] as Json?,
    );
  }
  Json toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'deviceID': deviceID,
    'secret': secret,
    if (pending != null) 'pending': pending,
  };
}

enum LinkState {
  disconnected,
  connecting,
  awaitingApproval,
  connected,
  unauthorized,
}

class MobileClient extends ChangeNotifier {
  final MobileStore store;
  final MobileConnector connector;
  final Duration requestTimeout;
  final Duration staleAfter;
  MobileClient({
    MobileStore? store,
    MobileConnector? connector,
    this.requestTimeout = const Duration(seconds: 12),
    this.staleAfter = const Duration(seconds: 12),
  }) : store = store ?? SecureMobileStore(),
       connector = connector ?? ((uri) => WebSocket.connect(uri.toString()));

  final List<PairedHost> hosts = [];
  PairedHost? activeHost;
  Json? snapshot;
  LinkState state = LinkState.disconnected;
  String? error;
  String? notice;
  bool initialized = false;
  bool storageFailed = false;
  bool sending = false;
  DateTime? lastReceived;
  bool _authenticated = false;
  bool _pairing = false;
  bool _paused = false;
  bool _disposed = false;
  int _generation = 0;
  int _retryCount = 0;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _watchdog;
  final Map<String, Completer<Json>> _requests = {};
  Future<void> _writes = Future.value();

  bool get online =>
      state == LinkState.connected &&
      _authenticated &&
      snapshot != null &&
      lastReceived != null &&
      DateTime.now().difference(lastReceived!) < staleAfter;
  bool get canControl =>
      online && !sending && activeHost?.pending == null && !storageFailed;
  List<Json> get plans => (snapshot?['plans'] as List? ?? []).cast<Json>();
  bool get uncertain => activeHost?.pending != null;

  Future<void> initialize() async {
    if (initialized) return;
    try {
      final raw = await store.read();
      if (raw != null) {
        final data = jsonDecode(raw) as Json;
        hosts.addAll(
          (data['hosts'] as List).map(
            (item) => PairedHost.fromJson(item as Json),
          ),
        );
        if (hosts.isNotEmpty) {
          activeHost = hosts.firstWhere(
            (host) => host.id == data['active'],
            orElse: () => hosts.first,
          );
        }
      }
    } catch (_) {
      storageFailed = true;
      error = '无法读取设备授权，请解锁手机后重新打开 App';
    }
    initialized = true;
    _notify();
    if (activeHost != null && !storageFailed) await connect(activeHost!);
  }

  Future<void> _save() {
    final value = jsonEncode({
      'hosts': hosts.map((host) => host.toJson()).toList(),
      'active': activeHost?.id,
    });
    final write = _writes.then((_) => store.write(value));
    _writes = write.catchError((_) {});
    return write.catchError((Object _) {
      storageFailed = true;
      error = '设备授权或操作记录未能安全保存，请重启 App 后检查';
      _notify();
      throw MobileFailure(error!);
    });
  }

  Future<void> connect(PairedHost host, {bool retry = false}) async {
    if (_disposed || _paused || storageFailed) return;
    if (!validEndpoint(host.endpoint)) {
      throw const MobileFailure('只允许连接 Tailscale 的安全地址');
    }
    final changed = activeHost?.id != host.id;
    _close();
    if (changed) {
      snapshot = null;
      lastReceived = null;
    }
    activeHost = host;
    if (!retry) _retryCount = 0;
    state = LinkState.connecting;
    error = null;
    _notify();
    final attempt = _generation;
    try {
      await _save();
      await _open(Uri.parse(host.endpoint), attempt);
      final reply = await request(
        'authenticate',
        fields: {'deviceID': host.deviceID, 'secret': host.secret},
      );
      if (attempt != _generation) return;
      if (reply['type'] != 'authenticated') {
        throw const MobileFailure('连接协议不兼容，请更新两端 AutoMAA');
      }
      _applySnapshot(reply['snapshot']);
      _authenticated = true;
      state = LinkState.connected;
      _retryCount = 0;
      error = null;
      _startWatchdog();
      _notify();
      if (host.pending != null) await resolvePending();
    } catch (failure) {
      if (attempt != _generation || _disposed) return;
      final unauthorized = state == LinkState.unauthorized;
      _close();
      state = unauthorized ? LinkState.unauthorized : LinkState.disconnected;
      error = failure is MobileFailure
          ? failure.message
          : '无法连接 Mac，请检查 Tailscale 和 Mac 上的 AutoMAA';
      _notify();
      if (!unauthorized) _scheduleReconnect();
    }
  }

  Future<void> pair(String text, String deviceName) async {
    if (storageFailed) throw const MobileFailure('安全存储不可用，请重启 App 后重试');
    Json code;
    try {
      code = jsonDecode(text.trim()) as Json;
    } catch (_) {
      throw const MobileFailure('配对信息格式不正确，请重新扫码或粘贴完整信息');
    }
    final name = deviceName.trim();
    if (name.isEmpty ||
        name.length > 60 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const MobileFailure('请输入 1 至 60 字的设备名称');
    }
    if (code['version'] != 1 ||
        code['endpoint'] is! String ||
        !validEndpoint(code['endpoint']) ||
        code['hostID'] is! String ||
        code['hostName'] is! String ||
        code['secret'] is! String ||
        (code['secret'] as String).length != 44) {
      throw const MobileFailure('配对信息无效或版本不兼容，请在 Mac 重新生成');
    }
    final expiry = DateTime.tryParse(code['expiresAt'] as String? ?? '');
    if (expiry == null || !expiry.isAfter(DateTime.now())) {
      throw const MobileFailure('配对信息已过期，请在 Mac 重新生成');
    }
    _close();
    snapshot = null;
    _pairing = true;
    lastReceived = null;
    state = LinkState.connecting;
    error = null;
    notice = null;
    _notify();
    final attempt = _generation;
    try {
      await _open(Uri.parse(code['endpoint']), attempt);
      state = LinkState.awaitingApproval;
      _notify();
      final reply = await request(
        'pair',
        fields: {'secret': code['secret'], 'deviceName': name},
        timeout: expiry.difference(DateTime.now()) + const Duration(seconds: 3),
      );
      if (attempt != _generation) throw const MobileFailure('配对已取消');
      if (reply['type'] != 'paired' ||
          reply['deviceID'] is! String ||
          reply['secret'] is! String) {
        throw const MobileFailure('配对未完成，请在 Mac 重新生成配对信息');
      }
      final host = PairedHost(
        id: code['hostID'],
        name: code['hostName'],
        endpoint: code['endpoint'],
        deviceID: reply['deviceID'],
        secret: reply['secret'],
        pending: hosts
            .where(
              (old) =>
                  old.id.toLowerCase() ==
                  (code['hostID'] as String).toLowerCase(),
            )
            .firstOrNull
            ?.pending,
      );
      hosts.removeWhere((old) => old.id.toLowerCase() == host.id.toLowerCase());
      hosts.add(host);
      activeHost = host;
      await _save();
      if (attempt != _generation ||
          _paused ||
          _disposed ||
          activeHost != host) {
        throw const MobileFailure('配对连接已变化，请重新连接设备');
      }
      _applySnapshot(reply['snapshot']);
      _authenticated = true;
      state = LinkState.connected;
      error = null;
      _retryCount = 0;
      _startWatchdog();
      _notify();
    } catch (failure) {
      if (attempt == _generation) {
        _close();
        state = LinkState.disconnected;
        error = failure is MobileFailure
            ? failure.message
            : '配对未完成，请检查连接并在 Mac 重新生成';
        _notify();
      }
      throw MobileFailure(error ?? '配对已取消');
    } finally {
      _pairing = false;
    }
  }

  Future<void> _open(Uri endpoint, int attempt) async {
    final opening = connector(endpoint).then((socket) {
      if (attempt != _generation || _disposed) {
        unawaited(socket.close());
        throw const MobileFailure('连接已取消');
      }
      return socket;
    });
    final socket = await opening.timeout(requestTimeout);
    if (attempt != _generation) {
      unawaited(socket.close());
      throw const MobileFailure('连接已取消');
    }
    _socket = socket;
    _subscription = socket.listen(
      (data) => _receive(data, attempt),
      onError: (Object _) => _lost(attempt),
      onDone: () => _lost(attempt),
    );
  }

  Future<Json> request(
    String operation, {
    Json fields = const {},
    Duration? timeout,
  }) async {
    final socket = _socket;
    if (socket == null) throw const MobileFailure('连接已断开，请重新连接');
    final id = const Uuid().v4();
    final request = <String, dynamic>{
      'version': 1,
      'id': id,
      'operation': operation,
      ...fields,
    };
    return _send(request, timeout: timeout);
  }

  Future<Json> _send(Json request, {Duration? timeout}) async {
    final socket = _socket;
    if (socket == null) throw const MobileFailure('连接已断开，请重新连接');
    final id = request['id'] as String;
    final completer = Completer<Json>();
    _requests[id.toLowerCase()] = completer;
    try {
      socket.add(jsonEncode(request));
      return await completer.future.timeout(timeout ?? requestTimeout);
    } finally {
      _requests.remove(id.toLowerCase());
    }
  }

  void _receive(dynamic raw, int attempt) {
    if (attempt != _generation) return;
    try {
      if (raw is! String || raw.length > 1048576) throw const FormatException();
      final reply = jsonDecode(raw) as Json;
      if (_authenticated && reply['snapshot'] != null) {
        _applySnapshot(reply['snapshot']);
        _notify();
      }
      final id = (reply['id'] as String?)?.toLowerCase();
      final completer = _requests[id];
      if (completer == null ||
          completer.isCompleted ||
          reply['type'] == 'approval') {
        return;
      }
      if (reply['type'] == 'unauthorized') {
        state = LinkState.unauthorized;
      }
      if (reply['type'] == 'rejected' || reply['type'] == 'unauthorized') {
        completer.completeError(
          MobileRejection(reply['message'] as String? ?? '操作未接受，请刷新状态'),
        );
      } else {
        completer.complete(reply);
      }
    } catch (_) {
      _lost(attempt);
    }
  }

  void _applySnapshot(dynamic value) {
    final data = value as Json;
    if (data['hostID'] is! String ||
        data['sessionID'] is! String ||
        data['revision'] is! String ||
        data['plans'] is! List ||
        (activeHost != null &&
            (data['hostID'] as String).toLowerCase() !=
                activeHost!.id.toLowerCase())) {
      throw const FormatException();
    }
    snapshot = data;
    lastReceived = DateTime.now();
  }

  Future<void> refresh() async {
    if (!online) {
      if (activeHost != null) await connect(activeHost!);
      return;
    }
    final attempt = _generation;
    try {
      await request('snapshot');
    } catch (_) {
      _lost(attempt);
    }
  }

  Future<void> command(
    String operation, {
    String? planID,
    String? revision,
    Json? run,
  }) async {
    if (!canControl) throw const MobileFailure('请等待连接恢复或确认上次操作结果');
    if (operation != 'run' && operation != 'stop') {
      throw const MobileFailure('不支持此操作');
    }
    final host = activeHost!;
    final attempt = _generation;
    final request = <String, dynamic>{
      'version': 1,
      'id': const Uuid().v4(),
      'operation': operation,
      'sessionID': snapshot!['sessionID'],
      'planID': ?planID,
      'revision': ?revision,
      'run': ?run,
    };
    sending = true;
    notice = null;
    host.pending = request;
    _notify();
    try {
      // Record the intent before sending so an app kill cannot erase an uncertain operation.
      await _save();
      if (attempt != _generation || activeHost != host) {
        throw const MobileFailure('连接已变化，操作结果待确认');
      }
      final reply = await _send(request);
      if (reply['type'] != 'accepted') {
        throw const MobileFailure('操作回执无效，请检查活动记录');
      }
      host.pending = null;
      await _save();
      notice = reply['message'] as String? ?? '请求已接受';
    } on MobileRejection catch (failure) {
      host.pending = null;
      await _save();
      notice = failure.message;
    } on MobileFailure catch (failure) {
      notice = failure.message;
    } catch (_) {
      notice = '操作结果待确认，请检查当前状态和活动记录，不要重复启动';
    } finally {
      sending = false;
      _notify();
    }
  }

  Future<void> resolvePending() async {
    final host = activeHost;
    final pending = host?.pending;
    final attempt = _generation;
    if (!online || host == null || pending == null) return;
    if (pending['sessionID'] != snapshot?['sessionID']) {
      notice = 'Mac 服务已重启，上次操作结果待确认。请检查活动记录。';
      _notify();
      return;
    }
    try {
      final reply = await request(
        'receipt',
        fields: {'sessionID': pending['sessionID'], 'commandID': pending['id']},
      );
      if (attempt != _generation ||
          activeHost != host ||
          host.pending != pending) {
        return;
      }
      if (reply['type'] != 'receipt' ||
          !['accepted', 'rejected'].contains(reply['outcome'])) {
        throw const MobileFailure('操作回执无效，请检查活动记录');
      }
      host.pending = null;
      await _save();
      if (attempt == _generation && activeHost == host) {
        notice = reply['message'] as String? ?? '已查到操作回执';
      }
    } catch (_) {
      if (attempt == _generation && activeHost == host) {
        notice = '未能确认上次操作结果，请检查当前状态和活动记录';
      }
    }
    _notify();
  }

  Future<void> acknowledgePending() async {
    if (!online || sending) return;
    activeHost?.pending = null;
    await _save();
    notice = null;
    _notify();
  }

  Future<void> forget(PairedHost host) async {
    if (sending) throw const MobileFailure('请先等待操作请求完成');
    hosts.removeWhere((item) => item.id == host.id);
    if (activeHost?.id == host.id) {
      _close();
      activeHost = null;
      snapshot = null;
      lastReceived = null;
      state = LinkState.disconnected;
      error = null;
      notice = null;
    }
    await _save();
    _notify();
  }

  void cancelPairing() {
    if (state != LinkState.awaitingApproval && state != LinkState.connecting) {
      return;
    }
    _close();
    state = LinkState.disconnected;
    _notify();
  }

  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      _close();
      state = LinkState.disconnected;
      _notify();
    } else if (activeHost != null) {
      unawaited(connect(activeHost!));
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (lastReceived != null &&
          DateTime.now().difference(lastReceived!) >= staleAfter) {
        _lost(_generation);
      }
    });
  }

  void _lost(int attempt) {
    if (attempt != _generation || _disposed) return;
    final unauthorized = state == LinkState.unauthorized;
    _close();
    state = unauthorized ? LinkState.unauthorized : LinkState.disconnected;
    error = unauthorized ? '授权已失效，请在 Mac 重新配对' : '连接已断开。Mac 上的任务不会因此停止。';
    _notify();
    if (!unauthorized) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_paused ||
        _disposed ||
        _pairing ||
        activeHost == null ||
        storageFailed ||
        _retryCount >= 5) {
      return;
    }
    final delay = Duration(seconds: 1 << _retryCount++);
    _retry = Timer(delay, () {
      if (activeHost != null) unawaited(connect(activeHost!, retry: true));
    });
  }

  void _close() {
    _generation++;
    _authenticated = false;
    _retry?.cancel();
    _watchdog?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.close());
    _socket = null;
    for (final pending in _requests.values) {
      if (!pending.isCompleted) {
        pending.completeError(const MobileFailure('连接已断开，操作结果待确认'));
      }
    }
    _requests.clear();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _close();
    super.dispose();
  }
}
