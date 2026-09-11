import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/transaction.dart';
import '../app_scope.dart';

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'محاكاة رسالة تحويل (للاختبار دون SMS حقيقي)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _senderCtrl,
          decoration: const InputDecoration(
            labelText: 'المرسل',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bodyCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'نص الرسالة',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _simulate,
          child: const Text('معالجة الرسالة'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!),
        ],
      ],
    );
  }
}
