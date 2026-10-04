import 'dart:async';

import 'package:flutter/material.dart';

import 'mobile_client.dart';
import 'mobile_pages.dart' show EmptyState, SectionTitle, formatTime;

class HistoryPage extends StatefulWidget {
  final MobileClient client;
  const HistoryPage({super.key, required this.client});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final search = TextEditingController();
  List<Json> records = [];
  String? next;
  String? error;
  bool loading = false;
  bool loaded = false;
  int filter = 0;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (!loaded && !loading && widget.client.online) unawaited(_load());
  }

  @override
  void dispose() {
    generation++;
    widget.client.removeListener(_changed);
    search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (loading || !widget.client.online) return;
    final attempt = ++generation;
    final host = widget.client.activeHost?.id;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.client.request(
        'history',
        fields: {if (more && next != null) 'before': next},
      );
      if (!mounted ||
          attempt != generation ||
          host != widget.client.activeHost?.id) {
        return;
      }
      final page = (result['history'] as List).cast<Json>();
      setState(() {
        records = more ? [...records, ...page] : page;
        next = result['next'] as String?;
        loaded = true;
      });
    } catch (failure) {
      if (mounted && attempt == generation) {
        setState(() {
          error = failure is MobileFailure ? failure.message : '记录读取失败，请重试';
          loaded = true;
        });
      }
    } finally {
      if (mounted && attempt == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = records
        .where(
          (item) =>
              (filter == 0 ||
                  (filter == 1
                      ? item['hasAttention'] == true
                      : item['failed'] == true)) &&
              '${item['title']} ${item['status']}'.toLowerCase().contains(
                query,
              ),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('全部')),
              ButtonSegment(value: 1, label: Text('提醒')),
              ButtonSegment(value: 2, label: Text('失败')),
            ],
            selected: {filter},
            onSelectionChanged: (value) => setState(() => filter = value.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '搜索已加载记录',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => search.clear()),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '已加载 ${records.length} 条记录',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!),
            ),
          if (!widget.client.online)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('连接后可刷新活动记录'),
            ),
          if (loading && records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!loading && visible.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: records.isEmpty ? '暂无活动记录' : '没有匹配的记录',
            ),
          for (final item in visible)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              title: Text(item['title'] as String),
              subtitle: Text(
                '${formatTime(item['startedAt'] as String)}\n${item['status']}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      HistoryDetails(client: widget.client, record: item),
                ),
              ),
            ),
          if (next != null)
            OutlinedButton(
              onPressed: loading || !widget.client.online
                  ? null
                  : () => _load(more: true),
              child: Text(loading ? '正在加载' : '加载更多'),
            ),
          if (error != null || (!loaded && !loading))
            TextButton(
              onPressed: widget.client.online ? _load : null,
              child: const Text('重新加载'),
            ),
        ],
      ),
    );
  }
}

class HistoryDetails extends StatefulWidget {
  final MobileClient client;
  final Json record;
  const HistoryDetails({super.key, required this.client, required this.record});
  @override
  State<HistoryDetails> createState() => _HistoryDetailsState();
}

class _HistoryDetailsState extends State<HistoryDetails> {
  List<Json> events = [];
  String? next;
  String? error;
  bool loading = false;
  late final String? hostID = widget.client.activeHost?.id;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    if (loading) return;
    if (!widget.client.online || widget.client.activeHost?.id != hostID) {
      setState(() => error = '请先重新连接原来的 Mac');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final reply = await widget.client.request(
        'historyDetails',
        fields: {
          'historyID': widget.record['id'],
          if (more && next != null) 'before': next,
        },
      );
      if (!mounted || widget.client.activeHost?.id != hostID) return;
      final page = (reply['events'] as List).cast<Json>();
      setState(() {
        events = more ? [...events, ...page] : page;
        next = reply['next'] as String?;
      });
    } catch (failure) {
      if (mounted) {
        setState(
          () =>
              error = failure is MobileFailure ? failure.message : '详情读取失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record['title'] as String),
      actions: [
        IconButton(
          tooltip: '刷新记录',
          onPressed: loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            formatTime(widget.record['startedAt'] as String),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SectionTitle('执行记录 · 最近在前'),
          if (error != null) Text(error!),
          if (loading && events.isEmpty)
            const Center(child: CircularProgressIndicator()),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        event['level'] == 'error'
                            ? Icons.error_outline
                            : event['level'] == 'warning'
                            ? Icons.warning_amber
                            : Icons.notes,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatTime(event['timestamp'] as String),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(event['message'] as String),
                  if (event['details'] != null)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('详细信息'),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(event['details'] as String),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  const Divider(),
                ],
              ),
            ),
          if (next != null)
            OutlinedButton(
              onPressed: loading ? null : () => _load(more: true),
              child: const Text('加载更早记录'),
            ),
          if (error != null)
            TextButton(
              onPressed: loading ? null : _load,
              child: const Text('重试'),
            ),
        ],
      ),
    ),
  );
}
