import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:automaa_mobile/mobile_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only HTTPS tailnet websocket endpoints are accepted', () {
    expect(validEndpoint(TestPeer.endpoint), isTrue);
    for (final value in [
      'ws://mac.example.ts.net:43827/mobile',
      'wss://mac.example.ts.net/mobile',
      'wss://mac.example.ts.net:443/mobile',
      'wss://mac.example.ts.net:43827/other',
      'wss://mac.example.ts.net:43827/mobile?q=x',
      'wss://mac.example.ts.net:43827/mobile#x',
      'wss://user@mac.example.ts.net:43827/mobile',
      'wss://mac.example.ts.net.evil.example:43827/mobile',
    ]) {
      expect(validEndpoint(value), isFalse, reason: value);
    }
  });

  test('a storage read failure blocks pairing and networking', () async {
    final store = MemoryMobileStore()..failRead = true;
    var connections = 0;
    final client = MobileClient(
      store: store,
      connector: (_) async {
        connections++;
        return TestSocket();
      },
    );
    addTearDown(client.dispose);
    await client.initialize();
    expect(client.storageFailed, isTrue);
    expect(client.canControl, isFalse);
    await expectLater(
      client.pair(TestPeer().pairingCode, 'Test phone'),
      throwsA(isA<MobileFailure>()),
    );
    expect(connections, 0);
  });

  test('an uncertain intent is persisted before a mutation is sent', () async {
    final fixture = await ClientFixture.connected();
    addTearDown(fixture.dispose);
    final started = Completer<void>();
    final release = Completer<void>();
    fixture.store.beforeWrite = (_) async {
      if (!started.isCompleted) started.complete();
      await release.future;
    };
    final command = fixture.client.command(
      'run',
      planID: TestPeer.planID,
      revision: 'revision-1',
    );
    await started.future;
    expect(fixture.peer.mutations, isEmpty);
    expect(fixture.client.uncertain, isTrue);
    fixture.store.beforeWrite = null;
    release.complete();
    await command;
    expect(fixture.peer.mutations, hasLength(1));
    final persisted = fixture.store.writes.map(
      (value) => jsonDecode(value) as Json,
    );
    expect(
      persisted.any(
        (value) => (value['hosts'] as List).first['pending'] != null,
      ),
      isTrue,
    );
    expect(fixture.client.uncertain, isFalse);
  });

  test('a failed intent write never sends a command', () async {
    final fixture = await ClientFixture.connected();
    addTearDown(fixture.dispose);
    fixture.store.failWrite = true;
    await fixture.client.command(
      'run',
      planID: TestPeer.planID,
      revision: 'revision-1',
    );
    expect(fixture.peer.mutations, isEmpty);
    expect(fixture.client.storageFailed, isTrue);
    expect(fixture.client.canControl, isFalse);
    expect(fixture.client.uncertain, isTrue);
  });

  test('a lost response survives restart and resolves without resending the mutation', () async {
    final fixture = await ClientFixture.connected();
    fixture.peer.holdMutations = true;
    await fixture.client.command(
      'run',
      planID: TestPeer.planID,
      revision: 'revision-1',
    );
    expect(fixture.client.uncertain, isTrue);
    expect(fixture.peer.mutations, hasLength(1));
    fixture.client.dispose();
    final restarted = MobileClient(
      store: fixture.store,
      connector: fixture.peer.connect,
      requestTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.online, isTrue);
    expect(restarted.uncertain, isFalse);
    expect(fixture.peer.mutations, hasLength(1));
    expect(
      fixture.peer.requests.where(
        (request) => request['operation'] == 'receipt',
      ),
      hasLength(1),
    );
  });

  test('known command rejection clears only that intent', () async {
    final fixture = await ClientFixture.connected();
    addTearDown(fixture.dispose);
    fixture.peer.rejectMutations = true;
    await fixture.client.command(
      'run',
      planID: TestPeer.planID,
      revision: 'revision-1',
    );
    expect(fixture.client.uncertain, isFalse);
    expect(fixture.client.notice, 'Test rejection');
    expect(fixture.client.canControl, isTrue);
  });

  test('a cached rejected receipt can resolve an uncertain command', () async {
    final fixture = await ClientFixture.connected();
    addTearDown(fixture.dispose);
    final pending = fixture.pending('old-rejection');
    fixture.client.activeHost!.pending = pending;
    fixture.peer.receipts['old-rejection'] = {
      'type': 'rejected',
      'message': 'Cached rejection',
    };
    await fixture.client.resolvePending();
    expect(fixture.client.uncertain, isFalse);
    expect(fixture.client.notice, 'Cached rejection');
  });

  test('a service session change preserves the uncertain operation for manual review', () async {
    final fixture = await ClientFixture.connected();
    addTearDown(fixture.dispose);
    fixture.client.activeHost!.pending = {
      ...fixture.pending('old-session'),
      'sessionID': 'previous-session',
    };
    await fixture.client.resolvePending();
    expect(fixture.client.uncertain, isTrue);
    expect(fixture.client.canControl, isFalse);
    expect(
      fixture.peer.requests.where(
        (request) => request['operation'] == 'receipt',
      ),
      isEmpty,
    );
  });

  test(
    're-pairing the same Mac does not erase an unresolved command',
    () async {
      final fixture = await ClientFixture.connected();
      addTearDown(fixture.dispose);
      fixture.client.activeHost!.pending = fixture.pending(
        'unresolved-before-pairing',
      );
      await fixture.client.pair(fixture.peer.pairingCode, 'Test phone');
      expect(
        fixture.client.activeHost!.pending?['id'],
        'unresolved-before-pairing',
      );
      expect(fixture.client.canControl, isFalse);
      final saved = jsonDecode(fixture.store.value!) as Json;
      expect(
        (saved['hosts'] as List).single['pending']['id'],
        'unresolved-before-pairing',
      );
    },
  );

  test('a late old receipt cannot erase a newer pending command', () async {
    final fixture = await ClientFixture.connected();
    addTearDown(fixture.dispose);
    fixture.client.activeHost!.pending = fixture.pending('old-command');
    fixture.peer.receipts['old-command'] = {
      'type': 'accepted',
      'message': 'Old command accepted',
    };
    fixture.peer.holdReceipts = true;
    final lookup = fixture.client.resolvePending();
    await flushEvents();
    expect(fixture.peer.delayedReceipts, hasLength(1));
    await fixture.client.acknowledgePending();
    fixture.peer.holdMutations = true;
    final nextCommand = fixture.client.command(
      'run',
      planID: TestPeer.planID,
      revision: 'revision-1',
    );
    await flushEvents();
    final nextID = fixture.client.activeHost!.pending?['id'];
    expect(nextID, isNotNull);
    expect(nextID, isNot('old-command'));
    fixture.peer.delayedReceipts.single();
    await lookup;
    expect(fixture.client.activeHost!.pending?['id'], nextID);
    fixture.peer.delayedMutations.single();
    await nextCommand;
  });

  test('pausing while pairing credentials are saved cannot revive a closed connection', () async {
    final store = MemoryMobileStore();
    final peer = TestPeer();
    final started = Completer<void>();
    final release = Completer<void>();
    store.beforeWrite = (_) async {
      started.complete();
      await release.future;
    };
    final client = MobileClient(store: store, connector: peer.connect);
    addTearDown(client.dispose);
    final pairing = client
        .pair(peer.pairingCode, 'Test phone')
        .catchError((Object _) {});
    await started.future;
    client.setPaused(true);
    release.complete();
    await pairing;
    expect(client.state, LinkState.disconnected);
    expect(client.online, isFalse);
    expect(client.canControl, isFalse);
  });

  test('an older connection cannot replace the selected Mac', () async {
    final store = MemoryMobileStore();
    final first = TestPeer();
    final second = TestPeer(hostID: TestPeer.otherHostID);
    final opening = Completer<WebSocket>();
    final client = MobileClient(
      store: store,
      connector: (uri) =>
          uri.host.startsWith('other-') ? second.connect(uri) : opening.future,
    );
    addTearDown(client.dispose);
    final firstHost = first.host;
    final secondHost = second.host;
    client.hosts.addAll([firstHost, secondHost]);
    final firstConnection = client.connect(firstHost);
    await flushEvents();
    await client.connect(secondHost);
    opening.complete(await first.connect(Uri.parse(firstHost.endpoint)));
    await firstConnection;
    expect(client.activeHost, same(secondHost));
    expect(client.snapshot?['hostID'], TestPeer.otherHostID);
    expect(client.online, isTrue);
    expect(first.requests, isEmpty);
  });

  test(
    'an old refresh failure cannot disconnect the newly selected Mac',
    () async {
      final first = TestPeer();
      final second = TestPeer(hostID: TestPeer.otherHostID);
      final client = MobileClient(
        store: MemoryMobileStore(),
        connector: (uri) => uri.host.startsWith('other-')
            ? second.connect(uri)
            : first.connect(uri),
      );
      addTearDown(client.dispose);
      final firstHost = first.host;
      final secondHost = second.host;
      client.hosts.addAll([firstHost, secondHost]);
      await client.connect(firstHost);
      first.holdSnapshots = true;
      final oldRefresh = client.refresh();
      await flushEvents();
      expect(first.delayedSnapshots, hasLength(1));
      final nextConnection = client.connect(secondHost);
      await oldRefresh;
      await nextConnection;
      expect(client.activeHost, same(secondHost));
      expect(client.snapshot?['hostID'], TestPeer.otherHostID);
      expect(client.online, isTrue);
      expect(client.state, LinkState.connected);
      first.delayedSnapshots.single();
      await flushEvents();
      expect(client.online, isTrue);
      expect(client.snapshot?['hostID'], TestPeer.otherHostID);
    },
  );

  test(
    'switching Macs retains each host unresolved intent separately',
    () async {
      final first = TestPeer();
      final second = TestPeer(hostID: TestPeer.otherHostID);
      final client = MobileClient(
        store: MemoryMobileStore(),
        connector: (uri) => uri.host.startsWith('other-')
            ? second.connect(uri)
            : first.connect(uri),
      );
      addTearDown(client.dispose);
      final firstHost = first.host;
      final secondHost = second.host;
      client.hosts.addAll([firstHost, secondHost]);
      await client.connect(firstHost);
      firstHost.pending = {
        'id': 'first-mac-command',
        'sessionID': 'previous-session',
        'operation': 'run',
      };
      await client.connect(secondHost);
      expect(client.uncertain, isFalse);
      expect(client.canControl, isTrue);
      expect(firstHost.pending?['id'], 'first-mac-command');
      await client.connect(firstHost);
      expect(client.uncertain, isTrue);
      expect(client.canControl, isFalse);
      expect(first.mutations, isEmpty);
      expect(second.mutations, isEmpty);
    },
  );

  test(
    'revoked authorization disables controls without automatic retries',
    () async {
      final peer = TestPeer()..unauthorized = true;
      final client = MobileClient(
        store: MemoryMobileStore(),
        connector: peer.connect,
      );
      addTearDown(client.dispose);
      final host = peer.host;
      client.hosts.add(host);
      await client.connect(host);
      expect(client.state, LinkState.unauthorized);
      expect(client.canControl, isFalse);
      expect(client.online, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(peer.requests, hasLength(1));
    },
  );
}

