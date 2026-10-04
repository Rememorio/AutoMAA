import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A loopback-only protocol fixture. It never launches a process or reads user data.
class FakeMacServer {
  static const hostID = '00000000-0000-4000-8000-000000000001';
  static const sessionID = '00000000-0000-4000-8000-000000000002';
  static const planID = '00000000-0000-4000-8000-000000000003';
  static const deviceID = '00000000-0000-4000-8000-000000000004';
  static const runID = '00000000-0000-4000-8000-000000000005';
  static const lockID = '00000000-0000-4000-8000-000000000006';
  static const pairingSecret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  static const deviceSecret = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';
  static const endpoint = 'wss://qa-mac.example.ts.net:43827/mobile';

  late final HttpServer _server;
  Timer? _heartbeat;
  final _sockets = <WebSocket>{};
  final _authorized = <WebSocket>{};
  final _pendingPairing = <WebSocket, String>{};
  final _receipts = <String, Map<String, dynamic>>{};
  final requests = <Map<String, dynamic>>[];
  bool running = false;
  bool revoked = false;
  bool autoApprove = true;
  bool dropNextMutationReply = false;
  bool rejectNextRun = false;
  bool pushSnapshots = true;
  String planName = '日常方案';
  int runCount = 0;
  int stopCount = 0;

  String get pairingCode => jsonEncode({
    'version': 1,
    'hostID': hostID,
    'hostName': 'QA Mac',
    'endpoint': endpoint,
    'secret': pairingSecret,
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  });

  Map<String, dynamic> get snapshot => {
    'hostID': hostID,
    'sessionID': sessionID,
    'hostName': 'QA Mac',
    'appVersion': '0.0.0-qa',
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'revision': 'qa-revision-1',
    'busy': running,
    'stopping': false,
    if (running) 'run': {'runID': runID, 'planID': planID, 'lockID': lockID},
    'phase': running ? '执行任务' : '空闲',
    'message': running ? '日常方案 · 测试账号 · 基建换班' : '等待运行',
    'progress': running ? 0.4 : 0.0,
    'canStop': running,
    'plans': [
      {
        'id': planID,
        'name': planName,
        'accounts': ['测试客户端 / 测试账号'],
        'tasks': ['基建换班', '收取奖励'],
        'parameters': ['不使用理智药', '不使用源石'],
        'schedule': '未设置定时',
        'action': '运行方案',
        'canRun': !running,
        'pending': ['测试账号 · 基建换班', '测试账号 · 收取奖励'],
        'warnings': <String>[],
      },
    ],
  };

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      if (pushSnapshots) broadcast();
    });
    _server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen(
        (data) => _receive(
          socket,
          jsonDecode(data as String) as Map<String, dynamic>,
        ),
        onDone: () {
          _sockets.remove(socket);
          _authorized.remove(socket);
        },
        onError: (Object _) {},
      );
    });
  }

  Future<WebSocket> connect(Uri _) =>
      WebSocket.connect('ws://127.0.0.1:${_server.port}/mobile');

  void broadcast() {
    for (final socket in _authorized) {
      _send(socket, {'type': 'snapshot', 'snapshot': snapshot});
    }
  }

  void approvePendingPairing() {
    for (final entry in _pendingPairing.entries) {
      _authorized.add(entry.key);
      _send(entry.key, {
        'id': entry.value,
        'type': 'paired',
        'deviceID': deviceID,
        'secret': deviceSecret,
        'snapshot': snapshot,
      });
    }
    _pendingPairing.clear();
  }

  Future<void> disconnect() async {
    for (final socket in _sockets.toList()) {
      await socket.close();
    }
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await disconnect();
    await _server.close(force: true);
  }

  void _send(WebSocket socket, Map<String, dynamic> reply) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(reply));
  }

  void _receive(WebSocket socket, Map<String, dynamic> request) {
    requests.add(request);
    final id = request['id'] as String;
    final operation = request['operation'] as String;
    void reply(String type, [Map<String, dynamic> values = const {}]) =>
        _send(socket, {'id': id, 'type': type, ...values});

    if (operation == 'pair') {
      if (request['secret'] != pairingSecret) {
        reply('unauthorized', {'message': '配对信息已过期或无效'});
      } else {
        reply('approval', {'message': '请在 Mac 上确认授权'});
        if (autoApprove) {
          _authorized.add(socket);
          reply('paired', {
            'deviceID': deviceID,
            'secret': deviceSecret,
            'snapshot': snapshot,
          });
        } else {
          _pendingPairing[socket] = id;
        }
      }
      return;
    }
    if (operation == 'authenticate') {
      if (revoked ||
          request['deviceID'] != deviceID ||
          request['secret'] != deviceSecret) {
        reply('unauthorized', {'message': '设备授权已撤销，请重新配对'});
      } else {
        _authorized.add(socket);
        reply('authenticated', {'snapshot': snapshot});
      }
      return;
    }
    if (!_authorized.contains(socket) || revoked) {
      reply('unauthorized', {'message': '设备未授权，请重新配对'});
      return;
    }
    switch (operation) {
      case 'snapshot':
        reply('snapshot', {'snapshot': snapshot});
      case 'history':
        reply('history', {
          'history': [
            {
              'id': request['before'] == null ? runID : lockID,
              'title': request['before'] == null ? '日常方案' : '维护检查',
              'startedAt': '2026-10-02T12:00:00Z',
              'status': request['before'] == null ? '已完成' : '执行失败',
              'hasAttention': request['before'] != null,
              'failed': request['before'] != null,
            },
          ],
          if (request['before'] == null) 'next': 'qa-page-2',
        });
      case 'historyDetails':
        reply('historyDetails', {
          'events': [
            {
              'id': lockID,
              'timestamp': '2026-10-02T12:02:00Z',
              'level': 'info',
              'message': request['before'] == null ? '基建换班已完成' : '任务准备完成',
              'details': '测试账号 · 连接已清理',
            },
          ],
          if (request['before'] == null) 'next': 'qa-log-2',
        });
      case 'run' || 'stop':
        if (_receipts.containsKey(id)) {
          _send(socket, {..._receipts[id]!, 'snapshot': snapshot});
          return;
        }
        if (request['sessionID'] != sessionID ||
            (operation == 'run' &&
                (request['revision'] != 'qa-revision-1' ||
                    running ||
                    rejectNextRun))) {
          rejectNextRun = false;
          reply('rejected', {
            'message': '方案状态已变化，请刷新后重试',
            'snapshot': snapshot,
          });
          return;
        }
        if (operation == 'run') {
          running = true;
          runCount++;
        } else {
          running = false;
          stopCount++;
        }
        final receipt = <String, dynamic>{
          'id': id,
          'type': 'accepted',
          'message': operation == 'run' ? '已开始运行' : '已请求安全停止',
        };
        _receipts[id] = receipt;
        if (dropNextMutationReply) {
          dropNextMutationReply = false;
          unawaited(socket.close());
        } else {
          _send(socket, {...receipt, 'snapshot': snapshot});
        }
      case 'receipt':
        final receipt = _receipts[request['commandID']];
        if (receipt == null) {
          reply('rejected', {'message': '未找到操作回执，请检查当前状态'});
        } else {
          _send(socket, {
            ...receipt,
            'id': id,
            'type': 'receipt',
            'outcome': receipt['type'],
            'snapshot': snapshot,
          });
        }
      default:
        reply('rejected', {'message': '不支持此操作'});
    }
  }
}
