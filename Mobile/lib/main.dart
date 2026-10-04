import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'mobile_client.dart';
import 'mobile_pages.dart';
import 'pairing_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AutoMAAMobileApp(client: MobileClient()));
}

ThemeData mobileTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff007d78),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xff4fccc2) : const Color(0xff007d78),
        surface: dark ? const Color(0xff191b1c) : const Color(0xfff7f8f9),
        surfaceContainer: dark ? const Color(0xff232627) : Colors.white,
        error: dark ? const Color(0xffffb4ab) : const Color(0xffb3261e),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    brightness: brightness,
  );
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    textTheme: base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(letterSpacing: 0),
      displayMedium: base.textTheme.displayMedium?.copyWith(letterSpacing: 0),
      displaySmall: base.textTheme.displaySmall?.copyWith(letterSpacing: 0),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(letterSpacing: 0),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(letterSpacing: 0),
      titleMedium: base.textTheme.titleMedium?.copyWith(letterSpacing: 0),
      titleSmall: base.textTheme.titleSmall?.copyWith(letterSpacing: 0),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(letterSpacing: 0),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(letterSpacing: 0),
      bodySmall: base.textTheme.bodySmall?.copyWith(letterSpacing: 0),
      labelLarge: base.textTheme.labelLarge?.copyWith(letterSpacing: 0),
      labelMedium: base.textTheme.labelMedium?.copyWith(letterSpacing: 0),
      labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainer,
    ),
  );
}

class AutoMAAMobileApp extends StatefulWidget {
  final MobileClient client;
  const AutoMAAMobileApp({super.key, required this.client});
  @override
  State<AutoMAAMobileApp> createState() => _AutoMAAMobileAppState();
}

class _AutoMAAMobileAppState extends State<AutoMAAMobileApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.client.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.client.setPaused(true);
    }
    if (state == AppLifecycleState.resumed) widget.client.setPaused(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AutoMAA',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: mobileTheme(Brightness.light),
    darkTheme: mobileTheme(Brightness.dark),
    home: MobileHome(client: widget.client),
  );
}

class MobileHome extends StatefulWidget {
  final MobileClient client;
  const MobileHome({super.key, required this.client});
  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  int index = 0;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) {
      final client = widget.client;
      return Scaffold(
        appBar: AppBar(
          title: const Text('AutoMAA'),
          actions: [
            IconButton(
              tooltip: '刷新状态',
              onPressed: client.activeHost == null || client.sending
                  ? null
                  : client.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '添加 Mac',
              onPressed: client.sending
                  ? null
                  : () => openPairing(context, client),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              ConnectionStrip(client: client),
              Expanded(
                child: IndexedStack(
                  index: index,
                  children: [
                    OverviewPage(client: client),
                    HistoryPage(
                      key: ValueKey(client.activeHost?.id),
                      client: client,
                    ),
                    DevicesPage(client: client),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: '总览',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: '活动',
            ),
            NavigationDestination(
              icon: Icon(Icons.devices_outlined),
              selectedIcon: Icon(Icons.devices),
              label: '设备',
            ),
          ],
        ),
      );
    },
  );
}

class ConnectionStrip extends StatelessWidget {
  final MobileClient client;
  const ConnectionStrip({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    final label = switch (client.state) {
      LinkState.connected => '已连接',
      LinkState.connecting => '连接中',
      LinkState.awaitingApproval => '等待 Mac 授权',
      LinkState.unauthorized => '需要重新配对',
      LinkState.disconnected =>
        client.activeHost == null ? '尚未连接 Mac' : '连接已断开',
    };
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            client.online ? Icons.check_circle_outline : Icons.computer,
            color: client.online
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${client.activeHost?.name ?? 'AutoMAA'} · $label',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (client.error != null)
                  Text(
                    client.error!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (!client.online && client.lastReceived != null)
                  Text(
                    '最近更新 ${formatTime(client.lastReceived!.toIso8601String())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void openPairing(BuildContext context, MobileClient client) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PairingPage(client: client)));
}