Future<void> flushEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

class MemoryMobileStore implements MobileStore {
  String? value;
  final List<String> writes = [];
  bool failRead = false;
  bool failWrite = false;
  Future<void> Function(String)? beforeWrite;
  @override
  Future<String?> read() async {
    if (failRead) throw const MobileFailure('Test storage failure');
    return value;
  }

  @override
  Future<void> write(String newValue) async {
    await beforeWrite?.call(newValue);
    if (failWrite) throw const MobileFailure('Test storage failure');
    value = newValue;
    writes.add(newValue);
  }
}

class ClientFixture {
  final MobileClient client;
  final MemoryMobileStore store;
  final TestPeer peer;
  ClientFixture(this.client, this.store, this.peer);
  static Future<ClientFixture> connected() async {
    final peer = TestPeer();
    final store = MemoryMobileStore();
    final client = MobileClient(
      store: store,
      connector: peer.connect,
      requestTimeout: const Duration(milliseconds: 150),
    );
    final host = peer.host;
    client.hosts.add(host);
    await client.connect(host);
    expect(client.online, isTrue);
    return ClientFixture(client, store, peer);
  }

  Json pending(String id) => {
    'version': 1,
    'id': id,
    'operation': 'run',
    'sessionID': TestPeer.sessionID,
    'planID': TestPeer.planID,
    'revision': 'revision-1',
  };
  void dispose() => client.dispose();
}

