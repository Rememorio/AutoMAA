import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Invoked by MobileInteropTests against an isolated, loopback-only Swift fixture.
Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (var index = 0; index + 1 < arguments.length; index += 2) {
    options[arguments[index]] = arguments[index + 1];
  }
  ProtocolPeer? peer;
  try {
    final port = int.parse(options['--port']!);
    check(port > 0 && port <= 65535, 'invalid loopback port');
    final invitation =
        jsonDecode(await File(options['--invitation']!).readAsString()) as Json;
    check(invitation['version'] == 1, 'pairing version');
    check(
      (invitation['endpoint'] as String).startsWith('wss://'),
      'secure advertised endpoint',
    );
    check(
      DateTime.parse(invitation['expiresAt'] as String).isAfter(DateTime.now()),
      'pairing expiry',
    );
    check(
      base64Decode(invitation['secret'] as String).length == 32,
      'pairing entropy',
    );
    peer = await ProtocolPeer.connect(port);
    check(
      (await peer.request('snapshot'))['type'] == 'unauthorized',
      'unauthorized snapshot',
    );
    final paired = await peer.request('pair', {
      'secret': invitation['secret'],
      'deviceName': '测试手机 Interop',
    });
    check(paired['type'] == 'paired', 'pairing result');
    check(peer.approvals == 1, 'approval precedes paired result');
    check(
      base64Decode(paired['secret'] as String).length == 32,
      'credential entropy',
    );
    check(paired['secret'] != invitation['secret'], 'distinct credential');
    validateSnapshot(
      paired['snapshot'] as Json,
      invitation['hostID'] as String,
    );
    final replayedPairing = await peer.request('pair', {
      'secret': invitation['secret'],
      'deviceName': '测试手机 Interop',
    });
    check(replayedPairing['type'] == 'rejected', 'single-use pairing');
    await peer.close();

    peer = await ProtocolPeer.connect(port);
    final authenticated = await peer.request('authenticate', {
      'deviceID': (paired['deviceID'] as String).toLowerCase(),
      'secret': paired['secret'],
    });
    check(authenticated['type'] == 'authenticated', 'reconnect authentication');
    final snapshotReply = await peer.request('snapshot');
    check(snapshotReply['type'] == 'snapshot', 'snapshot operation');
    final snapshot = snapshotReply['snapshot'] as Json;
    validateSnapshot(snapshot, invitation['hostID'] as String);
    final session = (snapshot['sessionID'] as String).toLowerCase();
    final plan = (snapshot['plans'] as List).single as Json;
    final command = <String, dynamic>{
      'version': 1,
      'id': newUUID(),
      'operation': 'run',
      'sessionID': session,
      'planID': (plan['id'] as String).toLowerCase(),
      'revision': snapshot['revision'],
    };
    final accepted = await peer.send(command);
    check(accepted['type'] == 'accepted', 'run acceptance');
    check((accepted['snapshot'] as Json)['busy'] == true, 'run state');
    final duplicate = await peer.send(command);
    check(duplicate['type'] == 'accepted', 'duplicate receipt');
    check(
      duplicate['message'] == accepted['message'],
      'duplicate original result',
    );
    final conflict = await peer.send({
      ...command,
      'revision': 'changed-revision',
    });
    check(conflict['type'] == 'rejected', 'same-id changed-payload rejection');
    final receipt = await peer.request('receipt', {
      'sessionID': session,
      'commandID': command['id'],
    });
    check(
      receipt['type'] == 'receipt' && receipt['outcome'] == 'accepted',
      'accepted receipt envelope',
    );
    final history = await peer.request('history');
    check(history['type'] == 'history', 'history operation');
    final record = (history['history'] as List).single as Json;
    check(
      DateTime.parse(record['startedAt'] as String).isUtc,
      'history ISO date',
    );
    final detail = await peer.request('historyDetails', {
      'historyID': record['id'],
    });
    check(detail['type'] == 'historyDetails', 'historyDetails operation');
    final event = (detail['events'] as List).single as Json;
    check(
      (event['message'] as String).contains('[已隐藏]'),
      'redacted unicode log',
    );
    check(
      !(event['message'] as String).contains('interop-sensitive'),
      'log secret absent',
    );
    check(DateTime.parse(event['timestamp'] as String).isUtc, 'event ISO date');

    final identity = (accepted['snapshot'] as Json)['run'] as Json;
    final badStop = <String, dynamic>{
      'version': 1,
      'id': newUUID(),
      'operation': 'stop',
      'sessionID': session,
      'run': {...identity, 'lockID': newUUID()},
    };
    check(
      (await peer.send(badStop))['type'] == 'rejected',
      'wrong run identity',
    );
    final rejectedReceipt = await peer.request('receipt', {
      'sessionID': session,
      'commandID': badStop['id'],
    });
    check(
      rejectedReceipt['type'] == 'receipt' &&
          rejectedReceipt['outcome'] == 'rejected',
      'rejected receipt envelope',
    );
    final stop = <String, dynamic>{
      'version': 1,
      'id': newUUID(),
      'operation': 'stop',
      'sessionID': session,
      'run': identity.map(
        (key, value) => MapEntry(key, (value as String).toLowerCase()),
      ),
    };
    final stopped = await peer.send(stop);
    check(stopped['type'] == 'accepted', 'exact run identity stop');
    check((stopped['snapshot'] as Json)['busy'] == false, 'stopped snapshot');
    check((await peer.send(stop))['type'] == 'accepted', 'stop deduplication');
    final stopReceipt = await peer.request('receipt', {
      'sessionID': session,
      'commandID': stop['id'],
    });
    check(stopReceipt['outcome'] == 'accepted', 'stop receipt');

    await File(options['--revoke']!).writeAsString('', flush: true);
    await peer.closed.future.timeout(const Duration(seconds: 5));
    final revokedFile = File(options['--revoked']!);
    for (var index = 0; index < 100 && !await revokedFile.exists(); index++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    check(await revokedFile.exists(), 'Mac revocation signal');
    await peer.close();
    peer = await ProtocolPeer.connect(port);
    final revoked = await peer.request('authenticate', {
      'deviceID': paired['deviceID'],
      'secret': paired['secret'],
    });
    check(revoked['type'] == 'unauthorized', 'revoked credential rejection');
    check(
      (await peer.request('snapshot'))['type'] == 'unauthorized',
      'revoked device cannot read',
    );
    stdout.writeln(
      'AUTOMAA_INTEROP_OK pair auth snapshot run-dedup receipt history stop-dedup revoke',
    );
  } catch (error) {
    stderr.writeln('AUTOMAA_INTEROP_FAILED ${error.runtimeType}: $error');
    exitCode = 1;
  } finally {
    await peer?.close();
  }
}

