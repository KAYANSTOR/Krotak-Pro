import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_surface_card.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _senderCtrl = TextEditingController(text: 'BANK');
  final _bodyCtrl = TextEditingController(
    text: 'تم تحويل 1500 ريال الى 770123456 برقم العملية REF-99',
  );
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _senderCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _simulate() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final result = await c.smsHandler.handleManual(
      sender: _senderCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Success<Transaction?>) {
        final tx = result.value;
        _status = tx == null
            ? 'رسالة مكررة أو بدون أثر'
            : 'تمت المعالجة — معاملة ${tx.id}';
      } else {
        _status = (result as Failure).error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return ListView(
      padding: NetSpacing.screen,
      children: [
        Text(
          'محاكاة رسالة تحويل (للاختبار دون SMS حقيقي)',
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: NetSpacing.md),
        NetSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _senderCtrl,
                decoration: const InputDecoration(labelText: 'المرسل'),
              ),
              const SizedBox(height: NetSpacing.md),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'نص الرسالة'),
              ),
              const SizedBox(height: NetSpacing.lg),
              FilledButton(
                onPressed: _busy ? null : _simulate,
                child: const Text('معالجة الرسالة'),
              ),
            ],
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: NetSpacing.md),
          NetSurfaceCard(
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: Text(
                    _status!,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13,
                      height: 1.4,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
