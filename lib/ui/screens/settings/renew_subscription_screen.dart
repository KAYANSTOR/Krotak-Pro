import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/license.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

class RenewSubscriptionScreen extends StatefulWidget {
  const RenewSubscriptionScreen({super.key});

  @override
  State<RenewSubscriptionScreen> createState() => _RenewSubscriptionScreenState();
}

class _RenewSubscriptionScreenState extends State<RenewSubscriptionScreen> {
  bool _loading = true;
  String? _current;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await AppScope.of(context).licenseService.current();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<License>) {
        _current = '${r.value.status.name} · ينتهي ${r.value.expiresAt}';
      } else {
        _current = (r as Failure).error.message;
      }
    });
  }

  Future<void> _extend(int days) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final r = await c.licenseService.activateOffline(
      licenseId: c.ids.next('lic'),
      expiresAt: c.clock.now().add(Duration(days: days)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r is Success<License>
          ? 'تم التجديد حتى ${r.value.expiresAt}'
          : (r as Failure).error.message;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تجديد الاشتراك')),
      body: _loading
          ? const AsyncLoadingView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('الحالة: $_current', style: const TextStyle(fontFamily: 'Tajawal')),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _extend(30),
                  child: const Text('تجديد 30 يومًا (محلي)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _extend(365),
                  child: const Text('تجديد سنة (محلي)'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: const TextStyle(fontFamily: 'Tajawal')),
                ],
              ],
            ),
    );
  }
}
