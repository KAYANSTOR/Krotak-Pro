import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/license.dart';
import '../app_scope.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _licenseLabel = '…';
  bool _smsOk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final license = await c.licenseService.current();
    final sms = await c.smsBridge.hasPermissions();
    if (!mounted) return;
    setState(() {
      if (license is Success<License>) {
        _licenseLabel = license.value.status.name;
      } else {
        _licenseLabel = 'غير مفعّل';
      }
      _smsOk = sms;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user),
            title: const Text('الترخيص'),
            subtitle: Text(_licenseLabel),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              _smsOk ? Icons.sms : Icons.sms_failed,
              color: _smsOk ? Colors.green : Colors.orange,
            ),
            title: const Text('صلاحيات SMS'),
            subtitle: Text(_smsOk ? 'مفعّلة' : 'غير مفعّلة'),
            trailing: TextButton(
              onPressed: () async {
                await AppScope.of(context).smsBridge.requestPermissions();
                await _load();
              },
              child: const Text('طلب'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'NET يعمل محلياً: العملاء، المخزون، البيع من الرصيد، وتحليل التحويلات.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
