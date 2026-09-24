import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/local_message_retry_service.dart';
import '../../domain/services/messages_source_of_truth.dart';
import '../app_scope.dart';
import '../theme/net_semantic_colors.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';

/// الرسائل الفاشلة + Bulk Reset/Retry + تفاصيل رمز الرفض — 1.0.9.
class FailedMessagesScreen extends StatefulWidget {
  const FailedMessagesScreen({super.key});

  @override
  State<FailedMessagesScreen> createState() => _FailedMessagesScreenState();
}

class _FailedMessagesScreenState extends State<FailedMessagesScreen> {
  bool _loading = true;
  String? _error;
  List<_FailedRow> _rows = const [];
  String? _busyId;
  bool _bulkBusy = false;

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
    final c = AppScope.of(context);
    final result = await MessagesFacade(RepositoryMessagesSource(c.messages))
        .list(MessageListCategory.failed);
    if (!mounted) return;
    if (result is Failure<List<IncomingMessage>>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    final list = (result as Success<List<IncomingMessage>>).value;
    final rows = <_FailedRow>[];
    for (final m in list) {
      final st = await c.retryService.state(m.id);
      final state = st is Success<MessageRetryState> ? st.value : null;
      rows.add(_FailedRow(message: m, retry: state));
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = rows;
    });
  }

  Future<void> _retryOne(IncomingMessage message) async {
    setState(() => _busyId = message.id);
    final c = AppScope.of(context);
    await c.retryService.requestImmediateRetry(message.id);
    final result = await c.recoveryService.retryNow(message.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error.message, style: const TextStyle(fontFamily: 'Tajawal')),
        ),
      );
    }
    await _load();
  }

  Future<void> _bulkResetAndRetry() async {
    final exhausted = _rows.where((r) => r.retry?.exhausted == true).toList();
    final targets = exhausted.isNotEmpty ? exhausted : _rows;
    if (targets.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة جدولة جماعية؟', style: TextStyle(fontFamily: 'Tajawal')),
        content: Text(
          'سيتم إعادة جدولة ${targets.length} رسالة وإرسالها من جديد.',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنفيذ', style: TextStyle(fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkBusy = true);
    final c = AppScope.of(context);
    var done = 0;
    for (final row in targets) {
      await c.retryService.requestImmediateRetry(row.message.id);
      // Clear exhausted by recording a fresh request then retry
      final r = await c.recoveryService.retryNow(row.message.id);
      if (r is Success<void>) done++;
    }
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'أُعيدت جدولة $done من ${targets.length}',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const NetAppBarTitle(
            icon: Icons.replay_circle_filled_rounded,
            title: 'إعادة المحاولة',
            subtitle: 'الرسائل التي تحتاج إعادة إرسال',
          ),
          centerTitle: false,
          actions: [
            if (_rows.isNotEmpty)
              TextButton.icon(
                onPressed: _bulkBusy ? null : _bulkResetAndRetry,
                icon: _bulkBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_check),
                label: const Text(
                  'إعادة الكل',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : _rows.isEmpty
                    ? const AsyncEmptyView(
                        message: 'لا توجد رسائل فاشلة بانتظار إعادة المحاولة',
                        icon: Icons.check_circle_outline,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final row = _rows[index];
                            final item = row.message;
                            final busy = _busyId == item.id;
                            final retry = row.retry;
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.sender,
                                            style: const TextStyle(
                                              fontFamily: 'Tajawal',
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (retry?.exhausted == true)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: context.netColors.rejectedContainer,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'استنفدت المحاولات',
                                              style: TextStyle(
                                                fontFamily: 'Tajawal',
                                                fontSize: 11,
                                                color: context.netColors.rejected,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.body,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                                    ),
                                    if (retry?.lastErrorCode != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'رمز الرفض: ${retry!.lastErrorCode}',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          fontSize: 12,
                                          color: context.netColors.warning,
                                        ),
                                      ),
                                    ],
                                    if (retry != null)
                                      Text(
                                        'المحاولات: ${retry.attempts}',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FilledButton.icon(
                                        onPressed: busy ? null : () => _retryOne(item),
                                        icon: busy
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.refresh),
                                        label: const Text(
                                          'إعادة المحاولة',
                                          style: TextStyle(fontFamily: 'Tajawal'),
                                        ),
                                      ),
                                    ),
                                  ],
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

final class _FailedRow {
  const _FailedRow({required this.message, this.retry});
  final IncomingMessage message;
  final MessageRetryState? retry;
}
