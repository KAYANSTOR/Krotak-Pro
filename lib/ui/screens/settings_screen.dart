import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/license.dart';
import '../app_scope.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _status;
  bool _busy = false;

  Future<void> _activateTrial() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final result = await c.licenseService.activateOffline(
      licenseId: c.ids.next('lic'),
      expiresAt: c.clock.now().add(const Duration(days: 30)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Success<License>) {
        _status = 'ترخيص نشط حتى ${result.value.expiresAt}';
      } else {
        _status = (result as Failure).error.message;
      }
    });
  }

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final result = await c.backupService.createBackup(label: 'manual');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Success) {
        _status = 'تم إنشاء نسخة احتياطية';
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
        FilledButton(
          onPressed: _busy ? null : _activateTrial,
          child: const Text('تفعيل ترخيص تجريبي (30 يوم)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _backup,
          child: const Text('نسخ احتياطي للإعدادات'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          Text(_status!),
        ],
      ],
    );
  }
}
