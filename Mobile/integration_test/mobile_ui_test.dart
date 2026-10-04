import 'dart:async';

import 'package:automaa_mobile/main.dart';
import 'package:automaa_mobile/mobile_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_mac_server.dart';

class _Store implements MobileStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  throw TimeoutException('UI did not settle');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'complete mobile UI flow with a loopback Mac and responsive states',
    (tester) async {
      final server = FakeMacServer()..autoApprove = false;
      await server.start();
      final client = MobileClient(store: _Store(), connector: server.connect);
      try {
        await tester.pumpWidget(AutoMAAMobileApp(client: client));
        await tester.pumpAndSettle();
        expect(find.text('连接你的 Mac'), findsOneWidget);
        await binding.takeScreenshot('ios-empty-light');

        await tester.tap(find.byTooltip('添加 Mac'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('扫描 Mac 上的二维码'));
        await _until(
          tester,
          () => find.textContaining('摄像头不可用').evaluate().isNotEmpty,
        );
        await binding.takeScreenshot('ios-camera-unavailable');
        await tester.tap(find.text('返回'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'QA iPhone');
        final pairingCode = server.pairingCode;
        await Clipboard.setData(ClipboardData(text: pairingCode));
        await tester.tap(find.text('粘贴配对信息'));
        await tester.pumpAndSettle();
        final codeField = tester.widget<TextField>(find.byType(TextField).last);
        expect(codeField.controller!.text, pairingCode);
        expect(codeField.obscureText, isTrue);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('连接并请求授权'));
        await _until(tester, () => client.state == LinkState.awaitingApproval);
        expect(find.text('请在 Mac 上确认授权'), findsOneWidget);
        await binding.takeScreenshot('ios-pairing-approval');
        server.approvePendingPairing();
        await _until(tester, () => client.online);
        await tester.pumpAndSettle();
        expect(find.text('当前空闲'), findsOneWidget);
        await binding.takeScreenshot('ios-overview-light');

        await tester.tap(find.text('日常方案'));
        await tester.pumpAndSettle();
        expect(find.text('执行账号'), findsOneWidget);
        await binding.takeScreenshot('ios-plan-light');
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, '运行方案'),
          300,
        );
        await tester.tap(find.widgetWithText(FilledButton, '运行方案'));
        await tester.pumpAndSettle();
        expect(find.text('运行方案「日常方案」？'), findsOneWidget);
        expect(find.textContaining('不使用源石'), findsWidgets);
        await binding.takeScreenshot('ios-run-confirmation');
        await tester.tap(find.widgetWithText(TextButton, '运行方案'));
        await _until(tester, () => server.runCount == 1 && !client.sending);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('执行任务'), findsOneWidget);
        await binding.takeScreenshot('ios-running-light');
        await tester.tap(find.widgetWithText(OutlinedButton, '安全停止'));
        await tester.pumpAndSettle();
        expect(find.text('安全停止当前运行？'), findsOneWidget);
        await binding.takeScreenshot('ios-stop-confirmation');
        await tester.tap(find.widgetWithText(TextButton, '安全停止'));
        await _until(tester, () => server.stopCount == 1 && !client.sending);
        expect(client.snapshot!['busy'], isFalse);

        await tester.tap(find.text('活动'));
        await tester.pumpAndSettle();
        expect(find.text('已加载 1 条记录'), findsOneWidget);
        await tester.tap(find.text('提醒'));
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的记录'), findsOneWidget);
        await tester.tap(find.text('加载更多'));
        await _until(tester, () => find.text('维护检查').evaluate().isNotEmpty);
        expect(find.text('已加载 2 条记录'), findsOneWidget);
        await tester.tap(find.text('失败'));
        await tester.pumpAndSettle();
        await binding.takeScreenshot('ios-history-filter');
        await tester.enterText(find.byType(TextField), '不匹配');
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的记录'), findsOneWidget);
        await tester.tap(find.byTooltip('清除搜索'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('维护检查'));
        await _until(tester, () => find.text('基建换班已完成').evaluate().isNotEmpty);
        await tester.tap(find.text('详细信息'));
        await tester.pumpAndSettle();
        expect(find.text('测试账号 · 连接已清理'), findsOneWidget);
        await tester.tap(find.text('加载更早记录'));
        await _until(tester, () => find.text('任务准备完成').evaluate().isNotEmpty);
        await binding.takeScreenshot('ios-history-detail');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('设备'));
        await tester.pumpAndSettle();
        expect(find.text('qa-mac.example.ts.net'), findsOneWidget);
        await binding.takeScreenshot('ios-devices-light');

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.tap(find.text('总览'));
        await tester.pumpAndSettle();
        await binding.takeScreenshot('ios-overview-dark');
        expect(tester.takeException(), isNull);

        tester.platformDispatcher.textScaleFactorTestValue = 2;
        server.planName = '非常长的自动化方案名称用于验证窄屏和大字体换行';
        server.broadcast();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('ios-overview-large-text');
        await tester.tap(find.text('活动'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('ios-history-large-text');
        await tester.tap(find.text('设备'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('ios-devices-large-text');

        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        await tester.pumpAndSettle();
        await tester.tap(find.text('总览'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('ios-overview-landscape');
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await tester.pumpAndSettle();

        server.running = true;
        server.broadcast();
        await _until(tester, () => client.snapshot?['busy'] == true);
        client.setPaused(true);
        await tester.pumpAndSettle();
        expect(client.canControl, isFalse);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '安全停止'),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining('最近更新'), findsOneWidget);
        await binding.takeScreenshot('ios-offline');
        expect(tester.takeException(), isNull);
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await Clipboard.setData(const ClipboardData(text: ''));
        await tester.pumpWidget(const SizedBox.shrink());
        client.dispose();
        await server.close();
      }
    },
  );
}
