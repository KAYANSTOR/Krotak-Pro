import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/license.dart';
import '../app_scope.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _idCtrl = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final id = _idCtrl.text.trim().isEmpty ? c.ids.next('lic') : _idCtrl.text.trim();
    final r = await c.licenseService.activateOffline(
      licenseId: id,
      expiresAt: c.clock.now().add(const Duration(days: 30)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r is Success<License>
          ? 'مفعّل: ${r.value.id} حتى ${r.value.expiresAt}'
          : (r as Failure).error.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفعيل الترخيص')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'التفعيل محلي (offline-first). التحقق عبر الإنترنت اختياري وغير مربوط بخادم حاليًا.',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              labelText: 'معرّف الترخيص (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _activate,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تفعيل 30 يومًا'),
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
