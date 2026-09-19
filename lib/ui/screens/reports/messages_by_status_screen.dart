import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../app_scope.dart';
import '../../labels/net_labels.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

class MessagesByStatusScreen extends StatefulWidget {
  const MessagesByStatusScreen({
    super.key,
    required this.title,
    required this.statuses,
  });

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
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final collected = <IncomingMessage>[];
    for (final status in widget.statuses) {
      final r = await c.messages.listByStatus(status);
      if (r is Failure<List<IncomingMessage>>) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = r.error.message;
        });
        return;
      }
      collected.addAll((r as Success<List<IncomingMessage>>).value);
    }
    collected.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = collected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const AsyncLoadingView(skeleton: true, skeletonCount: 5)
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? AsyncEmptyView(
                      message: 'لا رسائل في هذه الحالة',
                      hint: 'ستظهر هنا الرسائل الواردة بهذه الحالة مرتبة من الأحدث.',
                      icon: Icons.mark_email_unread_outlined,
                      actionLabel: 'إعادة التحميل',
                      onAction: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: context.kayan.primary,
                      child: ListView.builder(
                        padding: NetSpacing.screen,
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final m = _items[i];
                          final net = context.netColors;
                          final status = m.status;
                          return NetSurfaceCard(
                            margin: const EdgeInsets.only(bottom: NetSpacing.sm),
                            padding: NetSpacing.cardTight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.sender.isEmpty ? 'مرسل غير معروف' : m.sender,
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: context.kayan.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: NetSpacing.sm),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: NetSpacing.sm,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: messageStatusContainer(status, net),
                                        borderRadius: BorderRadius.circular(NetRadii.xs),
                                      ),
                                      child: Text(
                                        messageStatusLabel(status),
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: messageStatusColor(status, net),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: NetSpacing.xs),
                                Text(
                                  m.body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: context.kayan.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: NetSpacing.sm),
                                Text(
                                  relativeArabicTime(m.receivedAt),
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 11,
                                    color: context.kayan.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