typedef Json = Map<String, dynamic>;

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void validateSnapshot(Json snapshot, String hostID) {
  check(
    (snapshot['hostID'] as String).toLowerCase() == hostID.toLowerCase(),
    'stable host UUID',
  );
  check(
    RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(snapshot['sessionID'] as String),
    'session UUID',
  );
  check(
    DateTime.parse(snapshot['updatedAt'] as String).isUtc,
    'snapshot ISO date',
  );
  check(snapshot['hostName'] == '协议测试 Mac', 'Unicode host name');
  check(
    snapshot['busy'] is bool && snapshot['progress'] is num,
    'typed state fields',
  );
  check((snapshot['plans'] as List).length == 1, 'plan array');
}

String newUUID() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ProtocolPeer {
  final WebSocket socket;
  final pending = <String, Completer<Json>>{};
  final closed = Completer<void>();
  late final StreamSubscription<dynamic> subscription;
  int approvals = 0;

  ProtocolPeer(this.socket) {
    subscription = socket.listen(
      (dynamic message) {
        try {
          final reply = jsonDecode(message as String) as Json;
          if (reply['type'] == 'approval') {
            approvals++;
            return;
          }
          final id = (reply['id'] as String?)?.toLowerCase();
          final completer = pending[id];
          if (completer != null && !completer.isCompleted) {
            completer.complete(reply);
          }
        } catch (error) {
          finish(error);
        }
      },
      onDone: () => finish(StateError('Connection closed')),
      onError: finish,
    );
  }

  static Future<ProtocolPeer> connect(int port) async => ProtocolPeer(
    await WebSocket.connect('ws://127.0.0.1:$port/mobile')
        .timeout(const Duration(seconds: 5)),
  );

  Future<Json> request(String operation, [Json fields = const {}]) =>
      send({'version': 1, 'id': newUUID(), 'operation': operation, ...fields});

  Future<Json> send(Json request) async {
    final id = (request['id'] as String).toLowerCase();
    final completer = Completer<Json>();
    pending[id] = completer;
    try {
      socket.add(jsonEncode(request));
      final reply = await completer.future.timeout(const Duration(seconds: 5));
      check(
        (reply['id'] as String).toLowerCase() == id,
        'reply UUID correlation',
      );
      return reply;
    } finally {
      pending.remove(id);
    }
  }

  void finish(Object error) {
    if (!closed.isCompleted) closed.complete();
    for (final completer in pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  Future<void> close() async {
    await socket.close().timeout(const Duration(seconds: 2), onTimeout: () {});
    await subscription.cancel();
  }
}
