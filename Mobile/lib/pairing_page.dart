import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'mobile_client.dart';

class PairingPage extends StatefulWidget {
  final MobileClient client;
  const PairingPage({super.key, required this.client});
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final code = TextEditingController();
  final name = TextEditingController(
    text: Platform.isIOS ? '我的 iPhone' : '我的 Android',
  );
  bool busy = false;
  bool visible = false;
  String? error;
  @override
  void dispose() {
    widget.client.cancelPairing();
    code.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.pair(code.text, name.text);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MobileFailure ? failure.message : '配对失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('添加 Mac')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: name,
            enabled: !busy,
            maxLength: 60,
            decoration: const InputDecoration(labelText: '这台手机的名称'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final raw = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(builder: (_) => const ScannerPage()),
                    );
                    if (mounted && raw != null) {
                      setState(() {
                        code.text = raw;
                        error = null;
                      });
                    }
                  },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('扫描 Mac 上的二维码'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: code,
            enabled: !busy,
            obscureText: !visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '配对信息',
              suffixIcon: IconButton(
                tooltip: visible ? '隐藏配对信息' : '显示配对信息',
                onPressed: () => setState(() => visible = !visible),
                icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (mounted) setState(() => code.text = data?.text ?? '');
                    },
              icon: const Icon(Icons.content_paste),
              label: const Text('粘贴配对信息'),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (busy)
            AnimatedBuilder(
              animation: widget.client,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.client.state == LinkState.awaitingApproval
                            ? '请在 Mac 上确认授权'
                            : '正在连接 Mac',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: busy ? null : _pair,
            icon: const Icon(Icons.link),
            label: const Text('连接并请求授权'),
          ),
          if (busy)
            TextButton(
              onPressed: widget.client.cancelPairing,
              child: const Text('取消配对'),
            ),
        ],
      ),
    ),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool captured = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('扫描配对二维码'),
      actions: [
        IconButton(
          tooltip: '切换补光灯',
          onPressed: controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
      ],
    ),
    body: MobileScanner(
      controller: controller,
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 40),
              const SizedBox(height: 16),
              const Text(
                '摄像头不可用。请检查相机权限，或返回后粘贴配对信息。',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (!captured && value != null) {
          captured = true;
          Navigator.pop(context, value);
        }
      },
    ),
  );
}
