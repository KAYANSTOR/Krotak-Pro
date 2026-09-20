import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/services/local_blocked_number_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';

/// قائمة أرقام مستقلة تُرفض رسائلها قبل التحليل والإيداع.
class BlockedNumbersScreen extends StatefulWidget {
  const BlockedNumbersScreen({super.key});

  @override
  State<BlockedNumbersScreen> createState() => _BlockedNumbersScreenState();
}

class _BlockedNumbersScreenState extends State<BlockedNumbersScreen> {
  final _ctrl = TextEditingController();
  List<String> _phones = const [];
  bool _loading = true;
  bool _busy = false;

  LocalBlockedNumberService get _service {
    final c = AppScope.of(context);
    return LocalBlockedNumberService(settings: c.settings, clock: c.clock);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await _service.list();
    if (!mounted) return;
    setState(() {
      _phones = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    final result = await _service.add(raw);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    _ctrl.clear();
    await _reload();
  }

  Future<void> _remove(String phone) async {
    setState(() => _busy = true);
    await _service.remove(phone);
    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kayan.appBackground,
        appBar: AppBar(
          title: const Text(
            'الأرقام المحظورة',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'أي رسالة واردة من رقم محظور، أو تحتوي رقمه في النص، تُرفض قبل التحليل ولا يُقي’د إيداع.',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      color: kayan.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: '7xxxxxxxx',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          style: const TextStyle(fontFamily: 'Tajawal'),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _add,
                        child: const Text(
                          'حظر',
                          style: TextStyle(fontFamily: 'Tajawal'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_phones.isEmpty)
                    Text(
                      'لا توجد أرقام محظورة.',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        color: kayan.textSecondary,
                      ),
                    )
                  else
                    ..._phones.map(
                      (p) => Card(
                        child: ListTile(
                          title: Text(
                            p,
                            style: const TextStyle(fontFamily: 'Tajawal'),
                          ),
                          trailing: IconButton(
                            tooltip: 'إلغاء الحظر',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : () => _remove(p),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