class TestPeer {
  static const defaultHostID = '00000000-0000-4000-8000-000000000001';
  static const otherHostID = '00000000-0000-4000-8000-000000000002';
  static const sessionID = '00000000-0000-4000-8000-000000000003';
  static const planID = '00000000-0000-4000-8000-000000000004';
  static const deviceID = '00000000-0000-4000-8000-000000000005';
  static const endpoint = 'wss://test-mac.example.ts.net:43827/mobile';
  static const secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  final String hostID;
  final requests = <Json>[];
  final receipts = <String, Json>{};
  final delayedReceipts = <void Function()>[];
  final delayedMutations = <void Function()>[];
  final delayedSnapshots = <void Function()>[];
  bool holdReceipts = false;
  bool holdMutations = false;
  bool holdSnapshots = false;
  bool rejectMutations = false;
  bool unauthorized = false;
  TestPeer({this.hostID = defaultHostID});
  List<Json> get mutations => requests
      .where((item) => ['run', 'stop'].contains(item['operation']))
      .toList();
  PairedHost get host => PairedHost(
    id: hostID,
    name: 'Test Mac',
    endpoint: hostID == defaultHostID
        ? endpoint
        : endpoint.replaceFirst('test-mac', 'other-mac'),
    deviceID: deviceID,
    secret: secret,
  );
  String get pairingCode => jsonEncode({
    'version': 1,
    'hostID': hostID,
    'hostName': 'Test Mac',
    'endpoint': host.endpoint,
    'secret': secret,
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  });
  Json get snapshot => {
    'hostID': hostID,
    'sessionID': sessionID,
    'revision': 'revision-1',
    'plans': <Json>[],
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Future<WebSocket> connect(Uri _) async {
    final socket = TestSocket();
    socket.onRequest = (request) {
      requests.add(request);
      void reply(String type, [Json fields = const {}]) => socket.deliver({
        'id': request['id'],
        'type': type,
        'snapshot': snapshot,
        ...fields,
      });
      switch (request['operation']) {
        case 'authenticate':
          reply(unauthorized ? 'unauthorized' : 'authenticated', {
            'message': 'Test authorization',
          });
        case 'pair':
          reply('paired', {'deviceID': deviceID, 'secret': secret});
        case 'run' || 'stop':
          final outcome = rejectMutations ? 'rejected' : 'accepted';
          final values = {
            'message': rejectMutations ? 'Test rejection' : 'Test accepted',
          };
          receipts[request['id']] = {'type': outcome, ...values};
          if (holdMutations) {
            delayedMutations.add(() => reply(outcome, values));
          } else {
            reply(outcome, values);
          }
        case 'receipt':
          void sendReceipt() {
            final receipt = receipts[request['commandID']];
            if (receipt == null) {
              reply('rejected', {'message': 'Receipt not found'});
            } else {
              reply('receipt', {
                'outcome': receipt['type'],
                'message': receipt['message'],
              });
            }
          }
          if (holdReceipts) {
            delayedReceipts.add(sendReceipt);
          } else {
            sendReceipt();
          }
        case 'snapshot':
          if (holdSnapshots) {
            delayedSnapshots.add(() => reply('snapshot'));
          } else {
            reply('snapshot');
          }
        default:
          reply('snapshot');
      }
    };
    return socket;
  }
}

class TestSocket extends Stream<dynamic> implements WebSocket {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  void Function(Json request)? onRequest;
  int _readyState = WebSocket.open;
  @override
  int get readyState => _readyState;
  void deliver(Json reply) {
    if (_readyState == WebSocket.open) _incoming.add(jsonEncode(reply));
  }

  @override
  void add(dynamic data) => onRequest?.call(jsonDecode(data as String) as Json);
  @override
  Future<void> close([int? code, String? reason]) async {
    _readyState = WebSocket.closed;
    await _incoming.close();
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
