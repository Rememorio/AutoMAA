import 'dart:async';
import 'dart:convert';

import 'package:automaa_mobile/mobile_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_mac_server.dart';

class MemoryMobileStore implements MobileStore {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('Simulated locked secure storage');
    this.value = value;
  }
}

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('QA state did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS native secure storage round-trips isolated QA credentials', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = SecureMobileStore();
      final value = jsonEncode({
        'hosts': [
          {'id': FakeMacServer.hostID, 'secret': FakeMacServer.deviceSecret},
        ],
      });
      try {
        await store.write(value);
        expect(await store.read(), value);
      } finally {
        await store.write(jsonEncode({'hosts': <Json>[], 'active': null}));
      }
    });
  });

  testWidgets('pair, read history, run and safely stop over a real socket', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = FakeMacServer();
      final store = MemoryMobileStore();
      await server.start();
      final client = MobileClient(store: store, connector: server.connect);
      try {
        await client.initialize();
        expect(client.canControl, isFalse);
        await client.pair(server.pairingCode, 'QA iPhone');
        expect(client.online, isTrue);
        expect(client.canControl, isTrue);
        final saved = jsonDecode(store.value!) as Json;
        expect((saved['hosts'] as List).length, 1);

        final history = await client.request('history');
        expect((history['history'] as List).single['title'], '日常方案');
        final details = await client.request(
          'historyDetails',
          fields: {'historyID': FakeMacServer.runID},
        );
        expect((details['events'] as List).single['message'], '基建换班已完成');

        await client.command(
          'run',
          planID: FakeMacServer.planID,
          revision: client.snapshot!['revision'],
        );
        expect(server.runCount, 1);
        expect(client.snapshot!['busy'], isTrue);
        expect(client.uncertain, isFalse);
        await client.command('stop', run: client.snapshot!['run'] as Json);
        expect(server.stopCount, 1);
        expect(client.snapshot!['busy'], isFalse);
        expect(client.uncertain, isFalse);
      } finally {
        client.dispose();
        await server.close();
      }
    });
  });

  testWidgets(
    'lost mutation reply reconnects and queries receipt without replay',
    (tester) async {
      await tester.runAsync(() async {
        final server = FakeMacServer();
        await server.start();
        final client = MobileClient(
          store: MemoryMobileStore(),
          connector: server.connect,
        );
        try {
          await client.initialize();
          await client.pair(server.pairingCode, 'QA iPhone');
          server.dropNextMutationReply = true;
          await client.command(
            'run',
            planID: FakeMacServer.planID,
            revision: client.snapshot!['revision'],
          );
          expect(client.uncertain, isTrue);
          expect(client.canControl, isFalse);
          await waitFor(() => client.online && !client.uncertain);
          expect(server.runCount, 1);
          expect(
            server.requests.where((request) => request['operation'] == 'run'),
            hasLength(1),
          );
          expect(
            server.requests.where(
              (request) => request['operation'] == 'receipt',
            ),
            hasLength(1),
          );
          expect(client.snapshot!['busy'], isTrue);
        } finally {
          client.dispose();
          await server.close();
        }
      });
    },
  );

  testWidgets('revoked authorization stops reconnect and cannot control', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = FakeMacServer();
      await server.start();
      final client = MobileClient(
        store: MemoryMobileStore(),
        connector: server.connect,
      );
      try {
        await client.initialize();
        await client.pair(server.pairingCode, 'QA iPhone');
        server.revoked = true;
        await client.connect(client.activeHost!);
        expect(client.state, LinkState.unauthorized);
        expect(client.canControl, isFalse);
        await expectLater(
          client.command('run', planID: FakeMacServer.planID),
          throwsA(isA<MobileFailure>()),
        );
        expect(server.runCount, 0);
      } finally {
        client.dispose();
        await server.close();
      }
    });
  });

  testWidgets(
    'secure storage failure prevents mutation from being dispatched',
    (tester) async {
      await tester.runAsync(() async {
        final server = FakeMacServer();
        final store = MemoryMobileStore();
        await server.start();
        final client = MobileClient(store: store, connector: server.connect);
        try {
          await client.initialize();
          await client.pair(server.pairingCode, 'QA iPhone');
          store.failWrites = true;
          await client.command(
            'run',
            planID: FakeMacServer.planID,
            revision: client.snapshot!['revision'],
          );
          expect(client.storageFailed, isTrue);
          expect(client.canControl, isFalse);
          expect(server.runCount, 0);
          expect(
            server.requests.where((request) => request['operation'] == 'run'),
            isEmpty,
          );
        } finally {
          client.dispose();
          await server.close();
        }
      });
    },
  );

  testWidgets(
    'pending intent survives an app restart and only queries receipt',
    (tester) async {
      await tester.runAsync(() async {
        final server = FakeMacServer();
        final store = MemoryMobileStore();
        await server.start();
        var client = MobileClient(store: store, connector: server.connect);
        try {
          await client.initialize();
          await client.pair(server.pairingCode, 'QA iPhone');
          server.dropNextMutationReply = true;
          await client.command(
            'run',
            planID: FakeMacServer.planID,
            revision: client.snapshot!['revision'],
          );
          expect(client.uncertain, isTrue);
          client.dispose();
          client = MobileClient(store: store, connector: server.connect);
          await client.initialize();
          expect(client.online, isTrue);
          expect(client.uncertain, isFalse);
          expect(client.snapshot!['busy'], isTrue);
          expect(server.runCount, 1);
          expect(
            server.requests.where((request) => request['operation'] == 'run'),
            hasLength(1),
          );
        } finally {
          client.dispose();
          await server.close();
        }
      });
    },
  );

  testWidgets('expired or insecure pairing information never opens a socket', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = FakeMacServer();
      var connectionAttempts = 0;
      final client = MobileClient(
        store: MemoryMobileStore(),
        connector: (uri) {
          connectionAttempts++;
          return server.connect(uri);
        },
      );
      try {
        await client.initialize();
        final expired = jsonDecode(server.pairingCode) as Json;
        expired['expiresAt'] = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String();
        await expectLater(
          client.pair(jsonEncode(expired), 'QA iPhone'),
          throwsA(isA<MobileFailure>()),
        );
        final insecure = jsonDecode(server.pairingCode) as Json;
        insecure['endpoint'] = 'ws://127.0.0.1:43827/mobile';
        await expectLater(
          client.pair(jsonEncode(insecure), 'QA iPhone'),
          throwsA(isA<MobileFailure>()),
        );
        expect(connectionAttempts, 0);
        expect(client.canControl, isFalse);
      } finally {
        client.dispose();
      }
    });
  });

  testWidgets('rejected start stays idle and clears the known operation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final server = FakeMacServer();
      await server.start();
      final client = MobileClient(
        store: MemoryMobileStore(),
        connector: server.connect,
      );
      try {
        await client.initialize();
        await client.pair(server.pairingCode, 'QA iPhone');
        server.rejectNextRun = true;
        await client.command(
          'run',
          planID: FakeMacServer.planID,
          revision: client.snapshot!['revision'],
        );
        expect(server.runCount, 0);
        expect(client.snapshot!['busy'], isFalse);
        expect(client.uncertain, isFalse);
        expect(client.notice, contains('状态已变化'));
      } finally {
        client.dispose();
        await server.close();
      }
    });
  });
}
