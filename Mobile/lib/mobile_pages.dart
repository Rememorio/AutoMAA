import 'package:flutter/material.dart';

import 'main.dart' show openPairing;
import 'mobile_client.dart';
export 'history_page.dart';

String formatTime(String? raw) {
  final date = DateTime.tryParse(raw ?? '')?.toLocal();
  if (date == null) return '时间未知';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.month}月${date.day}日 ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 38,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(detail!, textAlign: TextAlign.center),
          ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 20), child: action!),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: danger
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showFailure(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MobileFailure ? error.message : '操作未完成，请检查连接后重试',
          ),
        ),
      );
    }
  }
}

class OverviewPage extends StatelessWidget {
  final MobileClient client;
  const OverviewPage({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    if (!client.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (client.activeHost == null) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.link,
            title: '连接你的 Mac',
            detail: '在 Mac 的 AutoMAA「全局设置 → 手机连接」生成配对信息。',
            action: FilledButton.icon(
              onPressed: client.storageFailed
                  ? null
                  : () => openPairing(context, client),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('添加 Mac'),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: client.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          CommandNotice(client: client),
          if (client.snapshot != null) CurrentRun(client: client),
          const SectionTitle('自动化方案'),
          if (client.plans.isEmpty)
            EmptyState(
              icon: Icons.playlist_add_check,
              title: client.snapshot == null ? '尚未获取方案' : '没有自动化方案',
              detail: client.snapshot == null
                  ? '检查连接后重新刷新。'
                  : '请先在 Mac 创建并配置方案。',
            ),
          for (final plan in client.plans)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlanPage(
                      client: client,
                      planID: plan['id'] as String,
                      hostID: client.activeHost!.id,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              plan['name'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text((plan['tasks'] as List).join(' · ')),
                      const SizedBox(height: 8),
                      Text(
                        plan['schedule'] as String,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            plan['canRun'] == true
                                ? Icons.play_circle_outline
                                : Icons.info_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              plan['action'] as String,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          Text(
                            (plan['accounts'] as List).length > 50
                                ? '50+ 个账号'
                                : '${(plan['accounts'] as List).length} 个账号',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CommandNotice extends StatelessWidget {
  final MobileClient client;
  const CommandNotice({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    if (client.notice == null && !client.uncertain) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                client.uncertain ? Icons.pending_actions : Icons.info_outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(client.notice ?? '操作结果待确认，请先检查活动记录')),
            ],
          ),
          if (client.uncertain)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: client.online && !client.sending
                      ? client.resolvePending
                      : null,
                  child: const Text('查询操作回执'),
                ),
                TextButton(
                  onPressed: client.online && !client.sending
                      ? () async {
                          if (await confirmAction(
                                context,
                                title: '已核对上次操作？',
                                message: '请先在活动记录确认上次操作是否执行。清除此提示不会停止或重跑任务，重复运行可能再次消耗游戏资源。',
                                action: '已核对结果',
                              ) &&
                              context.mounted) {
                            await showFailure(
                              context,
                              client.acknowledgePending,
                            );
                          }
                        }
                      : null,
                  child: const Text('已核对结果'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class CurrentRun extends StatelessWidget {
  final MobileClient client;
  const CurrentRun({super.key, required this.client});
  @override
  Widget build(BuildContext context) {
    final snapshot = client.snapshot!;
    final busy = snapshot['busy'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                busy ? Icons.play_circle : Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  snapshot['stopping'] == true
                      ? '正在安全停止'
                      : busy
                      ? snapshot['phase'] as String
                      : '当前空闲',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(snapshot['message'] as String),
          if (busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (snapshot['progress'] as num).toDouble().clamp(0, 1),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: client.canControl && snapshot['canStop'] == true
                  ? () async {
                      final run = Map<String, dynamic>.from(
                        snapshot['run'] as Json,
                      );
                      if (await confirmAction(
                            context,
                            title: '安全停止当前运行？',
                            message: '将终止当前 MAA 命令，关闭正在运行的客户端并清理连接。已完成的任务会保留。',
                            action: '安全停止',
                            danger: true,
                          ) &&
                          context.mounted) {
                        await showFailure(
                          context,
                          () => client.command('stop', run: run),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(snapshot['stopping'] == true ? '等待清理完成' : '安全停止'),
            ),
          ],
        ],
      ),
    );
  }
}

class PlanPage extends StatelessWidget {
  final MobileClient client;
  final String planID;
  final String hostID;
  const PlanPage({
    super.key,
    required this.client,
    required this.planID,
    required this.hostID,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: client,
    builder: (context, _) {
      final plans = client.activeHost?.id == hostID
          ? client.plans.where((plan) => plan['id'] == planID)
          : <Json>[];
      final plan = plans.firstOrNull;
      return Scaffold(
        appBar: AppBar(title: Text(plan?['name'] as String? ?? '方案详情')),
        body: plan == null
            ? const EmptyState(
                icon: Icons.playlist_remove,
                title: '方案已变化',
                detail: '请返回总览重新选择。',
              )
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    CommandNotice(client: client),
                    if (!client.online) const Text('连接已断开，以下为最近获取的信息。'),
                    const SectionTitle('执行账号'),
                    ..._lines(plan['accounts']),
                    const SectionTitle('任务顺序'),
                    ..._lines(plan['tasks']),
                    const SectionTitle('执行设置'),
                    ..._lines(plan['parameters']),
                    const SectionTitle('定时安排'),
                    Text(plan['schedule'] as String),
                    if ((plan['warnings'] as List).isNotEmpty) ...[
                      const SectionTitle('需要留意'),
                      for (final warning in plan['warnings'])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(warning as String)),
                            ],
                          ),
                        ),
                    ],
                    const SectionTitle('待执行内容'),
                    if ((plan['pending'] as List).isEmpty)
                      Text(plan['action'] as String)
                    else
                      ..._lines(plan['pending']),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: client.canControl && plan['canRun'] == true
                          ? () async {
                              final revision =
                                  client.snapshot!['revision'] as String;
                              final summary = [
                                ...(plan['accounts'] as List),
                                '',
                                ...(plan['parameters'] as List),
                              ].join('\n');
                              if (await confirmAction(
                                    context,
                                    title:
                                        '${plan['action']}「${plan['name']}」？',
                                    message: summary,
                                    action: plan['action'] as String,
                                  ) &&
                                  context.mounted) {
                                await showFailure(
                                  context,
                                  () => client.command(
                                    'run',
                                    planID: planID,
                                    revision: revision,
                                  ),
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        client.sending ? '正在发送请求' : plan['action'] as String,
                      ),
                    ),
                  ],
                ),
              ),
      );
    },
  );
  List<Widget> _lines(dynamic values) => (values as List)
      .map(
        (value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(value as String),
        ),
      )
      .toList();
}

class DevicesPage extends StatelessWidget {
  final MobileClient client;
  const DevicesPage({super.key, required this.client});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
    children: [
      const SectionTitle('已配对的 Mac'),
      if (client.hosts.isEmpty)
        const EmptyState(icon: Icons.devices, title: '尚未添加设备'),
      for (final host in client.hosts)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.computer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        host.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '移除此 Mac',
                      onPressed: client.sending
                          ? null
                          : () async {
                              if (await confirmAction(
                                    context,
                                    title: '移除「${host.name}」？',
                                    message: '将删除这台手机保存的连接凭据。Mac 上的任务不受影响；要彻底撤销授权，请在 Mac 的手机连接设置中移除此手机。',
                                    action: '移除设备',
                                    danger: true,
                                  ) &&
                                  context.mounted) {
                                await showFailure(
                                  context,
                                  () => client.forget(host),
                                );
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  Uri.parse(host.endpoint).host,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: client.sending ? null : () => client.connect(host),
                  icon: const Icon(Icons.link),
                  label: Text(
                    host.id == client.activeHost?.id ? '重新连接' : '连接此 Mac',
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: client.sending || client.storageFailed
            ? null
            : () => openPairing(context, client),
        icon: const Icon(Icons.add),
        label: const Text('添加 Mac'),
      ),
    ],
  );
}
