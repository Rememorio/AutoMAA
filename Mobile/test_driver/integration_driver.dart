import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name) || bytes.length < 1000) {
        return false;
      }
      final directory = Directory('../dist/mobile/screenshots');
      await directory.create(recursive: true);
      final prefix = Platform.environment['AUTOMAA_QA_SCREENSHOT_PREFIX'] ?? '';
      if (!RegExp(r'^[a-z0-9-]*$').hasMatch(prefix)) return false;
      await File('${directory.path}/$prefix$name.png')
          .writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: null,
  );
}
