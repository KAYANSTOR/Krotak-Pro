import 'package:flutter/material.dart';
import '../../../domain/entities/transaction.dart';
import '../../theme/net_semantic_colors.dart';
import '../async_views.dart';

class NetRecentTransactionCard extends StatelessWidget {
  const NetRecentTransactionCard({super.key, required this.transaction, this.onTap});
  final Transaction transaction;
  final VoidCallback? onTap;

  Color _statusColor(BuildContext context) {
    final net = context.netColors;
    switch (transaction.status) {
      case TransactionStatus.completed: return net.success;
      case TransactionStatus.pending: return net.pending;
      case TransactionStatus.reversed: return net.warning;
      case TransactionStatus.rejected: return net.rejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(backgroundColor: statusColor.withOpacity(0.15), child: Icon(Icons.receipt_long, color: statusColor, size: 18)),
      title: Text('${transaction.type.name} — ${formatMoneyMinor(transaction.amount.minorUnits)}', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, color: cs.onSurface)),
      subtitle: Text(transaction.reference ?? transaction.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: cs.onSurfaceVariant)),
      trailing: Text(transaction.status.name, style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
    );
  }
}
