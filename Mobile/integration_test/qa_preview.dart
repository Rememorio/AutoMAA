import 'package:automaa_mobile/main.dart';
import 'package:automaa_mobile/mobile_client.dart';
import 'package:flutter/widgets.dart';

import 'support/fake_mac_server.dart';

class _PreviewStore implements MobileStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

/// A separate test entry point for native simulator screenshots, never a release flag.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final server = FakeMacServer();
  await server.start();
  final client = MobileClient(
    store: _PreviewStore(),
    connector: server.connect,
  );
  await client.initialize();
  await client.pair(server.pairingCode, 'QA iPhone');
  runApp(AutoMAAMobileApp(client: client));
}
