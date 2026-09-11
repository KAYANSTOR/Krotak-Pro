import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

class MessagesByStatusScreen extends StatefulWidget {
  const MessagesByStatusScreen({super.key, required this.title, required this.statuses});
  final String title;
  final List<MessageProcessingStatus> statuses;
  @override
  State<MessagesByStatusScreen> createState() => _MessagesByStatusScreenState();
}

class _MessagesByStatusScreenState extends State<MessagesByStatusScreen> {
  bool _loading = true;
  String? _error;
  List<IncomingMessage> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final c = AppScope.of(context);
    final collected = <IncomingMessage>[];
    for (final status in widget.statuses) {
      final r = await c.messages.listByStatus(status);
      if (r is Failure<List<IncomingMessage>>) {
        if (!mounted) return;
        setState(() { _loading = false; _error = r.error.message; });
        return;
      }
      collected.addAll((r as Success<List<IncomingMessage>>).value);
    }
    collected.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (!mounted) return;
    setState(() { _loading = false; _items = collected; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const AsyncEmptyView(message: 'لا رسائل في هذه الحالة')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = _items[i];
                          return ListTile(
                            title: Text(m.sender, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                            subtitle: Text('${m.status.name}\n${m.body}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                            isThreeLine: true,
                          );
                        },
                      ),
                    ),
    );
  }
}
