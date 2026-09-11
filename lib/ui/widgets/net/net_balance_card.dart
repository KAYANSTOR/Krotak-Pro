import 'package:flutter/material.dart';
import '../../theme/net_semantic_colors.dart';
import '../async_views.dart';

class NetBalanceCard extends StatelessWidget {
  const NetBalanceCard({super.key, required this.balanceMinor, required this.accountsCount, required this.availableCards, this.onTapAccounts, this.onTapCards});
  final int balanceMinor;
  final int accountsCount;
  final int availableCards;
  final VoidCallback? onTapAccounts;
  final VoidCallback? onTapCards;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: [net.balanceGradientStart, net.balanceGradientEnd], begin: Alignment.topRight, end: Alignment.bottomLeft),
        boxShadow: [BoxShadow(color: net.balanceGradientStart.withOpacity(0.28), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('أرصدة العملاء', style: TextStyle(fontFamily: 'Tajawal', color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(formatMoneyMinor(balanceMinor), style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _chip(label: 'حسابات', value: '$accountsCount', onTap: onTapAccounts)),
            const SizedBox(width: 10),
            Expanded(child: _chip(label: 'كروت متاحة', value: '$availableCards', onTap: onTapCards)),
          ]),
        ],
      ),
    );
  }

  Widget _chip({required String label, required String value, VoidCallback? onTap}) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white70, fontSize: 11)),
            Text(value, style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        ),
      ),
    );
  }
}
