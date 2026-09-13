import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../app_scope.dart';
import '../widgets/async_views.dart';

/// Operator recovery screen for transiently failed inbound payment messages.
class FailedMessagesScreen extends StatefulWidget {
  const FailedMessagesScreen({super.key});

  @override
  State<FailedMessagesScreen> createState() => _FailedMessagesScreenState();
}

class _FailedMessagesScreenState extends State<FailedMessagesScreen> {
  bool _loading = true;
  String? _error;
  List<IncomingMessage> _items = const [];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AppScope.of(context).messages.listByStatus(MessageProcessingStatus.failed);
    if (!mounted) return;
    if (result is Failure<List<IncomingMessage>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _items = (result as Success<List<IncomingMessage>>).value;
    });
  }

  Future<void> _retry(IncomingMessage message) async {
    setState(() => _busyId = message.id);
    final result = await AppScope.of(context).recoveryService.retryNow(message.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error.message)));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الرسائل التي تحتاج إعادة محاولة', style: TextStyle(fontFamily: 'Tajawal')),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? const AsyncEmptyView(
                        message: 'لا توجد رسائل فاشلة بانتظار إعادة المحاولة',
                        icon: Icons.check_circle_outline,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item = _items[index];
                            final busy = _busyId == item.id;
                            return Card(
                              child: ListTile(
                                title: Text(item.sender, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  item.body,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: 'Tajawal'),
                                ),
                                trailing: FilledButton.icon(
                                  onPressed: busy ? null : () => _retry(item),
                                  icon: busy
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.refresh),
                                  label: const Text('إعادة', style: TextStyle(fontFamily: 'Tajawal')),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}
